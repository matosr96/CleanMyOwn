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

import CleanMyOwnShared
import AppKit
import Foundation
import Security
import ServiceManagement

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
    /// Estado del helper privilegiado (SMAppService.daemon). `.enabled`
    /// significa instalado Y aprobado en Ajustes → ítems en segundo plano.
    @Published private(set) var helperStatus: SMAppService.Status = .notRegistered

    /// Ref vivo durante la sesión. Mientras no se libere, las llamadas
    /// privilegiadas reutilizan la autorización sin pedir password.
    private var authRef: AuthorizationRef?

    /// Daemon registrable vía SMAppService (plist en Contents/Library/LaunchDaemons).
    private let helperDaemon = SMAppService.daemon(plistName: HelperConstants.plistName)
    private var helperConnection: NSXPCConnection?

    var helperEnabled: Bool { helperStatus == .enabled }

    init() {
        refreshHelperStatus()
    }

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

    /// ¿Hay alguna vía de escalado disponible? (sesión AEWP activa o helper
    /// instalado y aprobado). Las vistas y servicios usan esto para decidir
    /// si hace falta pedir contraseña antes de operar.
    var canEscalate: Bool { isActive || helperEnabled }

    /// Borra varios paths con `/bin/rm -rf` en una sola invocación privilegiada.
    /// Defensa en profundidad: sólo se aceptan paths dentro de las raíces que
    /// la app realmente limpia (`RootRemovalPolicy`); cualquier otro se rechaza
    /// y se reporta. El helper, si está activo, re-valida en su lado.
    @discardableResult
    func removeAsRoot(paths: [String]) async -> PrivilegedResult {
        guard !paths.isEmpty else { return PrivilegedResult(exitCode: 0, output: "") }

        let allowed = paths.filter { RootRemovalPolicy.isAllowed($0) }
        let rejected = paths.filter { !RootRemovalPolicy.isAllowed($0) }

        var notes: [String] = []
        if !rejected.isEmpty {
            notes.append("Rechazados por seguridad (fuera de las rutas que CleanMyOwn limpia): "
                         + rejected.joined(separator: ", "))
        }
        guard !allowed.isEmpty else {
            return PrivilegedResult(exitCode: -1, output: notes.joined(separator: "\n"))
        }

        let result: PrivilegedResult
        if helperEnabled {
            result = await callHelper { proxy, reply in
                proxy.removeItems(paths: allowed, reply: reply)
            }
        } else {
            result = await runPrivileged("/bin/rm", ["-rf", "--"] + allowed)
        }
        let output = (notes + [result.output]).filter { !$0.isEmpty }.joined(separator: "\n")
        return PrivilegedResult(exitCode: result.exitCode, output: output)
    }

    /// Borra un snapshot local de Time Machine (helper si está activo; si no,
    /// `tmutil` vía la sesión AEWP).
    @discardableResult
    func deleteTMSnapshot(date: String) async -> PrivilegedResult {
        if helperEnabled {
            return await callHelper { proxy, reply in
                proxy.deleteTimeMachineSnapshot(date: date, reply: reply)
            }
        }
        return await runPrivileged("/usr/bin/tmutil", ["deletelocalsnapshots", date])
    }

    /// Ejecuta `/usr/sbin/purge` (helper si está activo; si no, sesión AEWP).
    @discardableResult
    func runPurge() async -> PrivilegedResult {
        if helperEnabled {
            return await callHelper { proxy, reply in
                proxy.purgeMemory(reply: reply)
            }
        }
        return await runPrivileged("/usr/sbin/purge", [])
    }

    // MARK: - Helper privilegiado (SMAppService.daemon)

    func refreshHelperStatus() {
        helperStatus = helperDaemon.status
    }

    /// Registra el daemon. La primera vez macOS lo deja en `.requiresApproval`
    /// y hay que aprobarlo en Ajustes del Sistema → General → Ítems de inicio
    /// y extensiones → Permitir en segundo plano.
    func registerHelper() {
        do {
            try helperDaemon.register()
        } catch {
            // SMAppService lanza error mientras el usuario no apruebe; el
            // estado real queda en `status`.
            refreshHelperStatus()
            if helperStatus == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                lastError = "No se pudo registrar el helper: \(error.localizedDescription)"
            }
            return
        }
        refreshHelperStatus()
    }

    func unregisterHelper() {
        try? helperDaemon.unregister()
        helperConnection?.invalidate()
        helperConnection = nil
        refreshHelperStatus()
    }

    func openHelperApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Continuación que sólo puede reanudarse una vez: la reply del proxy y el
    /// error handler de la conexión son excluyentes en XPC, pero ante un bug
    /// del transporte preferimos perder una respuesta a crashear por doble resume.
    private final class ResumeOnce<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ c: CheckedContinuation<T, Never>) { continuation = c }
        func resume(_ value: T) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    private func helperXPCConnection() -> NSXPCConnection {
        if let existing = helperConnection { return existing }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.helperConnection = nil }
        }
        connection.resume()
        helperConnection = connection
        return connection
    }

    private func callHelper(
        _ body: @escaping (HelperXPCProtocol, @escaping (Int32, String) -> Void) -> Void
    ) async -> PrivilegedResult {
        let connection = helperXPCConnection()
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let raw = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(PrivilegedResult(exitCode: -1,
                                             output: "XPC con el helper falló: \(error.localizedDescription)"))
            }
            guard let proxy = raw as? HelperXPCProtocol else {
                once.resume(PrivilegedResult(exitCode: -1, output: "Proxy XPC inválido"))
                return
            }
            body(proxy) { code, output in
                once.resume(PrivilegedResult(exitCode: code, output: output))
            }
        }
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
