//
//  AdminSessionService.swift
//  CleanMyOwn
//
//  Sesión "admin" persistente dentro del proceso de la app.
//
//  Aproximación: mantenemos un único `AuthorizationRef` vivo en memoria del
//  proceso. Cuando el usuario activa la sesión, llamamos
//  `AuthorizationCreate` + `AuthorizationCopyRights` con el right
//  `system.privilege.admin` y `interactionAllowed`. macOS muestra el prompt
//  nativo de password una sola vez. Mientras el `AuthorizationRef` viva
//  (y no llamemos `AuthorizationFree`), `AuthorizationExecuteWithPrivileges`
//  reutiliza esa autorización sin pedir password de nuevo.
//
//  IMPORTANTE: `osascript ... with administrator privileges` lanzado desde
//  procesos osascript independientes NO comparte el cache de auth porque cada
//  invocación crea su propio `AuthorizationRef` y lo descarta al terminar.
//  Por eso aquí mantenemos UN ref propio durante toda la sesión.
//
//  `AuthorizationExecuteWithPrivileges` está marcada como deprecated desde
//  10.7 pero sigue disponible y funcional. Lo importamos vía `@_silgen_name`
//  ya que Swift no expone su declaración pública.
//
//  La API no expone ni el PID del hijo ni su exit code. Para recuperarlos,
//  todo se ejecuta a través de un wrapper `/bin/sh -c` que emite por el pipe
//  dos marcadores: su PID (primera línea) y el exit code real del tool
//  (última línea). El tool y sus argumentos viajan como parámetros
//  posicionales ($0/$@), que el shell nunca interpreta → sin inyección.
//  Con el PID podemos reapear EXACTAMENTE ese hijo; un `waitpid(-1)` global
//  robaría el exit status de otros `Process` (mdfind, simctl, launchctl)
//  que Foundation gestiona en paralelo.
//

import AppKit
import Foundation
import Security

@_silgen_name("AuthorizationExecuteWithPrivileges")
private func _AuthorizationExecuteWithPrivileges(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ options: AuthorizationFlags,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>?>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus

@MainActor
final class AdminSessionService: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastError: String?

    /// Ref vivo durante la sesión. Mientras no se libere, las llamadas
    /// privilegiadas reutilizan la autorización sin pedir password.
    private var authRef: AuthorizationRef?

    struct PrivilegedResult {
        let exitCode: Int32
        let output: String
        var success: Bool { exitCode == 0 }
    }

    // MARK: - Activación / desactivación

    @discardableResult
    func activate() async -> Bool {
        if authRef != nil { isActive = true; return true }

        var ref: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &ref)
        guard createStatus == errAuthorizationSuccess, let ref else {
            lastError = "No se pudo crear AuthorizationRef (\(createStatus))"
            isActive = false
            return false
        }

        // Solicitar el right `system.privilege.admin` con interacción.
        let acquired = await Task.detached(priority: .userInitiated) {
            "system.privilege.admin".withCString { rightCString -> Bool in
                let mutable = UnsafeMutablePointer<CChar>(mutating: rightCString)
                var item = AuthorizationItem(name: mutable, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { itemPtr in
                    var rights = AuthorizationRights(count: 1, items: itemPtr)
                    let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
                    let status = AuthorizationCopyRights(ref, &rights, nil, flags, nil)
                    return status == errAuthorizationSuccess
                }
            }
        }.value

        if acquired {
            self.authRef = ref
            self.isActive = true
            self.lastError = nil
            return true
        } else {
            AuthorizationFree(ref, [.destroyRights])
            self.authRef = nil
            self.isActive = false
            self.lastError = "Autorización cancelada o denegada."
            return false
        }
    }

    func deactivate() {
        if let ref = authRef {
            AuthorizationFree(ref, [.destroyRights])
        }
        authRef = nil
        isActive = false
    }

    // MARK: - Full Disk Access

    /// Comprueba si el proceso actual tiene Full Disk Access. Lo determina
    /// intentando abrir `/Library/Application Support/com.apple.TCC/TCC.db`,
    /// archivo que sólo es legible con FDA concedido.
    static func hasFullDiskAccess() -> Bool {
        let probe = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        guard FileManager.default.fileExists(atPath: probe.path) else {
            // En sistemas raros donde no exista el archivo, asumir que no
            return false
        }
        do {
            let handle = try FileHandle(forReadingFrom: probe)
            try? handle.close()
            return true
        } catch {
            return false
        }
    }

    /// Abre el panel de Configuración del Sistema → Privacidad y seguridad →
    /// Acceso completo al disco. El usuario tiene que añadir CleanMyOwn ahí.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
            return
        }
        // Fallback (Settings antiguo)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ejecución privilegiada

    /// Ejecuta `tool args...` como root usando la autorización ya obtenida.
    /// No vuelve a pedir password mientras `authRef` siga vivo.
    @discardableResult
    func runPrivileged(_ tool: String, _ args: [String]) async -> PrivilegedResult {
        guard let ref = authRef else {
            return PrivilegedResult(exitCode: -1, output: "Sin autorización admin (activa el modo administrador)")
        }
        return await Task.detached(priority: .userInitiated) {
            Self.execute(ref: ref, tool: tool, args: args)
        }.value
    }

    /// Borra varios paths con `/bin/rm -rf` en una sola invocación privilegiada.
    /// Defensa en profundidad: sólo se aceptan paths dentro de las raíces que
    /// la app realmente limpia; cualquier otro se rechaza y se reporta.
    @discardableResult
    func removeAsRoot(paths: [String]) async -> PrivilegedResult {
        guard !paths.isEmpty else { return PrivilegedResult(exitCode: 0, output: "") }

        let allowed = paths.filter { Self.isAllowedRootRemovalPath($0) }
        let rejected = paths.filter { !Self.isAllowedRootRemovalPath($0) }

        var notes: [String] = []
        if !rejected.isEmpty {
            notes.append("Rechazados por seguridad (fuera de las rutas que CleanMyOwn limpia): "
                         + rejected.joined(separator: ", "))
        }
        guard !allowed.isEmpty else {
            return PrivilegedResult(exitCode: -1, output: notes.joined(separator: "\n"))
        }

        let result = await runPrivileged("/bin/rm", ["-rf", "--"] + allowed)
        let output = (notes + [result.output]).filter { !$0.isEmpty }.joined(separator: "\n")
        return PrivilegedResult(exitCode: result.exitCode, output: output)
    }

    /// Raíces bajo las que se permite borrar como root. Dos niveles:
    ///  - `containerRoots`: sólo descendientes ESTRICTOS (nunca la raíz misma).
    ///  - `exactRoots`: cachés dev regenerables — la raíz misma también es borrable.
    /// Coincide con lo que producen JunkScanService y AppCatalogService.
    nonisolated static func isAllowedRootRemovalPath(
        _ rawPath: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard rawPath.hasPrefix("/") else { return false }
        let url = URL(fileURLWithPath: rawPath)
        // Sin componentes relativos: nada de "." ni ".." en el path.
        let components = url.pathComponents
        guard !components.contains("..") && !components.contains(".") else { return false }
        let path = url.path
        guard path != "/" else { return false }

        let homePath = home.path

        let containerRoots = [
            homePath + "/Library",
            homePath + "/.Trash",
            homePath + "/Applications",
            "/Applications"
        ]
        for root in containerRoots where path != root && path.hasPrefix(root + "/") {
            return true
        }

        let exactRoots = [
            ".npm", ".yarn/cache",
            ".cargo/registry/cache", ".cargo/registry/src", ".rustup/downloads",
            ".gradle/caches", ".m2/repository", ".cocoapods/repos",
            ".bundle/cache", ".composer/cache",
            "go/pkg/mod/cache", ".pnpm-state"
        ].map { homePath + "/" + $0 }
        for root in exactRoots where path == root || path.hasPrefix(root + "/") {
            return true
        }
        return false
    }

    // MARK: - Núcleo: AuthorizationExecuteWithPrivileges

    nonisolated private static let pidMarker = "__CMO_PID__:"
    nonisolated private static let exitMarker = "__CMO_EXIT__:"

    nonisolated private static func execute(ref: AuthorizationRef, tool: String, args: [String]) -> PrivilegedResult {
        // Wrapper: 1ª línea = PID del sh, luego stdout+stderr del tool,
        // última línea = exit code real. tool/args son posicionales: el
        // shell no los parsea. El printf antepone \n para que el marcador
        // empiece en línea propia aunque el tool no termine su salida con
        // salto de línea ($? se captura ANTES, echo/printf lo resetearían).
        let script = "echo \"\(pidMarker)$$\"; \"$0\" \"$@\" 2>&1; s=$?; printf '\\n\(exitMarker)%d\\n' \"$s\""
        let shellArgs = ["-c", script, tool] + args

        var cStrings: [UnsafeMutablePointer<CChar>?] = shellArgs.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil { free(ptr) }
        }

        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = "/bin/sh".withCString { shellPath in
            cStrings.withUnsafeMutableBufferPointer { buf in
                _AuthorizationExecuteWithPrivileges(
                    ref,
                    shellPath,
                    [],
                    buf.baseAddress!,
                    &pipe
                )
            }
        }

        if status != errAuthorizationSuccess {
            return PrivilegedResult(exitCode: Int32(status),
                                    output: "AuthorizationExecuteWithPrivileges falló (status=\(status))")
        }

        var childPID: pid_t?
        var exitCode: Int32?
        var outputLines: [String] = []

        if let pipe {
            let bufSize = 4096
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            // fgets corta en \n o al llenar el buffer: acumular hasta tener
            // líneas completas para no partir un marcador por la mitad.
            var pending = ""
            while fgets(buf, Int32(bufSize), pipe) != nil {
                pending += String(cString: buf)
                while let nl = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<nl])
                    pending = String(pending[pending.index(after: nl)...])
                    classify(line: line, childPID: &childPID, exitCode: &exitCode, output: &outputLines)
                }
            }
            if !pending.isEmpty {
                classify(line: pending, childPID: &childPID, exitCode: &exitCode, output: &outputLines)
            }
            fclose(pipe)
        }

        // EOF en el pipe ⇒ el wrapper terminó. Reapear sólo ESE pid.
        if let pid = childPID {
            var st: Int32 = 0
            while waitpid(pid, &st, 0) == -1 && errno == EINTR { /* reintentar */ }
        }

        // Sin marcador de exit no podemos afirmar éxito: reportar fallo y que
        // el caller verifique por su cuenta (fileExists) si aplica.
        return PrivilegedResult(
            exitCode: exitCode ?? -1,
            output: outputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// El PID lo fija la PRIMERA línea con marcador (el wrapper la emite antes
    /// que nada); el exit code lo fija la ÚLTIMA (el wrapper la emite al final),
    /// así un tool que imprima texto parecido no puede falsearlos.
    nonisolated static func classify(
        line: String,
        childPID: inout pid_t?,
        exitCode: inout Int32?,
        output: inout [String]
    ) {
        if childPID == nil, line.hasPrefix(pidMarker),
           let value = pid_t(line.dropFirst(pidMarker.count).trimmingCharacters(in: .whitespaces)) {
            childPID = value
            return
        }
        if line.hasPrefix(exitMarker),
           let value = Int32(line.dropFirst(exitMarker.count).trimmingCharacters(in: .whitespaces)) {
            exitCode = value
            return
        }
        output.append(line)
    }
}
