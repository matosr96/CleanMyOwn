//
//  main.swift
//  CleanMyOwnHelper
//
//  Daemon privilegiado lanzado por launchd vía SMAppService.daemon. Corre
//  como root y expone los verbos de HelperXPCProtocol por XPC.
//
//  Modelo de seguridad (en orden de importancia):
//   1. Verbos estrechos — no existe "ejecuta este comando"; sólo borrar
//      dentro de la allowlist, borrar un snapshot con formato validado, y purge.
//   2. Allowlist evaluada AQUÍ (lado servidor) con el HOME derivado del euid
//      del cliente vía getpwuid — nunca de un path que el cliente declare.
//   3. Sólo acepta conexiones del usuario de consola (dueño de /dev/console),
//      jamás de root u otros usuarios.
//   4. Requirement de firma sobre el cliente. Con firma ad-hoc esto sólo
//      ancla el identifier (límite documentado en el README) — por eso los
//      puntos 1-3 son la defensa real.
//

import CleanMyOwnShared
import Foundation

/// Objeto exportado a UNA conexión. Guarda el uid del cliente validado al
/// aceptar la conexión; todos los verbos derivan el home de ese uid.
final class HelperService: NSObject, HelperXPCProtocol {
    private let clientUID: uid_t

    init(clientUID: uid_t) {
        self.clientUID = clientUID
    }

    private var clientHome: URL? {
        guard let pw = getpwuid(clientUID) else { return nil }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }

    func version(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.version)
    }

    func removeItems(paths: [String], reply: @escaping (Int32, String) -> Void) {
        guard let home = clientHome else {
            reply(-1, "No se pudo resolver el home del usuario cliente")
            return
        }
        let allowed = paths.filter { RootRemovalPolicy.isAllowed($0, home: home) }
        let rejected = paths.filter { !RootRemovalPolicy.isAllowed($0, home: home) }

        var notes: [String] = []
        if !rejected.isEmpty {
            notes.append("Rechazados por la allowlist del helper: " + rejected.joined(separator: ", "))
        }
        guard !allowed.isEmpty else {
            reply(-1, notes.joined(separator: "\n"))
            return
        }
        let result = ShellRunner.runSync("/bin/rm", ["-rf", "--"] + allowed)
        let output = (notes + [result.stdout, result.stderr])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        reply(result.exitCode, output)
    }

    func deleteTimeMachineSnapshot(date: String, reply: @escaping (Int32, String) -> Void) {
        guard HelperValidation.isValidSnapshotDate(date) else {
            reply(-1, "Identificador de snapshot inválido: \(date)")
            return
        }
        let result = ShellRunner.runSync("/usr/bin/tmutil", ["deletelocalsnapshots", date])
        reply(result.exitCode, [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    func purgeMemory(reply: @escaping (Int32, String) -> Void) {
        let result = ShellRunner.runSync("/usr/sbin/purge", [])
        reply(result.exitCode, [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Sólo el usuario con la sesión gráfica (dueño de /dev/console).
        var consoleStat = stat()
        guard stat("/dev/console", &consoleStat) == 0 else { return false }
        let consoleUID = consoleStat.st_uid
        let clientUID = newConnection.effectiveUserIdentifier
        guard clientUID == consoleUID, clientUID != 0 else { return false }

        // Si el requirement es inválido o el cliente no lo cumple, el sistema
        // invalida la conexión antes de entregar mensajes.
        newConnection.setCodeSigningRequirement(HelperConstants.clientCodeSigningRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = HelperService(clientUID: clientUID)
        newConnection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
