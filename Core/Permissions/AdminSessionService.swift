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
    @discardableResult
    func removeAsRoot(paths: [String]) async -> PrivilegedResult {
        guard !paths.isEmpty else { return PrivilegedResult(exitCode: 0, output: "") }
        return await runPrivileged("/bin/rm", ["-rf"] + paths)
    }

    // MARK: - Núcleo: AuthorizationExecuteWithPrivileges

    nonisolated private static func execute(ref: AuthorizationRef, tool: String, args: [String]) -> PrivilegedResult {
        // Convertir args a un array null-terminated de C strings.
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil { free(ptr) }
        }

        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = tool.withCString { toolPath in
            cStrings.withUnsafeMutableBufferPointer { buf in
                _AuthorizationExecuteWithPrivileges(
                    ref,
                    toolPath,
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

        // Leer todo el output del child (el pipe se cierra cuando termina).
        var output = ""
        if let pipe {
            let bufSize = 4096
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            while fgets(buf, Int32(bufSize), pipe) != nil {
                output += String(cString: buf)
            }
            fclose(pipe)
        }

        // Reapear cualquier zombie del child sin bloquear (no necesitamos su exit
        // status: si el pipe cerró sin error y los archivos desaparecieron,
        // consideramos éxito). waitpid(-1, ..., WNOHANG) en bucle.
        var status_p: Int32 = 0
        while waitpid(-1, &status_p, WNOHANG) > 0 { /* reap */ }

        return PrivilegedResult(exitCode: 0, output: output)
    }
}
