//
//  ShellRunner.swift
//  CleanMyOwnShared
//
//  Helper único para ejecutar binarios del sistema sin shell intermedio:
//  el ejecutable es siempre una ruta fija y los argumentos van como array,
//  así que no hay superficie de inyección.
//
//  Los pipes de stdout y stderr se leen HASTA EOF en paralelo y ANTES de
//  `waitUntilExit()`. Si se espera primero y el hijo escribe más que el
//  buffer del pipe (~64 KB), el hijo se bloquea escribiendo y la app espera
//  para siempre (deadlock clásico de NSTask). `mdfind` o `simctl list -j`
//  superan ese tamaño con facilidad.
//

import Foundation

public struct ShellResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ShellRunner {
    /// Ejecuta `tool args...` y espera a que termine. Seguro para salidas grandes.
    public static func runSync(_ tool: String, _ args: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // stderr en una cola aparte para que ninguno de los dos pipes se llene
        // mientras el otro espera EOF.
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            group.leave()
        }

        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        group.wait()
        process.waitUntilExit()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errBox.data, encoding: .utf8) ?? ""
        )
    }

    /// Variante async: ejecuta fuera del hilo llamante.
    public static func run(_ tool: String, _ args: [String]) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            runSync(tool, args)
        }.value
    }
}
