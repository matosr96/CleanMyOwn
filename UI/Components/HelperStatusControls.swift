//
//  HelperStatusControls.swift
//  CleanMyOwn
//
//  Fila compacta con el estado del helper privilegiado (SMAppService.daemon)
//  y la acción correspondiente: instalar, aprobar en Ajustes, o desinstalar.
//  Con el helper activo, las operaciones root no piden contraseña — ni
//  siquiera una vez por sesión — y persiste entre reinicios de la app.
//

import ServiceManagement
import SwiftUI

struct HelperStatusControls: View {
    @EnvironmentObject private var admin: AdminSessionService

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.bodySmall)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.18), lineWidth: 1))
        .onAppear { admin.refreshHelperStatus() }
    }

    @ViewBuilder
    private var actions: some View {
        if admin.helperIsBroken {
            // Registrado pero no contesta (típico tras recompilar): reinstalar
            // lo vuelve a registrar con la firma actual.
            Button("Reinstalar") { admin.registerHelper() }
                .buttonStyle(.plain)
                .font(.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Button(action: { admin.unregisterHelper() }) {
                Image(systemName: "xmark.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help("Quitar el asistente")
        } else {
            switch admin.helperStatus {
            case .enabled:
                Button("Desinstalar") { admin.unregisterHelper() }
                    .buttonStyle(.plain)
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textTertiary)
            case .requiresApproval:
                Button("Abrir Ajustes") { admin.openHelperApprovalSettings() }
                    .buttonStyle(.plain)
                    .font(.bodySmall.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Button(action: { admin.refreshHelperStatus() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textTertiary)
                .help("Revisar si ya quedó aprobado")
            default:
                Button("Instalar asistente") { admin.registerHelper() }
                    .buttonStyle(.plain)
                    .font(.bodySmall.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var icon: String {
        if admin.helperIsBroken { return "exclamationmark.triangle.fill" }
        switch admin.helperStatus {
        case .enabled: return "bolt.shield.fill"
        case .requiresApproval: return "hourglass"
        default: return "shield.lefthalf.filled.badge.checkmark"
        }
    }

    private var tint: Color {
        if admin.helperIsBroken { return Theme.warning }
        switch admin.helperStatus {
        case .enabled: return Theme.success
        case .requiresApproval: return Theme.warning
        default: return Theme.accent
        }
    }

    private var label: String {
        if admin.helperIsBroken {
            return "El asistente está instalado pero no responde. Mientras tanto se pide la contraseña; reinstálalo para volver a operar sin ella."
        }
        switch admin.helperStatus {
        case .enabled:
            return "Asistente en segundo plano activo — tareas protegidas sin contraseña, para siempre."
        case .requiresApproval:
            return "Asistente pendiente de aprobación en Ajustes → Ítems de inicio → Permitir en segundo plano."
        default:
            // macOS reporta .notFound (no .notRegistered) antes del primer
            // registro, así que ambos estados muestran la invitación a instalar.
            return "Opcional: instala el asistente en segundo plano y olvídate de la contraseña."
        }
    }
}

#Preview {
    HelperStatusControls()
        .environmentObject(AdminSessionService())
        .padding()
}
