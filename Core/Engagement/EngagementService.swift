//
//  EngagementService.swift
//  CleanMyOwn
//
//  Avisos inteligentes OPT-IN. Gracias al companion de menubar la app vive
//  residente, así que puede vigilar un par de señales útiles y avisar con
//  notificaciones locales — pocas, honestas y con cooldown. Nada de spam.
//
//  Reglas:
//   • Papelera > 10 GB            → cada 3 días como mucho.
//   • > 14 días sin escanear      → cada 7 días como mucho.
//

import Foundation
import UserNotifications

@MainActor
final class EngagementService: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled {
                requestAuthorizationAndStart()
            } else {
                loop?.cancel()
                loop = nil
            }
        }
    }

    private enum Keys {
        static let enabled = "smartAlerts"
        static let lastScan = "lastScanDate"
        static let trashNotified = "alert.trash.lastDate"
        static let staleNotified = "alert.stale.lastDate"
    }

    private enum Limits {
        static let trashThreshold: Int64 = 10 * 1024 * 1024 * 1024   // 10 GB
        static let trashCooldown: TimeInterval = 3 * 86_400
        static let staleScanAfter: TimeInterval = 14 * 86_400
        static let staleCooldown: TimeInterval = 7 * 86_400
        static let checkEvery: TimeInterval = 6 * 3_600              // 6 h
    }

    private var loop: Task<Void, Never>?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        if enabled {
            startLoop()
        }
    }

    /// Lo llama JunkScanService al iniciar un escaneo.
    static func markScanDate() {
        UserDefaults.standard.set(Date(), forKey: Keys.lastScan)
    }

    private func requestAuthorizationAndStart() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                if granted {
                    self?.startLoop()
                } else {
                    self?.enabled = false
                }
            }
        }
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            // Primer chequeo a los 60 s del arranque, luego cada 6 h.
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            while !Task.isCancelled {
                await self?.runChecks()
                try? await Task.sleep(nanoseconds: UInt64(Limits.checkEvery * 1_000_000_000))
            }
        }
    }

    private func runChecks() async {
        guard enabled else { return }

        // 1) Papelera grande
        let trashBytes = await Task.detached(priority: .utility) {
            Self.directorySize(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        }.value
        if trashBytes > Limits.trashThreshold,
           cooledDown(Keys.trashNotified, every: Limits.trashCooldown) {
            notify(
                title: "Tu Papelera ocupa \(trashBytes.formattedAsBytes)",
                body: "Vaciarla desde Limpieza recupera ese espacio de verdad."
            )
            UserDefaults.standard.set(Date(), forKey: Keys.trashNotified)
        }

        // 2) Mucho tiempo sin escanear (sólo si alguna vez escaneó)
        if let last = UserDefaults.standard.object(forKey: Keys.lastScan) as? Date {
            let days = Int(Date().timeIntervalSince(last) / 86_400)
            if Date().timeIntervalSince(last) > Limits.staleScanAfter,
               cooledDown(Keys.staleNotified, every: Limits.staleCooldown) {
                notify(
                    title: "Hace \(days) días del último escaneo",
                    body: "Un Smart Scan rápido te dice cuánta basura se acumuló."
                )
                UserDefaults.standard.set(Date(), forKey: Keys.staleNotified)
            }
        }
    }

    private func cooledDown(_ key: String, every interval: TimeInterval) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return true }
        return Date().timeIntervalSince(last) > interval
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Tamaño rápido de un directorio (para el chequeo de la Papelera).
    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
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
