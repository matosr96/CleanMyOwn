//
//  AppCatalogService.swift
//  CleanMyOwn
//
//  Lista las apps instaladas en /Applications y ~/Applications, lee su Info.plist,
//  y detecta archivos asociados (Application Support, Caches, Preferences,
//  Containers, Saved State, etc.) por bundle identifier.
//
//  La desinstalación mueve la .app y todos sus archivos asociados a la Papelera.
//

import AppKit
import Foundation
import SwiftUI

struct AppEntry: Identifiable {
    let id: String                 // bundleID si existe, si no path
    let name: String
    let bundleID: String?
    let version: String?
    let location: URL              // ruta al .app
    let sizeBytes: Int64
    let icon: NSImage?
    let requiresAdmin: Bool        // owner = root o no es escribible por el usuario
    var associatedItems: [AssociatedItem] = []

    var isSystemApp: Bool {
        location.path.hasPrefix("/System/") || location.path == "/Applications/Safari.app"
    }
    var totalRemovableBytes: Int64 {
        sizeBytes + associatedItems.reduce(0) { $0 + $1.sizeBytes }
    }
}

struct AssociatedItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let category: String      // "Caches", "Preferences", etc.
    let sizeBytes: Int64

    static func == (lhs: AssociatedItem, rhs: AssociatedItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class AppCatalogService: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUninstalledBytes: Int64 = 0

    func reload() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                Self.scanInstalledApps()
            }.value
            self.apps = loaded
            self.isLoading = false
        }
    }

    /// Busca archivos asociados a una app por bundle ID y nombre.
    func findAssociatedFiles(for app: AppEntry) async -> [AssociatedItem] {
        await Task.detached(priority: .userInitiated) {
            Self.scanAssociatedFiles(for: app)
        }.value
    }

    /// Resultado de un intento de desinstalación.
    struct UninstallResult {
        var freedBytes: Int64
        var appRemoved: Bool                      // ¿la .app se borró efectivamente del disco?
        var failedURLs: [URL]                     // urls que no pudieron borrarse
        var errors: [String]                      // mensajes humanos
        var needsAdmin: Bool                      // detectado que falló por permisos y NO había sesión admin
        var processesKilled: Int                  // cuántos procesos vivos se cerraron antes de borrar
    }

    /// Encuentra todos los procesos vivos que pertenecen a una app:
    ///   - Bundle ID exacto, o sub-bundles cuyo ID empieza con `<bid>.`
    ///   - Procesos cuyo executable vive dentro del `.app`
    /// Devuelve el set deduplicado por PID.
    private static func runningInstances(of app: AppEntry) -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        var matches: [NSRunningApplication] = []

        let appPath = app.location.path + "/"
        for proc in running {
            // Match por path del executable (más fiable: agarra helpers/agents cuyo bundle ID
            // pueda no coincidir directamente).
            if let url = proc.executableURL, url.path.hasPrefix(appPath) {
                matches.append(proc); continue
            }
            // Match por bundle ID exacto y sub-bundles
            if let bid = app.bundleID, let pbid = proc.bundleIdentifier {
                if pbid == bid || pbid.hasPrefix(bid + ".") {
                    matches.append(proc)
                }
            }
        }
        // Deduplicar por PID
        var seen = Set<pid_t>()
        return matches.filter { seen.insert($0.processIdentifier).inserted }
    }

    /// Cierra todos los procesos vivos de la app: primero `terminate()` (SIGTERM
    /// — la app puede limpiar), espera hasta 2s, y si sobreviven `forceTerminate()` (SIGKILL).
    /// Devuelve la cantidad total de procesos que estaban corriendo.
    @discardableResult
    private func quitRunningInstances(of app: AppEntry) async -> Int {
        let procs = Self.runningInstances(of: app)
        guard !procs.isEmpty else { return 0 }

        for p in procs { p.terminate() }

        // Esperar hasta 2s a que cierren limpiamente
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if procs.allSatisfy(\.isTerminated) { return procs.count }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        // Force kill los rebeldes
        for p in procs where !p.isTerminated { p.forceTerminate() }
        // Pequeña espera adicional para que el WindowServer borre íconos del Dock
        try? await Task.sleep(nanoseconds: 400_000_000)
        return procs.count
    }

    /// Desinstala usando, opcionalmente, una `AdminSessionService` ya activa.
    /// Estrategia:
    ///   1. Si la app está marcada `requiresAdmin` Y `adminSession?.isActive == true`,
    ///      hacemos UN solo `rm -rf` privilegiado con todos los paths.
    ///   2. Si no requiere admin, `FileManager.removeItem` directo.
    ///   3. Si requiere admin pero la sesión NO está activa, devolvemos `needsAdmin = true`
    ///      para que la UI active la sesión y reintente sin pedir password de nuevo.
    /// En todos los casos, verificamos con `fileExists` antes de removerlo de la lista.
    func uninstall(
        _ app: AppEntry,
        includingAssociated items: [AssociatedItem],
        adminSession: AdminSessionService? = nil
    ) async -> UninstallResult {
        let fm = FileManager.default
        let allURLs: [URL] = items.map(\.url) + [app.location]
        let bytesByURL: [URL: Int64] = Dictionary(uniqueKeysWithValues:
            items.map { ($0.url, $0.sizeBytes) } + [(app.location, app.sizeBytes)]
        )

        // 0) Cerrar instancias vivas (app + helpers + agents) antes de borrar.
        // Si no hacemos esto, el ícono del Dock queda zombie, hay locks abiertos
        // y procesos huérfanos sobreviven al borrado.
        let killed = await quitRunningInstances(of: app)

        // ¿Necesitamos privilegios? La app lo dice, o cualquier item asociado vive
        // en un padre no escribible.
        let needsPriv = app.requiresAdmin || items.contains {
            !fm.isWritableFile(atPath: $0.url.deletingLastPathComponent().path)
        }

        if needsPriv {
            guard let adminSession, adminSession.isActive else {
                return UninstallResult(freedBytes: 0, appRemoved: false,
                                       failedURLs: allURLs, errors: [],
                                       needsAdmin: true, processesKilled: killed)
            }
            let result = await adminSession.removeAsRoot(paths: allURLs.map(\.path))
            return finalize(app: app, urls: allURLs, bytesByURL: bytesByURL,
                            cmdStderr: result.success ? "" : result.output,
                            processesKilled: killed)
        }

        // Camino sin privilegios.
        for url in allURLs {
            try? fm.removeItem(at: url)
        }
        return finalize(app: app, urls: allURLs, bytesByURL: bytesByURL,
                        cmdStderr: "", processesKilled: killed)
    }

    /// Verifica con `fileExists` qué desapareció realmente y construye el resultado.
    private func finalize(app: AppEntry, urls: [URL], bytesByURL: [URL: Int64],
                          cmdStderr: String, processesKilled: Int) -> UninstallResult {
        let fm = FileManager.default
        var freed: Int64 = 0
        var failed: [URL] = []
        var errors: [String] = []

        for url in urls {
            if fm.fileExists(atPath: url.path) {
                failed.append(url)
                errors.append("\(url.lastPathComponent): permaneció en disco")
            } else {
                freed += bytesByURL[url] ?? 0
            }
        }
        if !cmdStderr.isEmpty && !failed.isEmpty {
            errors.insert(cmdStderr.trimmingCharacters(in: .whitespacesAndNewlines), at: 0)
        }

        let appRemoved = !fm.fileExists(atPath: app.location.path)
        if appRemoved { apps.removeAll { $0.id == app.id } }
        lastUninstalledBytes = freed
        lastError = errors.isEmpty ? nil : errors.prefix(5).joined(separator: "\n")

        return UninstallResult(
            freedBytes: freed,
            appRemoved: appRemoved,
            failedURLs: failed,
            errors: errors,
            needsAdmin: false,
            processesKilled: processesKilled
        )
    }

    // MARK: - Scan estático

    nonisolated private static func scanInstalledApps() -> [AppEntry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]

        var found: [AppEntry] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let children = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children where url.pathExtension == "app" {
                guard let entry = appEntry(at: url) else { continue }
                found.append(entry)
            }
            // Algunas apps están en subcarpetas (ej: /Applications/Utilities/Console.app)
            for url in children {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir, url.pathExtension != "app" else { continue }
                if let nested = try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) {
                    for inner in nested where inner.pathExtension == "app" {
                        if let entry = appEntry(at: inner) { found.append(entry) }
                    }
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func appEntry(at url: URL) -> AppEntry? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let bundle = Bundle(url: url)
        let infoPlist = bundle?.infoDictionary
        let displayName = (infoPlist?["CFBundleDisplayName"] as? String)
            ?? (infoPlist?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle?.bundleIdentifier
        let version = (infoPlist?["CFBundleShortVersionString"] as? String)
            ?? (infoPlist?["CFBundleVersion"] as? String)

        let size = directorySize(at: url)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 36, height: 36)

        // Detectar si requiere admin: owner=root o no escribible por el usuario.
        let needsAdmin = requiresAdminToDelete(url: url)

        return AppEntry(
            id: bundleID ?? url.path,
            name: displayName,
            bundleID: bundleID,
            version: version,
            location: url,
            sizeBytes: size,
            icon: icon,
            requiresAdmin: needsAdmin
        )
    }

    nonisolated private static func scanAssociatedFiles(for app: AppEntry) -> [AssociatedItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [AssociatedItem] = []

        // Construir lista de candidatos por categoría: (categoría, ruta)
        let bid = app.bundleID
        let nameVariants = [app.name, app.name.replacingOccurrences(of: " ", with: "")].filter { !$0.isEmpty }

        struct Candidate { let category: String; let path: String }
        var candidates: [Candidate] = []

        let categoriesByDir: [(String, String)] = [
            ("Application Support", "Library/Application Support"),
            ("Caches", "Library/Caches"),
            ("Logs", "Library/Logs"),
            ("Saved Application State", "Library/Saved Application State"),
            ("HTTP Storage", "Library/HTTPStorages"),
            ("WebKit Data", "Library/WebKit"),
            ("Containers", "Library/Containers"),
            ("Group Containers", "Library/Group Containers"),
            ("Cookies", "Library/Cookies")
        ]

        for (category, dir) in categoriesByDir {
            if let bid {
                candidates.append(Candidate(category: category, path: home.appendingPathComponent("\(dir)/\(bid)").path))
                // Saved State usa sufijo .savedState
                if category == "Saved Application State" {
                    candidates.append(Candidate(category: category, path: home.appendingPathComponent("\(dir)/\(bid).savedState").path))
                }
                if category == "Cookies" {
                    candidates.append(Candidate(category: category, path: home.appendingPathComponent("\(dir)/\(bid).binarycookies").path))
                }
            }
            for nameVar in nameVariants {
                candidates.append(Candidate(category: category, path: home.appendingPathComponent("\(dir)/\(nameVar)").path))
            }
        }

        // Preferences (.plist) — por bundle id
        if let bid {
            candidates.append(Candidate(category: "Preferences", path: home.appendingPathComponent("Library/Preferences/\(bid).plist").path))
        }

        // Launch Agents
        if let bid {
            candidates.append(Candidate(category: "Launch Agent", path: home.appendingPathComponent("Library/LaunchAgents/\(bid).plist").path))
        }

        // Crash Reports
        if let bid {
            candidates.append(Candidate(category: "Crash Reports", path: home.appendingPathComponent("Library/Logs/DiagnosticReports/\(bid)").path))
        }

        // Filtrar duplicados por path y los que no existen
        var seen = Set<String>()
        for c in candidates where !seen.contains(c.path) {
            seen.insert(c.path)
            let url = URL(fileURLWithPath: c.path)
            guard fm.fileExists(atPath: c.path) else { continue }
            let size = directorySize(at: url)
            guard size > 0 || !((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) else { continue }
            found.append(AssociatedItem(url: url, category: c.category, sizeBytes: size))
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Detecta si el .app requiere privilegios de admin para borrarse.
    /// Heurística: dueño es root, o el directorio padre no es escribible por el usuario.
    nonisolated private static func requiresAdminToDelete(url: URL) -> Bool {
        let fm = FileManager.default
        // Si el .app es un symlink, asumimos que sí (suele apuntar a /opt/, /usr/local, etc.)
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            if let type = attrs[.type] as? FileAttributeType, type == .typeSymbolicLink {
                return true
            }
            if let owner = attrs[.ownerAccountName] as? String, owner == "root" {
                return true
            }
            if let ownerID = attrs[.ownerAccountID] as? NSNumber, ownerID.intValue == 0 {
                return true
            }
        }
        // El borrado real pasa por el padre: hay que poder escribir en /Applications.
        let parent = url.deletingLastPathComponent().path
        return !fm.isWritableFile(atPath: parent)
    }

    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

        if !isDir {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }

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
}
