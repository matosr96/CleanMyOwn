//
//  Sidebar.swift
//  CleanMyOwn
//
//  Barra lateral sobria y nativa: header compacto con la marca, items de
//  UNA línea con chip de color, highlight de selección que se desliza
//  (matchedGeometryEffect) y footer de estado minimal. Las animaciones
//  viven en los detalles, no en el ruido.
//

import SwiftUI

/// Cada módulo de la app. El rawValue es el nombre visible.
enum AppModule: String, CaseIterable, Identifiable {
    case dashboard = "Resumen"
    case junkCleaner = "Limpieza"
    case uninstaller = "Desinstalador"
    case largeFiles = "Archivos grandes"
    case memoryFreer = "Memoria"
    case loginItems = "Arranque"

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

    /// Descripción corta — la usan las cabeceras de cada módulo.
    var subtitle: String {
        switch self {
        case .dashboard:    return "Estado de tu Mac"
        case .junkCleaner:  return "Liberar espacio"
        case .uninstaller:  return "Apps y sus restos"
        case .largeFiles:   return "Pesados y duplicados"
        case .memoryFreer:  return "Liberar RAM"
        case .loginItems:   return "Apps en segundo plano"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: AppModule
    @EnvironmentObject private var permissions: PermissionsMonitor
    @EnvironmentObject private var admin: AdminSessionService
    @EnvironmentObject private var junk: JunkScanService

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow

            VStack(alignment: .leading, spacing: 3) {
                ForEach(AppModule.allCases) { module in
                    SidebarItem(
                        module: module,
                        isSelected: selection == module,
                        badge: badge(for: module),
                        namespace: selectionNamespace,
                        action: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                selection = module
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            footer
        }
        .frame(width: 224)
        // Sin fondo propio ni divisor: el sidebar flota sobre el MISMO lienzo
        // animado que el contenido — la app es una sola superficie.
    }

    /// Dato vivo por módulo: el sidebar también informa, no sólo navega.
    private func badge(for module: AppModule) -> String? {
        switch module {
        case .junkCleaner:
            let bytes = junk.totalBytes
            return bytes > 0 && !junk.isScanning ? bytes.formattedAsBytes : nil
        default:
            return nil
        }
    }

    // MARK: - Marca (compacta, sin hero)

    private var brandRow: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 2)
            Text("CleanMyOwn")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Footer de estado, sin cajas

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow(
                ok: permissions.hasFullDiskAccess,
                text: permissions.hasFullDiskAccess ? "Acceso total al disco" : "Acceso al disco parcial"
            )
            statusRow(
                ok: admin.helperEnabled,
                pending: admin.helperStatus == .requiresApproval,
                text: admin.helperEnabled ? "Asistente activo"
                    : (admin.helperStatus == .requiresApproval ? "Asistente pendiente" : "Asistente no instalado")
            )
            HStack {
                Text("v1.0").font(.system(size: 10.5, design: .rounded))
                Spacer()
                Text("matosr96").font(.system(size: 10.5, design: .rounded))
            }
            .foregroundStyle(Theme.textTertiary.opacity(0.7))
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func statusRow(ok: Bool, pending: Bool = false, text: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ok ? Theme.success : (pending ? Theme.warning : Theme.textTertiary.opacity(0.5)))
                .frame(width: 6, height: 6)
                .shadow(color: ok ? Theme.success.opacity(0.6) : .clear, radius: 3)
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct SidebarItem: View {
    let module: AppModule
    let isSelected: Bool
    let badge: String?
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Chip de color: gradiente lleno al seleccionar, tinte en reposo.
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient(
                                    colors: [module.accentColor, module.accentColor.opacity(0.62)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(module.accentColor.opacity(hovering ? 0.24 : 0.14)))
                        .frame(width: isSelected ? 30 : 27, height: isSelected ? 30 : 27)
                    Image(systemName: module.icon)
                        .font(.system(size: isSelected ? 13 : 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : module.accentColor)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .shadow(color: module.accentColor.opacity(isSelected ? 0.45 : 0),
                        radius: 7, y: 2)

                // El seleccionado se EXPANDE y revela su descripción —
                // jerarquía y movimiento sin ensuciar el resto.
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(module.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    if isSelected {
                        Text(module.subtitle)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer(minLength: 4)

                // Dato vivo (ej: GB de basura encontrados por el Smart Scan)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warning.opacity(0.14)))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, isSelected ? 9 : 6)
            .background {
                // La tarjeta de selección SE TRANSFORMA al viajar entre items
                // (matchedGeometry anima posición Y tamaño).
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.cardGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [module.accentColor.opacity(0.45),
                                                 module.accentColor.opacity(0.10)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: module.accentColor.opacity(0.18), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "sidebar.selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                }
            }
            // Tilt 3D sutil al hover
            .rotation3DEffect(
                .degrees(hovering && !isSelected ? 2.5 : 0),
                axis: (x: 0.35, y: -1, z: 0),
                perspective: 0.7
            )
            .scaleEffect(hovering && !isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Anim.hover, value: hovering)
    }
}

#Preview {
    Sidebar(selection: .constant(.dashboard))
        .environmentObject(PermissionsMonitor.shared)
        .environmentObject(AdminSessionService())
        .environmentObject(JunkScanService())
        .frame(height: 700)
        .background(Theme.background)
}
