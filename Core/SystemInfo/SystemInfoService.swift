//
//  SystemInfoService.swift
//  CleanMyOwn
//
//  Obtiene información del sistema usando APIs nativas de macOS.
//  Sin dependencias externas. Todo aquí es read-only y seguro.
//

import Foundation

/// Snapshot de info del sistema en un momento dado.
struct SystemSnapshot {
    let totalDiskBytes: Int64
    let freeDiskBytes: Int64
    let totalMemoryBytes: UInt64
    let usedMemoryBytes: UInt64
    let cpuUsagePercent: Double
    let modelName: String
    let osVersion: String

    var usedDiskBytes: Int64 { totalDiskBytes - freeDiskBytes }
    var diskUsageFraction: Double {
        guard totalDiskBytes > 0 else { return 0 }
        return Double(usedDiskBytes) / Double(totalDiskBytes)
    }
    var memoryUsageFraction: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return Double(usedMemoryBytes) / Double(totalMemoryBytes)
    }
}

/// Ticks acumulados de CPU desde el boot (natural_t = UInt32, puede dar la
/// vuelta; los deltas se calculan con aritmética modular).
struct CPUTicks: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

@MainActor
final class SystemInfoService: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?

    private var refreshTask: Task<Void, Never>?

    /// Muestra anterior de ticks de CPU. El % de uso es el delta entre dos
    /// muestras consecutivas; los ticks absolutos son acumulados desde el
    /// boot y darían un promedio histórico casi constante.
    private var previousCPUTicks: CPUTicks?

    /// Inicia un refresco periódico cada `interval` segundos.
    func startAutoRefresh(interval: TimeInterval = 2.0) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                self.snapshot = self.capture()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Captura sincrónica del estado

    private func capture() -> SystemSnapshot {
        let ticks = Self.readCPUTicks()
        let cpu = Self.cpuUsage(current: ticks, previous: previousCPUTicks)
        if let ticks { previousCPUTicks = ticks }
        return SystemSnapshot(
            totalDiskBytes: Self.diskTotal(),
            freeDiskBytes: Self.diskFree(),
            totalMemoryBytes: Self.memoryTotal(),
            usedMemoryBytes: Self.memoryUsed(),
            cpuUsagePercent: cpu,
            modelName: Self.hardwareModel(),
            osVersion: Self.osVersionString()
        )
    }

    // MARK: - Disco

    private static func diskTotal() -> Int64 {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    private static func diskFree() -> Int64 {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Memoria

    private static func memoryTotal() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Memoria "usada" siguiendo la lógica de Activity Monitor:
    /// usedMem = active + wired + compressed
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(host, HOST_VM_INFO64, reboundPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return active + wired + compressed
    }

    // MARK: - CPU

    private static func readCPUTicks() -> CPUTicks? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuLoad) { loadPtr in
            loadPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(host, HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: cpuLoad.cpu_ticks.0,
            system: cpuLoad.cpu_ticks.1,
            idle: cpuLoad.cpu_ticks.2,
            nice: cpuLoad.cpu_ticks.3
        )
    }

    /// % de uso entre dos muestras consecutivas. Sin muestra previa (primer
    /// tick) cae al promedio desde el boot como semilla. Los deltas usan `&-`
    /// para sobrevivir el wraparound de UInt32.
    nonisolated static func cpuUsage(current: CPUTicks?, previous: CPUTicks?) -> Double {
        guard let current else { return 0 }
        let user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
        if let previous {
            user = current.user &- previous.user
            system = current.system &- previous.system
            idle = current.idle &- previous.idle
            nice = current.nice &- previous.nice
        } else {
            (user, system, idle, nice) = (current.user, current.system, current.idle, current.nice)
        }
        let total = Double(user) + Double(system) + Double(idle) + Double(nice)
        guard total > 0 else { return 0 }
        return (Double(user) + Double(system) + Double(nice)) / total * 100.0
    }

    // MARK: - Hardware / OS

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private static func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

// MARK: - Helpers de formato

extension Int64 {
    /// Formatea bytes como "120.5 GB", "1.2 TB", etc.
    var formattedAsBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension UInt64 {
    var formattedAsBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
