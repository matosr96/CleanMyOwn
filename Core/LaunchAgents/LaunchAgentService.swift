//
//  LaunchAgentService.swift
//  CleanMyOwn
//
//  Enumera Launch Agents y Daemons en las rutas estándar y permite
//  habilitar/deshabilitar los del usuario.
//
//  Estrategia segura para deshabilitar: renombrar el plist a `.plist.disabled`
//  (reversible) y descargar el job con `launchctl bootout` si está cargado.
//

import CleanMyOwnShared
import Foundation
import SwiftUI

enum LaunchAgentScope: String {
    case userAgent = "User"
    case systemAgent = "System (Agents)"
    case systemDaemon = "System (Daemons)"

    var requiresAdmin: Bool { self != .userAgent }
}

struct LaunchAgent: Identifiable, Hashable {
    let id: String           // path al plist
    let label: String
    let plistURL: URL
    let scope: LaunchAgentScope
    let program: String?     // Program o ProgramArguments[0]
    let runAtLoad: Bool
    let keepAlive: Bool
    let isDisabledByFile: Bool   // tiene sufijo .disabled
    var isLoaded: Bool

    var displayName: String {
        // Si el label tiene un dominio invertido, último componente
        if label.contains(".") {
            return label.components(separatedBy: ".").last ?? label
        }
        return label
    }
}

@MainActor
final class LaunchAgentService: ObservableObject {
    @Published private(set) var agents: [LaunchAgent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    func reload() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                Self.scanAll()
            }.value
            self.agents = loaded.sorted { lhs, rhs in
                if lhs.scope.rawValue != rhs.scope.rawValue { return lhs.scope.rawValue < rhs.scope.rawValue }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            self.isLoading = false
        }
    }

    /// Habilita o deshabilita un agent del usuario.
    /// Para system agents/daemons devuelve un error porque requiere admin.
    func setEnabled(_ enabled: Bool, agent: LaunchAgent) async -> String? {
        guard agent.scope == .userAgent else {
            return "Modificar items del sistema requiere privilegios de administrador."
        }
        if enabled {
            return await enable(agent: agent)
        } else {
            return await disable(agent: agent)
        }
    }

    private func disable(agent: LaunchAgent) async -> String? {
        let fm = FileManager.default
        let disabledPath = agent.plistURL.path + ".disabled"
        do {
            // Descargar primero (best-effort)
            _ = await ShellRunner.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agent.label)"])
            // Renombrar
            try fm.moveItem(atPath: agent.plistURL.path, toPath: disabledPath)
            await rescan()
            return nil
        } catch {
            return "No se pudo deshabilitar: \(error.localizedDescription)"
        }
    }

    private func enable(agent: LaunchAgent) async -> String? {
        let fm = FileManager.default
        // Si está deshabilitado por archivo .disabled, restaurar nombre
        let originalPath = agent.plistURL.path.hasSuffix(".disabled")
            ? String(agent.plistURL.path.dropLast(".disabled".count))
            : agent.plistURL.path
        do {
            if originalPath != agent.plistURL.path {
                try fm.moveItem(atPath: agent.plistURL.path, toPath: originalPath)
            }
            // Cargar
            let result = await ShellRunner.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", originalPath])
            if result.exitCode != 0 {
                // No es fatal: el job puede ya estar cargado
            }
            await rescan()
            return nil
        } catch {
            return "No se pudo habilitar: \(error.localizedDescription)"
        }
    }

    /// Re-escanea todo y reemplaza la lista (los renames invalidan ids/paths).
    private func rescan() async {
        let updated = await Task.detached(priority: .userInitiated) {
            Self.scanAll()
        }.value
        self.agents = updated.sorted { lhs, rhs in
            if lhs.scope.rawValue != rhs.scope.rawValue { return lhs.scope.rawValue < rhs.scope.rawValue }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    // MARK: - Estáticos

    nonisolated private static func scanAll() -> [LaunchAgent] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs: [(URL, LaunchAgentScope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon)
        ]
        let loadedLabels = currentlyLoadedLabels()
        var found: [LaunchAgent] = []
        for (dir, scope) in dirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries {
                let path = url.path
                let isDisabled = path.hasSuffix(".plist.disabled")
                guard path.hasSuffix(".plist") || isDisabled else { continue }
                if let agent = parsePlist(at: url, scope: scope, loadedLabels: loadedLabels, isDisabled: isDisabled) {
                    found.append(agent)
                }
            }
        }
        return found
    }

    nonisolated static func parsePlist(at url: URL, scope: LaunchAgentScope, loadedLabels: Set<String>, isDisabled: Bool) -> LaunchAgent? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
        let keepAlive: Bool = {
            if let b = plist["KeepAlive"] as? Bool { return b }
            if plist["KeepAlive"] is [String: Any] { return true }
            return false
        }()
        let program: String? = {
            if let p = plist["Program"] as? String { return p }
            if let args = plist["ProgramArguments"] as? [String], let first = args.first { return first }
            return nil
        }()
        return LaunchAgent(
            id: url.path,
            label: label,
            plistURL: url,
            scope: scope,
            program: program,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            isDisabledByFile: isDisabled,
            isLoaded: loadedLabels.contains(label)
        )
    }

    nonisolated private static func currentlyLoadedLabels() -> Set<String> {
        let result = ShellRunner.runSync("/bin/launchctl", ["list"])
        guard result.exitCode == 0 else { return [] }
        return parseLoadedLabels(from: result.stdout)
    }

    /// `launchctl list` produce líneas: PID\tStatus\tLabel
    nonisolated static func parseLoadedLabels(from stdout: String) -> Set<String> {
        var set = Set<String>()
        for line in stdout.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            set.insert(String(cols[2]))
        }
        return set
    }

}
