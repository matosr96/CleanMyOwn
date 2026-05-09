//
//  Sidebar.swift
//  CleanMyOwn
//
//  Barra lateral con navegación entre módulos. Más ancha y con personalidad:
//  hero del logo arriba con halo + título grande, items con highlight de
//  color por módulo, footer con pills de estado de permisos.
//

import SwiftUI

/// Cada módulo de la app.
enum AppModule: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case junkCleaner = "Limpieza"
    case uninstaller = "Desinstalador"
    case largeFiles = "Archivos grandes"
    case memoryFreer = "Memoria"
    case loginItems = "Inicio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:    return "square.grid.2x2.fill"
        case .junkCleaner:  return "trash.fill"
        case .uninstaller:  return "shippingbox.fill"
        case .largeFiles:   return "doc.zipper"
        case .memoryFreer:  return "memorychip.fill"
        case .loginItems:   return "power"
        }
    }

    var accentColor: Color {
        switch self {
        case .dashboard:    return Theme.accent
        case .junkCleaner:  return Theme.success
        case .uninstaller:  return Theme.warning
        case .largeFiles:   return Color(red: 0.85, green: 0.50, blue: 1.0)
        case .memoryFreer:  return Color(red: 0.30, green: 0.85, blue: 0.95)
        case .loginItems:   return Theme.danger
        }
    }

    /// Subtítulo opcional bajo el nombre del módulo en la sidebar.
    var subtitle: String {
        switch self {
        case .dashboard:    return "Estado del sistema"
        case .junkCleaner:  return "Liberar espacio"
        case .uninstaller:  return "Apps instaladas"
        case .largeFiles:   return "Archivos pesados"
        case .memoryFreer:  return "Liberar RAM"
        case .loginItems:   return "Launch Agents"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: AppModule
    @EnvironmentObject private var permissions: PermissionsMonitor

    @State private var logoRotation: Double = -10
    @State private var logoGlow: Double = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBlock
            sectionLabel("MÓDULOS")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppModule.allCases) { module in
                    SidebarItem(
                        module: module,
                        isSelected: selection == module,
                        action: { selection = module }
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            footer
        }
        .frame(width: 260)
        .background(
            ZStack {
                Theme.sidebar
                LinearGradient(
                    colors: [Color.white.opacity(0.04), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
        .overlay(alignment: .trailing) {
            // Borde derecho sutil con glow
            Rectangle()
                .fill(LinearGradient(
                    colors: [Theme.accent.opacity(0.20), .clear, Color(red: 0.85, green: 0.50, blue: 1.0).opacity(0.15)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 1)
        }
    }

    // MARK: - Hero (logo + nombre)

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                // Glow externo
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 76, height: 76)
                    .blur(radius: 32)
                    .opacity(logoGlow * 0.9)
                Circle()
                    .fill(Color(red: 0.85, green: 0.50, blue: 1.0))
                    .frame(width: 56, height: 56)
                    .blur(radius: 26)
                    .opacity(logoGlow * 0.7)
                // Logo
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 12, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .rotation3DEffect(.degrees(logoRotation),
                              axis: (x: 0.4, y: 1, z: 0.2),
                              perspective: 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    logoRotation = 12
                }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    logoGlow = 0.95
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CleanMyOwn")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Limpia tu Mac.")
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.label)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
    }

    // MARK: - Footer con status pills

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ESTADO")
            statusPill(
                icon: permissions.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                text: permissions.hasFullDiskAccess ? "Acceso disco completo" : "Acceso disco parcial",
                tint: permissions.hasFullDiskAccess ? Theme.success : Theme.warning
            )
            HStack {
                Text("v1.0").font(.bodySmall).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("matosr96").font(.bodySmall).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
        }
        .padding(.bottom, 18)
    }

    private func statusPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.bodySmall)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

private struct SidebarItem: View {
    let module: AppModule
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Indicador animado a la izquierda
                Capsule()
                    .fill(module.accentColor)
                    .frame(width: 4, height: isSelected ? 32 : 0)
                    .opacity(isSelected ? 1 : 0)
                    .shadow(color: module.accentColor.opacity(0.6), radius: 6)

                // Icono dentro de pill colorida cuando está activo
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(module.accentColor.opacity(0.18))
                            .frame(width: 36, height: 36)
                    }
                    Image(systemName: module.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? module.accentColor
                                         : (hovering ? Theme.textPrimary : Theme.textSecondary))
                        .frame(width: 36, height: 36)
                        .shadow(color: isSelected ? module.accentColor.opacity(0.6) : .clear,
                                radius: isSelected ? 8 : 0)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(module.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    Text(module.subtitle)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.06)
                          : (hovering ? Color.white.opacity(0.03) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? module.accentColor.opacity(0.22) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(hovering && !isSelected ? 1.012 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Anim.bouncy, value: isSelected)
        .animation(Anim.hover, value: hovering)
    }
}

#Preview {
    Sidebar(selection: .constant(.dashboard))
        .environmentObject(PermissionsMonitor.shared)
        .frame(height: 700)
        .background(Theme.background)
}
