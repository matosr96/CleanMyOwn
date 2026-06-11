//
//  MaintenanceView.swift
//  CleanMyOwn
//
//  Tareas de mantenimiento de un clic: cada card explica QUÉ arregla en
//  lenguaje llano, avisa de efectos visibles y muestra el resultado en sitio.
//

import SwiftUI

struct MaintenanceView: View {
    @StateObject private var service = MaintenanceService()
    @EnvironmentObject private var admin: AdminSessionService
    @EnvironmentObject private var history: CleaningHistoryService

    private let mint = Color(red: 0.35, green: 0.88, blue: 0.72)

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header.cascadeIn(0)
                    HelperStatusControls().cascadeIn(1)
                    tasksList.cascadeIn(2)
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            HeaderIconChip(icon: "wrench.and.screwdriver.fill", tint: mint)
            VStack(alignment: .leading, spacing: 8) {
                Text("MANTENIMIENTO").font(.label).foregroundStyle(Theme.textTertiary)
                Text("Puesta a punto").font(.displayMedium).foregroundStyle(Theme.textPrimary)
                Text("Arreglos de un clic para los achaques clásicos de macOS.")
                    .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var tasksList: some View {
        VStack(spacing: 10) {
            ForEach(MaintenanceService.tasks) { task in
                taskCard(task)
            }
        }
    }

    private func taskCard(_ task: MaintenanceService.MaintenanceTask) -> some View {
        let state = service.state(of: task.id)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(mint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: task.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.name).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                    if task.requiresAdmin && !admin.canEscalate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.warning)
                            .help("Pedirá tu contraseña (o usa el asistente si está activo)")
                    }
                }
                Text(task.blurb).font(.bodySmall).foregroundStyle(Theme.textSecondary)
                if let caveat = task.caveat {
                    Text(caveat).font(.bodySmall).foregroundStyle(Theme.textTertiary)
                }
                if case .failure(let message) = state {
                    Text(message)
                        .font(.bodySmall).foregroundStyle(Theme.danger)
                        .lineLimit(2)
                }
            }

            Spacer()

            taskAction(task, state: state)
        }
        .padding(16)
        .glassCard(cornerRadius: Theme.cornerMedium)
    }

    @ViewBuilder
    private func taskAction(_ task: MaintenanceService.MaintenanceTask,
                            state: MaintenanceService.TaskState) -> some View {
        switch state {
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Ejecutando…").font(.bodySmall).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        case .success:
            Label("Listo", systemImage: "checkmark.circle.fill")
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.success)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .transition(.scale.combined(with: .opacity))
        default:
            Button(action: { Task { await run(task) } }) {
                Text("Ejecutar").font(.bodyMedium.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(mint.opacity(0.16)))
                    .foregroundStyle(mint)
            }
            .buttonStyle(.plain)
            .disabled(service.anyRunning)
            .accessibilityLabel("Ejecutar \(task.name)")
        }
    }

    private func run(_ task: MaintenanceService.MaintenanceTask) async {
        let ok = await service.run(task.id, admin: admin)
        if ok {
            history.record(kind: .maintenance, freedBytes: 0, itemCount: 1,
                           mode: .none, summary: task.name)
        }
    }
}

#Preview {
    MaintenanceView()
        .environmentObject(AdminSessionService())
        .environmentObject(CleaningHistoryService())
        .frame(width: 1000, height: 700)
        .background(Theme.background)
}
