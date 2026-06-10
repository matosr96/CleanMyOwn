//
//  OnboardingView.swift
//  CleanMyOwn
//
//  Wizard de bienvenida: configura los DOS permisos una sola vez para que
//  la app funcione para siempre sin fricción (estilo CleanMyMac):
//
//   1. Full Disk Access — detecta en vivo cuando se concede (PermissionsMonitor).
//   2. Asistente privilegiado (SMAppService) — root sin contraseñas, persistente
//      entre sesiones. También se detecta en vivo al aprobarlo en Ajustes.
//
//  Ambos pasos se pueden saltar; la app funciona igual con la sesión admin
//  por contraseña (una vez por sesión) como fallback.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var monitor: PermissionsMonitor
    @EnvironmentObject private var admin: AdminSessionService
    /// Se cierra la sheet
    let onFinish: () -> Void

    @State private var step: Int = 0
    @State private var helperPollTask: Task<Void, Never>?

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Header con progreso
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Color.white.opacity(0.1))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 12)

            // Contenido del paso actual
            ZStack {
                if step == 0 { welcomeSlide.transition(.opacity) }
                else if step == 1 { fdaSlide.transition(.opacity) }
                else if step == 2 { helperSlide.transition(.opacity) }
                else { doneSlide.transition(.opacity) }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer con botones
            HStack {
                if step > 0 && step < 3 {
                    Button("Saltar por ahora") {
                        if step == 1 { step = 2 } else { step = 3 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                    .font(.bodyMedium)
                }
                Spacer()
                primaryButton
            }
            .padding(.horizontal, 32).padding(.vertical, 22)
        }
        .frame(width: 640, height: 540)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        VStack(spacing: 18) {
            Spacer()
            BrandMark(size: 92)
                .shadow(color: Theme.accent.opacity(0.4), radius: 20, y: 6)
            Text("Bienvenido a CleanMyOwn")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("Configura DOS permisos una sola vez y la app funcionará\npara siempre, sin contraseñas ni interrupciones.")
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
            HStack(spacing: 14) {
                bulletPoint(icon: "checkmark.shield.fill", tint: Theme.success,
                            title: "100 % local",
                            text: "Nada sale de tu Mac.")
                bulletPoint(icon: "bolt.shield.fill", tint: Theme.accent,
                            title: "Configura y olvida",
                            text: "Permisos una vez, limpieza sin fricción.")
                bulletPoint(icon: "trash.fill", tint: Theme.danger,
                            title: "Borrado consciente",
                            text: "Confirmación antes de cada borrado.")
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func bulletPoint(icon: String, tint: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.bodyMedium.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            }
            Text(text).font(.bodySmall).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fdaSlide: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 4)
            ZStack {
                Circle()
                    .fill(monitor.hasFullDiskAccess ? Theme.success.opacity(0.18) : Theme.danger.opacity(0.18))
                    .frame(width: 80, height: 80)
                Image(systemName: monitor.hasFullDiskAccess ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(monitor.hasFullDiskAccess ? Theme.success : Theme.danger)
            }
            Text("1 · Acceso completo al disco")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("macOS protege los datos de algunas apps con un permiso especial. Sin él, una parte de la limpieza queda fuera de alcance —\nincluso con permisos de administrador.")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 520)

            // Estado en vivo
            statusRow(
                ok: monitor.hasFullDiskAccess,
                okText: "Permiso concedido",
                pendingText: "Esperando que concedas el permiso…"
            )

            // Pasos visuales
            VStack(alignment: .leading, spacing: 10) {
                stepLine("1", "Pulsa «Abrir Configuración del Sistema».")
                stepLine("2", "Arrastra CleanMyOwn.app al panel — o usa el botón +.")
                stepLine("3", "Activa el toggle. Vuelve aquí. Esto se actualizará solo.")
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .onAppear { monitor.beginActivePolling() }
        .onDisappear { monitor.endActivePolling() }
        .onChange(of: monitor.hasFullDiskAccess) { _, granted in
            if granted { withAnimation { step = 2 } }
        }
    }

    /// Paso 2: asistente privilegiado — la pieza que elimina las contraseñas
    /// para siempre (CleanMyMac hace exactamente esto con su propio helper).
    private var helperSlide: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 4)
            ZStack {
                Circle()
                    .fill(admin.helperEnabled ? Theme.success.opacity(0.18) : Theme.accent.opacity(0.18))
                    .frame(width: 80, height: 80)
                Image(systemName: admin.helperEnabled ? "checkmark.shield.fill" : "bolt.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(admin.helperEnabled ? Theme.success : Theme.accent)
            }
            Text("2 · Adiós a las contraseñas")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("Instala el asistente en segundo plano y las tareas que requieren permisos de administrador (apps protegidas, copias de Time Machine, liberar memoria) funcionarán sin pedirte la contraseña nunca más. Se aprueba UNA vez y queda activo para siempre.")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 540)

            statusRow(
                ok: admin.helperEnabled,
                okText: "Asistente activo — sin contraseñas",
                pendingText: admin.helperStatus == .requiresApproval
                    ? "Apruébalo en Ajustes → Ítems de inicio → Permitir en segundo plano…"
                    : "Aún no instalado"
            )

            VStack(alignment: .leading, spacing: 10) {
                stepLine("1", "Pulsa «Instalar asistente».")
                stepLine("2", "macOS abrirá Ajustes: activa CleanMyOwn en «Permitir en segundo plano».")
                stepLine("3", "Vuelve aquí. Esto se actualizará solo.")
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .onAppear { startHelperPolling() }
        .onDisappear { stopHelperPolling() }
        .onChange(of: admin.helperStatus) { _, status in
            if status == .enabled { withAnimation { step = 3 } }
        }
    }

    private func statusRow(ok: Bool, okText: String, pendingText: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Theme.success : Theme.warning)
                .font(.system(size: 16, weight: .semibold))
            Text(ok ? okText : pendingText)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(ok ? Theme.success : Theme.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            (ok ? Theme.success : Theme.warning).opacity(0.08)
        ))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            (ok ? Theme.success : Theme.warning).opacity(0.25), lineWidth: 1
        ))
    }

    private func stepLine(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18)).frame(width: 24, height: 24)
                Text(num).font(.bodySmall.weight(.bold)).foregroundStyle(Theme.accent)
            }
            Text(text).font(.bodyMedium).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private var doneSlide: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(Theme.success.opacity(0.18)).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.success)
            }
            .shadow(color: Theme.success.opacity(0.4), radius: 20, y: 6)
            Text("Todo listo")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text(doneMessage)
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Spacer()
        }
    }

    private var doneMessage: String {
        switch (monitor.hasFullDiskAccess, admin.helperEnabled) {
        case (true, true):
            return "Acceso al disco concedido y asistente activo: limpieza completa, sin contraseñas, para siempre. Como debe ser."
        case (true, false):
            return "Acceso al disco concedido. Sin el asistente, las tareas protegidas pedirán tu contraseña una vez por sesión — puedes instalarlo cuando quieras desde Limpieza o Desinstalador."
        case (false, true):
            return "Asistente activo. Falta el acceso completo al disco para limpiar los datos de algunas apps — concédelo desde Resumen cuando quieras."
        default:
            return "Continuamos sin permisos extra. Algunos elementos protegidos no se podrán borrar; concédelos más tarde desde el Dashboard."
        }
    }

    // MARK: - Helper polling

    private func startHelperPolling() {
        admin.refreshHelperStatus()
        helperPollTask?.cancel()
        helperPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                admin.refreshHelperStatus()
            }
        }
    }

    private func stopHelperPolling() {
        helperPollTask?.cancel()
        helperPollTask = nil
    }

    // MARK: - Footer

    private var primaryButton: some View {
        Group {
            if step == 0 {
                actionButton(label: "Continuar", icon: "arrow.right") { step = 1 }
            } else if step == 1 {
                if monitor.hasFullDiskAccess {
                    actionButton(label: "Continuar", icon: "arrow.right", color: Theme.success) { step = 2 }
                } else {
                    actionButton(label: "Abrir Configuración del Sistema",
                                 icon: "arrow.up.right.square") {
                        AdminSessionService.openFullDiskAccessSettings()
                    }
                }
            } else if step == 2 {
                if admin.helperEnabled {
                    actionButton(label: "Continuar", icon: "arrow.right", color: Theme.success) { step = 3 }
                } else if admin.helperStatus == .requiresApproval {
                    actionButton(label: "Abrir Ajustes", icon: "arrow.up.right.square") {
                        admin.openHelperApprovalSettings()
                    }
                } else {
                    actionButton(label: "Instalar asistente", icon: "bolt.shield.fill") {
                        admin.registerHelper()
                    }
                }
            } else {
                actionButton(label: "Empezar", icon: "arrow.right") { finish() }
            }
        }
    }

    private func actionButton(label: String, icon: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.titleMedium)
                Image(systemName: icon)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(color.map { LinearGradient(colors: [$0, $0.opacity(0.8)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing) }
                          ?? Theme.brandGradient)
            )
            .foregroundStyle(.white)
            .shadow(color: Theme.shadowColor, radius: 10, y: 4)
        }.buttonStyle(.plain)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onFinish()
    }
}

#Preview {
    OnboardingView(monitor: PermissionsMonitor.shared, onFinish: {})
        .environmentObject(AdminSessionService())
}
