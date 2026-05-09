//
//  PermissionsMonitor.swift
//  CleanMyOwn
//
//  Estado en vivo de los permisos del sistema. Una sola instancia compartida
//  observa cambios y notifica a las vistas:
//
//  - `hasFullDiskAccess` se re-checa cada vez que la app vuelve al foreground
//    (`NSApplication.didBecomeActiveNotification`) y opcionalmente vía
//    polling de 2s mientras alguna vista esté esperando el cambio.
//

import AppKit
import Combine
import Foundation

@MainActor
final class PermissionsMonitor: ObservableObject {
    static let shared = PermissionsMonitor()

    @Published private(set) var hasFullDiskAccess: Bool

    private var pollingTask: Task<Void, Never>?
    private var pollingClients: Int = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        self.hasFullDiskAccess = AdminSessionService.hasFullDiskAccess()
        startObservingForeground()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        pollingTask?.cancel()
    }

    /// Forzar una verificación inmediata.
    func refresh() {
        let now = AdminSessionService.hasFullDiskAccess()
        if now != hasFullDiskAccess {
            hasFullDiskAccess = now
        }
    }

    /// Una vista que muestra UI dependiente de FDA pide polling al aparecer
    /// y lo libera al desaparecer. Se cuenta uso para que múltiples vistas
    /// compartan el mismo timer.
    func beginActivePolling() {
        pollingClients += 1
        if pollingTask == nil {
            pollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { break }
                    self?.refresh()
                }
            }
        }
    }

    func endActivePolling() {
        pollingClients = max(0, pollingClients - 1)
        if pollingClients == 0 {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    private func startObservingForeground() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }
}
