//
//  MaintenanceService.swift
//  CleanMyOwn
//
//  Tareas de mantenimiento del sistema. Las que requieren root van por la
//  infraestructura privilegiada existente (asistente → AEWP); las de usuario
//  corren directas con ShellRunner. Cada tarea es un verbo concreto — nunca
//  "ejecuta este comando".
//

import CleanMyOwnShared
import Foundation

@MainActor
final class MaintenanceService: ObservableObject {
    enum TaskID: String, CaseIterable, Identifiable {
        case flushDNS
        case reindexSpotlight
        case rebuildLaunchServices
        case restartFinderDock

        var id: String { rawValue }
    }

    enum TaskState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    struct MaintenanceTask: Identifiable {
        let id: TaskID
        let name: String
        let blurb: String
        let icon: String
        /// Necesita privilegios (asistente o contraseña).
        let requiresAdmin: Bool
        /// Aviso de duración/efecto visible, si lo hay.
        let caveat: String?
    }

    static let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            id: .flushDNS,
            name: "Vaciar caché de DNS",
            blurb: "Resuelve webs que no cargan o cargan versiones viejas tras cambiar de red.",
            icon: "network",
            requiresAdmin: true,
            caveat: nil
        ),
        MaintenanceTask(
            id: .reindexSpotlight,
            name: "Reindexar Spotlight",
            blurb: "Reconstruye el índice de búsqueda cuando Spotlight no encuentra lo que existe.",
            icon: "magnifyingglass.circle.fill",
            requiresAdmin: true,
            caveat: "El Mac indexará en segundo plano un rato; la búsqueda estará incompleta mientras tanto."
        ),
        MaintenanceTask(
            id: .rebuildLaunchServices,
            name: "Reconstruir registro de apps",
            blurb: "Arregla apps duplicadas en «Abrir con…» y asociaciones de archivos rotas.",
            icon: "square.stack.3d.up.fill",
            requiresAdmin: false,
            caveat: "Puede tardar un minuto. El primer «Abrir con…» después será más lento."
        ),
        MaintenanceTask(
            id: .restartFinderDock,
            name: "Reiniciar Finder y Dock",
            blurb: "Cura iconos fantasma, ventanas congeladas y el Dock que no responde.",
            icon: "arrow.triangle.2.circlepath",
            requiresAdmin: false,
            caveat: "El escritorio y el Dock parpadearán un instante."
        )
    ]

    @Published private(set) var states: [TaskID: TaskState] = [:]

    func state(of id: TaskID) -> TaskState { states[id] ?? .idle }

    var anyRunning: Bool { states.values.contains(.running) }

    /// Ejecuta la tarea; devuelve true si terminó bien.
    @discardableResult
    func run(_ id: TaskID, admin: AdminSessionService) async -> Bool {
        guard state(of: id) != .running else { return false }
        states[id] = .running

        let result: ShellResult
        switch id {
        case .flushDNS:
            let r = await admin.flushDNSCache()
            result = ShellResult(exitCode: r.exitCode, stdout: "", stderr: r.output)
        case .reindexSpotlight:
            let r = await admin.reindexSpotlight()
            result = ShellResult(exitCode: r.exitCode, stdout: "", stderr: r.output)
        case .rebuildLaunchServices:
            result = await ShellRunner.run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"]
            )
        case .restartFinderDock:
            let finder = await ShellRunner.run("/usr/bin/killall", ["Finder"])
            let dock = await ShellRunner.run("/usr/bin/killall", ["Dock"])
            // killall devuelve 1 si el proceso no estaba corriendo — no es fallo.
            let worst = max(finder.exitCode, dock.exitCode)
            result = ShellResult(exitCode: worst <= 1 ? 0 : worst,
                                 stdout: "",
                                 stderr: [finder.stderr, dock.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
        }

        let ok = result.exitCode == 0
        states[id] = ok ? .success
            : .failure(result.stderr.isEmpty ? "Terminó con código \(result.exitCode)" : result.stderr)

        // El check vuelve a "Ejecutar" pasados unos segundos.
        if ok {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if self?.state(of: id) == .success {
                    self?.states[id] = .idle
                }
            }
        }
        return ok
    }
}
