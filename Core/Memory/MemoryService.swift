//
//  MemoryService.swift
//  CleanMyOwn
//
//  Lectura detallada de la memoria física e invocación de `purge` a través
//  de la sesión admin compartida (AdminSessionService) para liberar páginas
//  inactivas/comprimidas sin pedir la contraseña en cada uso.
//

import Foundation
import SwiftUI

struct MemoryStats {
    let totalBytes: UInt64
    let appBytes: UInt64        // active - purgeable (memoria de procesos)
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64     // file-backed inactive + speculative + purgeable
    let freeBytes: UInt64

    /// Memoria "usada" como la reporta Activity Monitor: app + wired + comprimida.
    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
    /// Memoria considerada "presionada" para Activity Monitor: app + compressed
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

    /// Ejecuta `purge` como root vía la sesión admin compartida (la activa si
    /// hace falta — un único prompt nativo por sesión). osascript NO sirve
    /// aquí: cada invocación crea su propio AuthorizationRef y volvería a
    /// pedir la contraseña aunque la sesión admin esté activa.
    func purge(adminSession: AdminSessionService) async {
        guard !isPurging else { return }
        isPurging = true
        lastError = nil

        let before = Self.capture()

        if !adminSession.canEscalate {
            let ok = await adminSession.activate()
            guard ok else {
                lastError = adminSession.lastError ?? "Autorización cancelada o sin permisos."
                isPurging = false
                return
            }
        }
        let result = await adminSession.runPurge()

        // Esperar un poco a que el sistema reorganice
        try? await Task.sleep(nanoseconds: 800_000_000)
        let after = Self.capture()

        if result.success {
            lastFreedBytes = max(0, Int64(before.usedBytes) - Int64(after.usedBytes))
            stats = after
        } else {
            lastError = result.output.isEmpty ? "No se pudo ejecutar purge." : result.output
        }
        isPurging = false
    }

    // MARK: - Captura

    nonisolated static func capture() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
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

}
