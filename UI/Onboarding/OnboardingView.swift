//
//  OnboardingView.swift
//  CleanMyOwn
//
//  Wizard de bienvenida que guía al usuario a otorgar Full Disk Access.
//  Se muestra como sheet la primera vez que se abre la app, o cuando
//  el usuario lo invoca desde el Dashboard.
//
//  El paso 2 detecta automáticamente cuando el usuario concede FDA en
//  System Settings (vía PermissionsMonitor) y avanza solo al paso 3.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var monitor: PermissionsMonitor
    /// Se cierra la sheet
    let onFinish: () -> Void

    @State private var step: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header con progreso
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
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
                else { doneSlide.transition(.opacity) }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer con botones
            HStack {
                if step > 0 && step < 2 {
                    Button("Saltar por ahora") {
                        finish()
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
        .frame(width: 640, height: 520)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 92, height: 92)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 20, y: 6)
            Text("Bienvenido a CleanMyOwn")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("Para limpiar a fondo tu Mac necesitamos UN permiso del sistema.\nTe guío en menos de 30 segundos.")
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
            HStack(spacing: 14) {
                bulletPoint(icon: "checkmark.shield.fill", tint: Theme.success,
                            title: "100 % local",
                            text: "Nada sale de tu Mac.")
                bulletPoint(icon: "trash.fill", tint: Theme.danger,
                            title: "Borrado consciente",
                            text: "Confirmación antes de cada borrado.")
                bulletPoint(icon: "bolt.fill", tint: Theme.warning,
                            title: "Liberá GBs",
                            text: "Cachés, snapshots, sims y más.")
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
            Text("Acceso completo al disco")
                .font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("macOS protege los datos de apps sandboxed (~/Library/Containers) con TCC. Sin este permiso es imposible borrarlos —\nni siquiera con admin.")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 520)

            // Estado en vivo
            HStack(spacing: 10) {
                Image(systemName: monitor.hasFullDiskAccess ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(monitor.hasFullDiskAccess ? Theme.success : Theme.warning)
                    .font(.system(size: 16, weight: .semibold))
                Text(monitor.hasFullDiskAccess ? "Permiso concedido" : "Esperando que concedas el permiso…")
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(monitor.hasFullDiskAccess ? Theme.success : Theme.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                (monitor.hasFullDiskAccess ? Theme.success : Theme.warning).opacity(0.08)
            ))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                (monitor.hasFullDiskAccess ? Theme.success : Theme.warning).opacity(0.25), lineWidth: 1
            ))

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
            Text(monitor.hasFullDiskAccess
                 ? "FDA concedido. El modo administrador (para snapshots TM y eliminaciones protegidas) se activa con un solo click cuando lo necesites — pedimos tu contraseña una sola vez por sesión."
                 : "Continuamos sin FDA. Algunos elementos huérfanos protegidos no se podrán borrar. Puedes concederlo más tarde desde el Dashboard.")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Spacer()
        }
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
            } else {
                actionButton(label: "Empezar", icon: "sparkles") { finish() }
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
}
