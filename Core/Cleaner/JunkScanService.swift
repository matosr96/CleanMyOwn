//
//  JunkScanService.swift
//  CleanMyOwn
//
//  Escanea distintas fuentes de basura del sistema:
//   • File-based — carpetas concretas (cachés, logs, papelera, Xcode...)
//   • Dev caches — npm, yarn, pip, Homebrew, Cargo, Gradle, Maven, etc.
//   • Cachés huérfanas — datos de apps que YA no están instaladas
//   • Time Machine snapshots locales — `tmutil` (requiere admin)
//   • Simuladores iOS obsoletos — `xcrun simctl`
//
//  ATENCIÓN: el borrado es PERMANENTE (`FileManager.removeItem`,
//  `tmutil deletelocalsnapshots`, `xcrun simctl delete`). La UI confirma con
//  alert destructivo antes de ejecutar.
//

import Foundation
import SwiftUI

// MARK: - Modelos

/// El tipo de operación para escanear esta categoría.
enum JunkScanKind {
    /// Categoría file-based clásica: una o más carpetas raíz.
    /// `listsChildren = true` -> cada hijo top-level es un item.
    /// `listsChildren = false` -> cada root es UN item.
    case fileBased(roots: [URL], listsChildren: Bool)

    /// Cachés de gestores de paquetes / herramientas dev. Cada path es un item.
    case devCaches(paths: [URL])

    /// Subdirectorios cuyo nombre es un bundle ID que ya no existe en /Applications.
    case orphanedAppData(directories: [URL])

    /// Snapshots locales de Time Machine. Requiere admin para borrarse.
    case timeMachineSnapshots

    /// Simuladores de iOS marcados como `isAvailable=false` por Xcode.
    case iOSSimulators
}

/// Identifica QUÉ es un item y cómo borrarlo.
enum JunkItemKind: Hashable {
    case file(URL)
    case localSnapshot(date: String)        // ej. "2026-05-08-123456"
    case simulator(udid: String)
}

/// Categoría de basura mostrada en la UI.
struct JunkCategory: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let icon: String
    let tint: Color
    let kind: JunkScanKind
    /// Si todas o algunas de sus operaciones de borrado requieren privilegios root.
    let requiresAdmin: Bool
    /// Si los items de esta categoría se marcan automáticamente tras el escaneo.
    /// Sólo debe ser `true` para datos regenerables (cachés, logs). Lo que se
    /// apoya en heurísticas (datos huérfanos) o no es regenerable (snapshots,
    /// simuladores) lo decide el usuario explícitamente.
    let preselectedByDefault: Bool
}

/// Un item escaneado.
struct JunkItem: Identifiable, Hashable {
    let id = UUID()
    let kind: JunkItemKind
    let displayName: String
    let detail: String?           // contexto adicional (path, fecha, etc.)
    let sizeBytes: Int64          // 0 si no es calculable (ej. snapshots TM)
    let isDirectory: Bool

    /// URL si el item es file-based, nil si no.
    var url: URL? {
        if case .file(let u) = kind { return u }
        return nil
    }

    static func == (lhs: JunkItem, rhs: JunkItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct JunkCategoryResult: Identifiable {
    let id: String
    let category: JunkCategory
    var items: [JunkItem]
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - Servicio

@MainActor
final class JunkScanService: ObservableObject {
    @Published private(set) var results: [JunkCategoryResult] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var scanProgressLabel: String = ""
    @Published private(set) var lastCleanedBytes: Int64 = 0
    @Published private(set) var lastError: String?

    @Published var selection: Set<UUID> = []

    // Los `Task.detached` no heredan la cancelación del task que los espera:
    // se guardan los handles para cancelarlos explícitamente al re-escanear.
    private var scanTask: Task<Void, Never>?
    private var scanWork: Task<[JunkItem], Never>?
    private var installedIDsWork: Task<Set<String>, Never>?

    var selectedBytes: Int64 {
        results.flatMap(\.items).filter { selection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }
    var totalBytes: Int64 { results.reduce(0) { $0 + $1.totalBytes } }

    /// ¿Algún item seleccionado requiere privilegios admin para borrarse?
    var selectionRequiresAdmin: Bool {
        for res in results where res.category.requiresAdmin {
            if res.items.contains(where: { selection.contains($0.id) }) { return true }
        }
        return false
    }

    // MARK: - Categorías predefinidas

    static let categories: [JunkCategory] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            JunkCategory(
                id: "user.caches",
                name: "Cachés de usuario",
                blurb: "Datos temporales que las apps regeneran automáticamente.",
                icon: "tray.2.fill",
                tint: Color(red: 0.30, green: 0.85, blue: 0.55),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Caches")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "user.logs",
                name: "Logs de aplicaciones",
                blurb: "Registros de diagnóstico del usuario.",
                icon: "doc.text.fill",
                tint: Color(red: 0.40, green: 0.70, blue: 1.0),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Logs")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "trash",
                name: "Papelera",
                blurb: "Archivos ya enviados a la papelera del sistema.",
                icon: "trash.fill",
                tint: Color(red: 1.0, green: 0.55, blue: 0.40),
                kind: .fileBased(roots: [home.appendingPathComponent(".Trash")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "xcode.derived",
                name: "Xcode · DerivedData",
                blurb: "Builds intermedios de Xcode. Se regeneran al compilar.",
                icon: "hammer.fill",
                tint: Color(red: 0.85, green: 0.50, blue: 1.0),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "xcode.archives",
                name: "Xcode · Archives antiguos",
                blurb: "Archivos .xcarchive de builds históricos.",
                icon: "archivebox.fill",
                tint: Color(red: 1.0, green: 0.65, blue: 0.20),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Developer/Xcode/Archives")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "xcode.devicesupport",
                name: "Xcode · iOS DeviceSupport",
                blurb: "Símbolos de versiones de iOS que ya no usas.",
                icon: "iphone",
                tint: Color(red: 0.30, green: 0.85, blue: 0.95),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "simulator.caches",
                name: "iOS Simulator · Cachés",
                blurb: "Datos temporales de simuladores de iOS.",
                icon: "ipad",
                tint: Color(red: 0.40, green: 0.55, blue: 1.0),
                kind: .fileBased(roots: [home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")], listsChildren: true),
                requiresAdmin: false,
                preselectedByDefault: true
            ),

            // ------ NUEVAS ------

            JunkCategory(
                id: "dev.caches",
                name: "Cachés de desarrollo",
                blurb: "npm, yarn, pnpm, pip, Homebrew, Cargo, Gradle, Maven, CocoaPods, Go.",
                icon: "hammer.circle.fill",
                tint: Color(red: 0.95, green: 0.60, blue: 0.30),
                kind: .devCaches(paths: [
                    home.appendingPathComponent(".npm"),
                    home.appendingPathComponent(".yarn/cache"),
                    home.appendingPathComponent("Library/pnpm-store"),
                    home.appendingPathComponent("Library/Caches/pip"),
                    home.appendingPathComponent("Library/Caches/Homebrew/downloads"),
                    home.appendingPathComponent("Library/Caches/Homebrew/api"),
                    home.appendingPathComponent(".cargo/registry/cache"),
                    home.appendingPathComponent(".cargo/registry/src"),
                    home.appendingPathComponent(".rustup/downloads"),
                    home.appendingPathComponent(".gradle/caches"),
                    home.appendingPathComponent(".m2/repository"),
                    home.appendingPathComponent(".cocoapods/repos"),
                    home.appendingPathComponent("Library/Caches/CocoaPods"),
                    home.appendingPathComponent(".bundle/cache"),
                    home.appendingPathComponent(".composer/cache"),
                    home.appendingPathComponent("Library/Caches/go-build"),
                    home.appendingPathComponent("go/pkg/mod/cache"),
                    home.appendingPathComponent(".pnpm-state"),
                    home.appendingPathComponent("Library/Caches/electron"),
                    home.appendingPathComponent("Library/Caches/electron-builder"),
                    home.appendingPathComponent("Library/Caches/Yarn")
                ]),
                requiresAdmin: false,
                preselectedByDefault: true
            ),
            JunkCategory(
                id: "orphan.appdata",
                name: "Datos de apps desinstaladas",
                blurb: "Cachés y soporte de apps cuyo bundle ID ya no está en /Applications.",
                icon: "questionmark.folder.fill",
                tint: Color(red: 1.0, green: 0.40, blue: 0.45),
                kind: .orphanedAppData(directories: [
                    home.appendingPathComponent("Library/Caches"),
                    home.appendingPathComponent("Library/Application Support"),
                    home.appendingPathComponent("Library/Preferences"),
                    home.appendingPathComponent("Library/Containers"),
                    home.appendingPathComponent("Library/HTTPStorages"),
                    home.appendingPathComponent("Library/WebKit"),
                    home.appendingPathComponent("Library/Logs"),
                    home.appendingPathComponent("Library/Saved Application State")
                ]),
                requiresAdmin: false,
                preselectedByDefault: false
            ),
            JunkCategory(
                id: "tm.snapshots",
                name: "Snapshots locales de Time Machine",
                blurb: "Backups locales del volumen / que ocupan espacio invisible.",
                icon: "clock.arrow.circlepath",
                tint: Color(red: 0.55, green: 0.75, blue: 1.0),
                kind: .timeMachineSnapshots,
                requiresAdmin: true,
                preselectedByDefault: false
            ),
            JunkCategory(
                id: "sim.obsolete",
                name: "Simuladores iOS obsoletos",
                blurb: "Simuladores de runtimes que Xcode actual ya no soporta.",
                icon: "iphone.slash",
                tint: Color(red: 0.85, green: 0.50, blue: 1.0),
                kind: .iOSSimulators,
                requiresAdmin: false,
                preselectedByDefault: false
            )
        ]
    }()

    // MARK: - Scan

    func startScan() {
        scanTask?.cancel()
        scanWork?.cancel()
        installedIDsWork?.cancel()
        results = []
        selection = []
        lastError = nil
        lastCleanedBytes = 0
        isScanning = true
        scanProgressLabel = "Iniciando escaneo…"

        scanTask = Task { [weak self] in
            guard let self else { return }
            // Pre-calcular bundle IDs instalados (lo necesita orphan detection)
            let idsWork = Task.detached(priority: .userInitiated) {
                Self.installedBundleIDs()
            }
            self.installedIDsWork = idsWork
            let installedIDs = await idsWork.value
            guard !Task.isCancelled else { return }

            var collected: [JunkCategoryResult] = []
            for category in Self.categories {
                if Task.isCancelled { return }
                self.scanProgressLabel = "Escaneando \(category.name)…"
                let work = Task.detached(priority: .userInitiated) {
                    Self.scanCategory(category, installedBundleIDs: installedIDs)
                }
                self.scanWork = work
                let items = await work.value
                guard !Task.isCancelled else { return }
                collected.append(JunkCategoryResult(id: category.id, category: category, items: items))
                self.results = collected
                // Sólo pre-marcar categorías seguras, y SUMANDO (formUnion):
                // reasignar todo el set pisaría lo que el usuario desmarcó
                // mientras el escaneo seguía corriendo.
                if category.preselectedByDefault {
                    self.selection.formUnion(items.map(\.id))
                }
            }
            self.isScanning = false
            self.scanProgressLabel = ""
        }
    }

    // MARK: - Scan dispatch

    nonisolated private static func scanCategory(_ category: JunkCategory, installedBundleIDs: Set<String>) -> [JunkItem] {
        let items: [JunkItem]
        switch category.kind {
        case .fileBased(let roots, let listsChildren):
            items = scanFileBased(roots: roots, listsChildren: listsChildren)
        case .devCaches(let paths):
            items = scanDevCaches(paths: paths)
        case .orphanedAppData(let dirs):
            items = scanOrphanedAppData(in: dirs, installed: installedBundleIDs)
        case .timeMachineSnapshots:
            items = scanTimeMachineSnapshots()
        case .iOSSimulators:
            items = scanIOSSimulators()
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Scanners individuales

    nonisolated private static func scanFileBased(roots: [URL], listsChildren: Bool) -> [JunkItem] {
        let fm = FileManager.default
        var items: [JunkItem] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            if listsChildren {
                // Sin .skipsHiddenFiles: lo que se lista es lo que se borra
                // (la Papelera puede contener items ocultos, por ejemplo).
                guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
                for child in children {
                    if Task.isCancelled { return items }
                    if child.lastPathComponent == ".DS_Store" { continue }
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let size = directorySize(at: child)
                    guard size > 0 else { continue }
                    items.append(JunkItem(kind: .file(child), displayName: child.lastPathComponent,
                                          detail: child.path, sizeBytes: size, isDirectory: isDir))
                }
            } else {
                let size = directorySize(at: root)
                if size > 0 {
                    items.append(JunkItem(kind: .file(root), displayName: root.lastPathComponent,
                                          detail: root.path, sizeBytes: size, isDirectory: true))
                }
            }
        }
        return items
    }

    nonisolated private static func scanDevCaches(paths: [URL]) -> [JunkItem] {
        let fm = FileManager.default
        var items: [JunkItem] = []
        for path in paths {
            guard fm.fileExists(atPath: path.path) else { continue }
            let size = directorySize(at: path)
            guard size > 0 else { continue }
            // Display name = nombre del tool si lo podemos inferir, si no, lastPathComponent
            let display = devCacheDisplayName(for: path)
            items.append(JunkItem(kind: .file(path), displayName: display,
                                  detail: path.path, sizeBytes: size, isDirectory: true))
        }
        return items
    }

    nonisolated static func devCacheDisplayName(for url: URL) -> String {
        let p = url.path
        if p.contains(".npm") { return "npm cache" }
        if p.contains(".yarn") || p.contains("Yarn") { return "Yarn cache" }
        if p.contains("pnpm-store") { return "pnpm store" }
        if p.contains("/pip") { return "pip cache" }
        if p.contains("Homebrew/downloads") { return "Homebrew · downloads" }
        if p.contains("Homebrew/api") { return "Homebrew · api" }
        if p.contains("/cargo/registry/cache") { return "Cargo · registry cache" }
        if p.contains("/cargo/registry/src") { return "Cargo · registry sources" }
        if p.contains("/rustup") { return "rustup downloads" }
        if p.contains("/gradle") { return "Gradle caches" }
        if p.contains(".m2") { return "Maven · ~/.m2/repository" }
        if p.contains("/cocoapods") || p.contains("CocoaPods") { return "CocoaPods cache" }
        if p.contains("/.bundle") { return "RubyGems · .bundle/cache" }
        if p.contains("/composer") { return "Composer cache" }
        if p.contains("/go-build") { return "Go · build cache" }
        if p.contains("/go/pkg/mod") { return "Go · module cache" }
        if p.contains("electron-builder") { return "electron-builder cache" }
        if p.contains("electron") { return "Electron cache" }
        return url.lastPathComponent
    }

    nonisolated private static func scanOrphanedAppData(in directories: [URL], installed: Set<String>) -> [JunkItem] {
        let fm = FileManager.default
        var items: [JunkItem] = []
        var seenPaths = Set<String>()

        // Para chequeo rápido de prefijos: ordenamos por longitud descendente
        // para hits más específicos primero (no estrictamente necesario).
        let installedSorted = installed.sorted { $0.count > $1.count }

        for dir in directories {
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                if Task.isCancelled { return items }
                let name = child.lastPathComponent
                var bid = name
                for suffix in [".plist", ".savedState", ".binarycookies"] {
                    if bid.hasSuffix(suffix) { bid.removeLast(suffix.count) }
                }
                guard isLikelyBundleID(bid) else { continue }
                if isInstalledOrSubBundle(bid, installed: installed, sorted: installedSorted) { continue }
                // Skip Apple bundles (system, no se desinstalan)
                if bid.hasPrefix("com.apple.") { continue }

                if seenPaths.contains(child.path) { continue }
                seenPaths.insert(child.path)

                let size = directorySize(at: child)
                guard size > 0 else { continue }
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                items.append(JunkItem(kind: .file(child), displayName: bid,
                                      detail: child.path, sizeBytes: size, isDirectory: isDir))
            }
        }
        return items
    }

    /// `bid` es una app instalada — directo o como sub-bundle de una instalada
    /// (ej: `net.whatsapp.WhatsApp.ServiceExtension` cuando WhatsApp está
    /// instalado como `net.whatsapp.WhatsApp`).
    nonisolated static func isInstalledOrSubBundle(_ bid: String, installed: Set<String>, sorted: [String]) -> Bool {
        if installed.contains(bid) { return true }
        for inst in sorted {
            if bid.hasPrefix(inst + ".") { return true }
        }
        return false
    }

    nonisolated static func isLikelyBundleID(_ s: String) -> Bool {
        guard s.contains(".") else { return false }
        // Forma típica: com.empresa.producto / org.dominio.x
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        if s.unicodeScalars.contains(where: { !allowed.contains($0) }) { return false }
        // Al menos 2 segmentos no vacíos
        let parts = s.split(separator: ".")
        guard parts.count >= 2 else { return false }
        // Debe empezar con letra
        guard let first = s.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
        return true
    }

    /// Bundle IDs de todas las apps instaladas en cualquier ruta del disco,
    /// incluyendo extensions / appex / helpers internos. Combina:
    ///   1. `mdfind kMDItemContentType==com.apple.application-bundle` → todas las
    ///      apps registradas por LaunchServices, sin importar dónde estén.
    ///   2. Recorrido directo de /Applications, ~/Applications,
    ///      /System/Applications y /System/Library/CoreServices/Applications.
    ///   3. Para cada app encontrada, escanear `Contents/PlugIns/*.appex|app|bundle`
    ///      y `Contents/Library/LoginItems/*.app` para extraer sub-bundle IDs.
    nonisolated private static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        var seenAppPaths = Set<String>()
        let fm = FileManager.default

        // 1) mdfind — encuentra TODAS las apps registradas
        let mdfindPaths = mdfindApplications()
        for p in mdfindPaths {
            let url = URL(fileURLWithPath: p)
            guard !seenAppPaths.contains(url.path) else { continue }
            seenAppPaths.insert(url.path)
            collectBundleIDs(from: url, into: &ids)
        }

        // 2) Fallback / complemento — directorios estándar
        let home = fm.homeDirectoryForCurrentUser
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications")
        ]
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            let topLevel = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in topLevel {
                if url.pathExtension == "app" {
                    guard !seenAppPaths.contains(url.path) else { continue }
                    seenAppPaths.insert(url.path)
                    collectBundleIDs(from: url, into: &ids)
                } else {
                    // Subcarpeta tipo /Applications/Utilities/
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard isDir else { continue }
                    let nested = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    for inner in nested where inner.pathExtension == "app" {
                        guard !seenAppPaths.contains(inner.path) else { continue }
                        seenAppPaths.insert(inner.path)
                        collectBundleIDs(from: inner, into: &ids)
                    }
                }
            }
        }
        return ids
    }

    /// Lee el bundle ID de una `.app` y de todos sus sub-bundles (PlugIns,
    /// LoginItems, Helpers, XPCServices, Frameworks).
    nonisolated private static func collectBundleIDs(from appURL: URL, into ids: inout Set<String>) {
        if let bid = Bundle(url: appURL)?.bundleIdentifier { ids.insert(bid) }

        let subDirs = [
            "Contents/PlugIns",
            "Contents/Library/LoginItems",
            "Contents/Helpers",
            "Contents/XPCServices",
            "Contents/Frameworks"
        ]
        let bundleExtensions: Set<String> = ["app", "appex", "bundle", "framework", "xpc"]

        let fm = FileManager.default
        for subPath in subDirs {
            let dir = appURL.appendingPathComponent(subPath)
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for entry in entries where bundleExtensions.contains(entry.pathExtension.lowercased()) {
                if let bid = Bundle(url: entry)?.bundleIdentifier { ids.insert(bid) }
                // Algunas Frameworks contienen XPCServices anidados
                let nested = entry.appendingPathComponent("Contents/XPCServices")
                if fm.fileExists(atPath: nested.path),
                   let inner = try? fm.contentsOfDirectory(at: nested, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for x in inner where x.pathExtension.lowercased() == "xpc" {
                        if let bid = Bundle(url: x)?.bundleIdentifier { ids.insert(bid) }
                    }
                }
            }
        }
    }

    nonisolated private static func mdfindApplications() -> [String] {
        let res = ShellRunner.runSync("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"])
        guard res.exitCode == 0 else { return [] }
        return res.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasSuffix(".app") }
    }

    nonisolated private static func scanTimeMachineSnapshots() -> [JunkItem] {
        let result = ShellRunner.runSync("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        guard result.exitCode == 0 else { return [] }
        return parseSnapshotIdentifiers(from: result.stdout).map { datePart in
            JunkItem(
                kind: .localSnapshot(date: datePart),
                displayName: prettySnapshotDate(datePart),
                detail: "Snapshot en /  ·  identificador: \(datePart)",
                sizeBytes: 0,             // tamaño real no es accesible por API
                isDirectory: false
            )
        }
    }

    /// Extrae los identificadores de fecha de la salida de
    /// `tmutil listlocalsnapshots /`. Formato de cada línea relevante:
    /// `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local`
    nonisolated static func parseSnapshotIdentifiers(from stdout: String) -> [String] {
        var identifiers: [String] = []
        for line in stdout.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("com.apple.TimeMachine.") else { continue }
            let datePart = s
                .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                .replacingOccurrences(of: ".local", with: "")
            guard !datePart.isEmpty else { continue }
            identifiers.append(datePart)
        }
        return identifiers
    }

    /// "2026-05-08-123456" -> "8 may 2026 · 12:34:56"
    nonisolated static func prettySnapshotDate(_ raw: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone.current
        guard let date = f.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "es_ES")
        out.dateFormat = "d MMM yyyy '·' HH:mm:ss"
        return out.string(from: date)
    }

    nonisolated private static func scanIOSSimulators() -> [JunkItem] {
        let result = ShellRunner.runSync("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var items: [JunkItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let devicesRoot = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")

        for (runtime, devices) in devicesByRuntime {
            for dev in devices {
                let isAvailable = (dev["isAvailable"] as? Bool) ?? true
                let availabilityError = (dev["availabilityError"] as? String) ?? ""
                guard !isAvailable || !availabilityError.isEmpty else { continue }
                let udid = (dev["udid"] as? String) ?? ""
                let name = (dev["name"] as? String) ?? udid
                guard !udid.isEmpty else { continue }
                let dirURL = devicesRoot.appendingPathComponent(udid)
                let size = directorySize(at: dirURL)
                let runtimePretty = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                items.append(JunkItem(
                    kind: .simulator(udid: udid),
                    displayName: "\(name)  ·  \(runtimePretty)",
                    detail: availabilityError.isEmpty ? "Marcado como obsoleto por Xcode" : availabilityError,
                    sizeBytes: size,
                    isDirectory: true
                ))
            }
        }
        return items
    }

    // MARK: - Tamaño de directorio

    /// Tamaño real en disco. Sin .skipsHiddenFiles: el borrado elimina TODO el
    /// árbol, así que el tamaño mostrado debe contar también lo oculto.
    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if !isDir {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                     errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en {
            if Task.isCancelled { return total }
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true { continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Limpieza

    /// ¿La selección incluye items que se borran SIEMPRE de forma permanente
    /// aunque el modo Papelera esté activo? (snapshots TM, simuladores, y el
    /// contenido de la propia Papelera)
    var selectionIncludesAlwaysPermanent: Bool {
        let trashPrefix = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash").path + "/"
        for item in results.flatMap(\.items) where selection.contains(item.id) {
            switch item.kind {
            case .localSnapshot, .simulator: return true
            case .file(let url): if url.path.hasPrefix(trashPrefix) { return true }
            }
        }
        return false
    }

    /// Elimina todos los items seleccionados.
    /// - `moveToTrash`: los items file-based van a la Papelera del sistema
    ///   (recuperables). Excepciones siempre permanentes: snapshots TM,
    ///   simuladores, y lo que ya está en ~/.Trash (vaciar la Papelera es
    ///   permanente por naturaleza). En este modo NO hay escalado a root —
    ///   root no puede "mover a la Papelera" del usuario.
    /// - Si hay items que requieren admin (snapshots TM), `adminSession` debe
    ///   estar activo o se omitirán.
    @discardableResult
    func cleanSelected(adminSession: AdminSessionService? = nil, moveToTrash: Bool = false) async -> Int64 {
        let selectedItems = results.flatMap(\.items).filter { selection.contains($0.id) }
        guard !selectedItems.isEmpty else { return 0 }

        var fileURLs: [URL] = []
        var snapshotDates: [String] = []
        var simUDIDs: [String] = []
        var bytesByID: [UUID: Int64] = [:]

        for item in selectedItems {
            bytesByID[item.id] = item.sizeBytes
            switch item.kind {
            case .file(let url):
                fileURLs.append(url)
            case .localSnapshot(let date):
                snapshotDates.append(date)
            case .simulator(let udid):
                simUDIDs.append(udid)
            }
        }

        var freed: Int64 = 0
        var removedIds: Set<UUID> = []
        var failures: [String] = []
        let fm = FileManager.default

        // 1) Files — primer pase normal
        let trashPrefix = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path + "/"
        var stillExisting: [(item: JunkItem, url: URL)] = []
        for item in selectedItems {
            guard case .file(let url) = item.kind else { continue }
            // Lo que ya está en ~/.Trash se borra de verdad incluso en modo
            // Papelera: moverlo "a la Papelera" sería un no-op.
            if moveToTrash && !url.path.hasPrefix(trashPrefix) {
                try? fm.trashItem(at: url, resultingItemURL: nil)
            } else {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) {
                freed += item.sizeBytes
                removedIds.insert(item.id)
            } else {
                stillExisting.append((item, url))
            }
        }

        // 1b) Si quedaron paths sin borrar (típicamente Containers protegidos por
        // TCC), reintentar con admin si está activo. Sólo en modo permanente:
        // root no puede mover archivos a la Papelera del usuario.
        if !stillExisting.isEmpty, !moveToTrash, let admin = adminSession, admin.isActive {
            let paths = stillExisting.map { $0.url.path }
            _ = await admin.removeAsRoot(paths: paths)
            let hasFDA = AdminSessionService.hasFullDiskAccess()
            for (item, url) in stillExisting {
                if !fm.fileExists(atPath: url.path) {
                    freed += item.sizeBytes
                    removedIds.insert(item.id)
                } else {
                    let hint = hasFDA
                        ? "el archivo tiene flags de inmutabilidad o ACLs"
                        : "macOS bloquea el acceso por TCC — otorga «Acceso completo al disco» a CleanMyOwn"
                    failures.append("\(item.displayName): no se pudo eliminar — \(hint)")
                }
            }
        } else if !stillExisting.isEmpty {
            for (item, _) in stillExisting {
                let hint: String
                if moveToTrash {
                    hint = "no se pudo mover a la Papelera — desactiva el modo Papelera para borrado permanente (con admin si hace falta)"
                } else if AdminSessionService.hasFullDiskAccess() {
                    hint = "protegido — activa el modo administrador y reintenta"
                } else {
                    hint = "protegido — activa el modo administrador y otorga FDA"
                }
                failures.append("\(item.displayName): \(hint)")
            }
        }

        // 2) Time Machine snapshots (admin)
        if !snapshotDates.isEmpty {
            if let admin = adminSession, admin.isActive {
                for item in selectedItems {
                    guard case .localSnapshot(let date) = item.kind else { continue }
                    let res = await admin.runPrivileged("/usr/bin/tmutil", ["deletelocalsnapshots", date])
                    if res.success {
                        freed += item.sizeBytes
                        removedIds.insert(item.id)
                    } else {
                        failures.append("Snapshot \(item.displayName): \(res.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            } else {
                for item in selectedItems {
                    if case .localSnapshot = item.kind {
                        failures.append("Snapshot \(item.displayName): requiere modo administrador.")
                    }
                }
            }
        }

        // 3) Simuladores iOS
        if !simUDIDs.isEmpty {
            for item in selectedItems {
                guard case .simulator(let udid) = item.kind else { continue }
                let res = ShellRunner.runSync("/usr/bin/xcrun", ["simctl", "delete", udid])
                if res.exitCode == 0 {
                    freed += item.sizeBytes
                    removedIds.insert(item.id)
                } else {
                    failures.append("Sim \(item.displayName): \(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }

        // Actualizar resultados
        results = results.map { res in
            var copy = res
            copy.items.removeAll { removedIds.contains($0.id) }
            return copy
        }
        selection.subtract(removedIds)
        lastCleanedBytes = freed
        lastError = failures.isEmpty ? nil : failures.prefix(8).joined(separator: "\n")
        return freed
    }

    // MARK: - Selección

    func toggle(_ item: JunkItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setSelection(category: JunkCategoryResult, selected: Bool) {
        let ids = category.items.map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func isFullySelected(_ category: JunkCategoryResult) -> Bool {
        !category.items.isEmpty && category.items.allSatisfy { selection.contains($0.id) }
    }

    func isPartiallySelected(_ category: JunkCategoryResult) -> Bool {
        let any = category.items.contains { selection.contains($0.id) }
        return any && !isFullySelected(category)
    }
}
