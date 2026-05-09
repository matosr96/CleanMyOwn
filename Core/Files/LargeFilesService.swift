//
//  LargeFilesService.swift
//  CleanMyOwn
//
//  Escanea una carpeta raíz buscando archivos por encima de un umbral de tamaño,
//  y opcionalmente detecta duplicados por hash SHA256.
//
//  Para evitar hashear todo, los duplicados se calculan así:
//    1. Agrupar candidatos por tamaño exacto
//    2. Para grupos de >=2 archivos, hashear sólo los primeros 1 MB (quick hash)
//    3. Para los que coinciden en quick hash, hash completo SHA256
//

import CryptoKit
import Foundation
import SwiftUI

struct LargeFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    let modifiedDate: Date?
    let isDirectory: Bool

    var displayName: String { url.lastPathComponent }
    var parentDir: String { url.deletingLastPathComponent().path }

    static func == (lhs: LargeFile, rhs: LargeFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    let files: [LargeFile]
    /// Bytes desperdiciados: tamaño * (n - 1)
    var wastedBytes: Int64 {
        let size = files.first?.sizeBytes ?? 0
        return size * Int64(max(files.count - 1, 0))
    }
}

@MainActor
final class LargeFilesService: ObservableObject {
    @Published var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var minSizeBytes: Int64 = 100 * 1024 * 1024   // 100 MB

    @Published private(set) var files: [LargeFile] = []
    @Published private(set) var duplicates: [DuplicateGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isHashing = false
    @Published private(set) var progressLabel = ""
    @Published private(set) var lastError: String?

    @Published var selection: Set<UUID> = []

    var selectedBytes: Int64 {
        files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    var totalWastedBytes: Int64 { duplicates.reduce(0) { $0 + $1.wastedBytes } }

    private var scanTask: Task<Void, Never>?

    func startScan() {
        scanTask?.cancel()
        files = []
        duplicates = []
        selection = []
        isScanning = true
        progressLabel = "Iniciando escaneo…"

        let root = rootURL
        let threshold = minSizeBytes

        scanTask = Task { [weak self] in
            guard let self else { return }
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.scan(root: root, minBytes: threshold)
            }.value
            self.files = scanned.sorted { $0.sizeBytes > $1.sizeBytes }
            self.selection = []
            self.isScanning = false
            self.progressLabel = "\(scanned.count) archivos encontrados"
        }
    }

    func computeDuplicates() {
        guard !files.isEmpty else { return }
        isHashing = true
        progressLabel = "Calculando duplicados…"
        let snapshot = files

        Task { [weak self] in
            guard let self else { return }
            let groups = await Task.detached(priority: .userInitiated) {
                Self.findDuplicates(among: snapshot)
            }.value
            self.duplicates = groups.sorted { $0.wastedBytes > $1.wastedBytes }
            self.isHashing = false
            self.progressLabel = "\(groups.count) grupos de duplicados"
        }
    }

    @discardableResult
    func deleteSelected() async -> Int64 {
        let toRemove = files.filter { selection.contains($0.id) }
        var freed: Int64 = 0
        var removedIDs: Set<UUID> = []
        var failures: [String] = []
        for f in toRemove {
            do {
                try FileManager.default.removeItem(at: f.url)
                freed += f.sizeBytes
                removedIDs.insert(f.id)
            } catch {
                failures.append("\(f.displayName): \(error.localizedDescription)")
            }
        }
        files.removeAll { removedIDs.contains($0.id) }
        duplicates = duplicates.compactMap { g in
            let remaining = g.files.filter { !removedIDs.contains($0.id) }
            return remaining.count >= 2 ? DuplicateGroup(hash: g.hash, files: remaining) : nil
        }
        selection.subtract(removedIDs)
        if !failures.isEmpty {
            lastError = failures.prefix(5).joined(separator: "\n")
        } else {
            lastError = nil
        }
        return freed
    }

    func toggle(_ file: LargeFile) {
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    /// Selecciona todos los archivos duplicados excepto el más antiguo (mantiene un original).
    func autoSelectDuplicatesKeepingOldest() {
        var toSelect = Set<UUID>()
        for group in duplicates {
            let sorted = group.files.sorted { ($0.modifiedDate ?? .distantFuture) < ($1.modifiedDate ?? .distantFuture) }
            for f in sorted.dropFirst() { toSelect.insert(f.id) }
        }
        selection = toSelect
    }

    // MARK: - Estáticos: scan y hashing

    nonisolated private static func scan(root: URL, minBytes: Int64) -> [LargeFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isPackageKey]

        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                     errorHandler: { _, _ in true }) else { return [] }

        var found: [LargeFile] = []
        for case let u as URL in en {
            // Saltar paths del sistema dentro del home (ya raros, pero por si acaso)
            if u.path.contains("/.Trash/") { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { continue }
            let isDir = v?.isDirectory ?? false
            // Si es un .app o paquete, contar como UN item
            if isDir && (v?.isPackage == true || u.pathExtension == "app") {
                let total = directorySize(at: u)
                if total >= minBytes {
                    found.append(LargeFile(
                        url: u, sizeBytes: total,
                        modifiedDate: v?.contentModificationDate,
                        isDirectory: true
                    ))
                }
                en.skipDescendants()
                continue
            }
            if isDir { continue }
            let size = Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
            if size >= minBytes {
                found.append(LargeFile(
                    url: u, sizeBytes: size,
                    modifiedDate: v?.contentModificationDate,
                    isDirectory: false
                ))
            }
        }
        return found
    }

    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles],
                                     errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true { continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    nonisolated private static func findDuplicates(among files: [LargeFile]) -> [DuplicateGroup] {
        // Agrupar por size
        var bySize: [Int64: [LargeFile]] = [:]
        for f in files where !f.isDirectory {
            bySize[f.sizeBytes, default: []].append(f)
        }
        var groups: [DuplicateGroup] = []
        for (_, candidates) in bySize where candidates.count >= 2 {
            // Quick hash (primeros 1 MB)
            var byQuick: [String: [LargeFile]] = [:]
            for f in candidates {
                if let h = quickHash(url: f.url) {
                    byQuick[h, default: []].append(f)
                }
            }
            for (_, qSet) in byQuick where qSet.count >= 2 {
                // Full hash
                var byFull: [String: [LargeFile]] = [:]
                for f in qSet {
                    if let h = fullHash(url: f.url) {
                        byFull[h, default: []].append(f)
                    }
                }
                for (h, set) in byFull where set.count >= 2 {
                    groups.append(DuplicateGroup(hash: h, files: set))
                }
            }
        }
        return groups
    }

    nonisolated private static func quickHash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        return Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func fullHash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 4 * 1024 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }
}
