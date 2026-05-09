//
//  MemoryService.swift
//  CleanMyOwn
//
//  Lectura detallada de la memoria física e invocación de `purge` con
//  privilegios administrativos para liberar páginas inactivas/comprimidas.
//

import Foundation
import SwiftUI

struct MemoryStats {
    let totalBytes: UInt64
    let appBytes: UInt64        // active + wired (procesos)
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64     // file-backed inactive + speculative + purgeable
    let freeBytes: UInt64

    var usedBytes: UInt64 { appBytes + compressedBytes + wiredBytes - wiredBytes /* avoid double */ }
    /// Memoria considerada "presionada" para Activity Monitor: app + wired + compressed
    var pressureBytes: UInt64 { appBytes + compressedBytes }
    var pressureFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(pressureBytes) / Double(totalBytes)
    }
}

@MainActor
final class MemoryService: ObservableObject {
    @Published private(set) var stats: MemoryStats?
    @Published private(set) var isPurging = false
    @Published private(set) var lastFreedBytes: Int64 = 0
    @Published private(set) var lastError: String?

    private var ticker: Task<Void, Never>?

    func startAutoRefresh(interval: TimeInterval = 1.5) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.stats = Self.capture()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        ticker?.cancel()
        ticker = nil
    }

    /// Ejecuta `sudo purge` solicitando privilegios al usuario vía AppleScript.
    /// Devuelve los bytes liberados (puede ser negativo si las apps aprovechan inmediatamente).
    func purge() async {
        guard !isPurging else { return }
        isPurging = true
        lastError = nil

        let before = Self.capture()

        let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        let result = await Task.detached(priority: .userInitiated) {
            Self.runOSAScript(script)
        }.value

        // Esperar un poco a que el sistema reorganice
        try? await Task.sleep(nanoseconds: 800_000_000)
        let after = Self.capture()

        if result.exitCode == 0 {
            let beforeUsed = Int64(before.appBytes + before.compressedBytes + before.wiredBytes)
            let afterUsed = Int64(after.appBytes + after.compressedBytes + after.wiredBytes)
            lastFreedBytes = max(0, beforeUsed - afterUsed)
            stats = after
        } else {
            // Errores típicos: el usuario canceló (1) o password incorrecta
            let msg = result.stderr.isEmpty ? "Operación cancelada o sin permisos." : result.stderr
            lastError = msg
        }
        isPurging = false
    }

    // MARK: - Captura

    nonisolated static func capture() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryStats(totalBytes: total, appBytes: 0, wiredBytes: 0, compressedBytes: 0, cachedBytes: 0, freeBytes: 0)
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize - speculative

        // Activity Monitor: "App Memory" = active - file-backed - purgeable
        let appMem = active > purgeable ? active - purgeable : active
        let cached = inactive + speculative + purgeable

        return MemoryStats(
            totalBytes: total,
            appBytes: appMem,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free
        )
    }

    // MARK: - osascript helper

    struct OSAResult { let exitCode: Int32; let stdout: String; let stderr: String }

    nonisolated private static func runOSAScript(_ script: String) -> OSAResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return OSAResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        return OSAResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
