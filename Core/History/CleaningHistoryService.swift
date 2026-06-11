//
//  CleaningHistoryService.swift
//  CleanMyOwn
//
//  Registro persistente de TODO lo que la app limpió: cuándo, qué, cuánto y
//  en qué modo. En una categoría donde el miedo nº1 es "¿qué me borró esta
//  app?", el historial es confianza — y la confianza es el producto.
//
//  Persistencia: JSON en ~/Library/Application Support/CleanMyOwn/history.json
//  (Codable, cap de 200 entradas, escritura atómica).
//

import Foundation

struct CleaningRecord: Identifiable, Codable {
    enum Kind: String, Codable {
        case junk          // Limpieza (Smart Scan)
        case uninstall     // Desinstalador
        case largeFiles    // Archivos grandes
        case memory        // Liberar RAM
        case maintenance   // Tareas de mantenimiento

        var displayName: String {
            switch self {
            case .junk: return "Limpieza"
            case .uninstall: return "Desinstalación"
            case .largeFiles: return "Archivos grandes"
            case .memory: return "Memoria"
            case .maintenance: return "Mantenimiento"
            }
        }

        var icon: String {
            switch self {
            case .junk: return "trash.fill"
            case .uninstall: return "shippingbox.fill"
            case .largeFiles: return "doc.zipper"
            case .memory: return "memorychip.fill"
            case .maintenance: return "wrench.and.screwdriver.fill"
            }
        }
    }

    enum Mode: String, Codable {
        case permanent
        case trash
        case none          // operaciones sin modo (memoria, mantenimiento)

        var displayName: String? {
            switch self {
            case .permanent: return "permanente"
            case .trash: return "a la Papelera"
            case .none: return nil
            }
        }
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    /// Bytes liberados (RAM en el caso de memoria; 0 si no aplica).
    let freedBytes: Int64
    /// Cantidad de elementos afectados (0 si no aplica).
    let itemCount: Int
    let mode: Mode
    /// Resumen humano: "7 categorías", "WhatsApp y 12 archivos", "Caché de DNS".
    let summary: String
}

@MainActor
final class CleaningHistoryService: ObservableObject {
    @Published private(set) var records: [CleaningRecord] = []

    /// Total liberado en disco desde que existe el historial (excluye RAM).
    var totalFreedDiskBytes: Int64 {
        records.filter { $0.kind != .memory }.reduce(0) { $0 + $1.freedBytes }
    }

    private static let maxRecords = 200

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CleanMyOwn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    /// Registra una operación. Ignora no-ops (nada liberado y nada afectado).
    func record(kind: CleaningRecord.Kind,
                freedBytes: Int64,
                itemCount: Int,
                mode: CleaningRecord.Mode,
                summary: String) {
        guard freedBytes > 0 || itemCount > 0 else { return }
        records.insert(
            CleaningRecord(date: Date(), kind: kind, freedBytes: freedBytes,
                           itemCount: itemCount, mode: mode, summary: summary),
            at: 0
        )
        if records.count > Self.maxRecords {
            records.removeLast(records.count - Self.maxRecords)
        }
        save()
    }

    func clear() {
        records = []
        save()
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([CleaningRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
