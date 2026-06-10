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
        // Rail de SOLO iconos (concepto glass): la navegación se reduce a una
        // columna de objetos de cristal flotando sobre el lienzo. Los nombres
        // viven en tooltips y en las cabeceras de cada módulo.
        VStack(spacing: 0) {
            BrandMark(size: 32)
                .shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 3)
                .padding(.top, 20)
                .padding(.bottom, 26)

            VStack(spacing: 10) {
                ForEach(AppModule.allCases) { module in
                    RailItem(
                        module: module,
                        isSelected: selection == module,
                        showsAlert: module == .junkCleaner && junk.totalBytes > 0 && !junk.isScanning,
                        alertText: junk.totalBytes.formattedAsBytes,
                        namespace: selectionNamespace,
                        action: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                selection = module
                            }
                        }
                    )
                }
            }

            Spacer()

            // Estado: dos puntos con tooltip — mínima superficie, máxima señal
            VStack(spacing: 10) {
                statusDot(
                    ok: permissions.hasFullDiskAccess,
                    help: permissions.hasFullDiskAccess ? "Acceso total al disco" : "Acceso al disco parcial — concédelo en Resumen"
                )
                statusDot(
                    ok: admin.helperEnabled,
                    pending: admin.helperStatus == .requiresApproval,
                    help: admin.helperEnabled ? "Asistente activo — sin contraseñas"
                        : (admin.helperStatus == .requiresApproval ? "Asistente pendiente de aprobación" : "Asistente no instalado")
                )
            }
            .padding(.bottom, 18)
        }
        .frame(width: 72)
        // Sin fondo propio ni divisor: flota sobre el MISMO lienzo que el contenido.
    }

    private func statusDot(ok: Bool, pending: Bool = false, help: String) -> some View {
        Circle()
            .fill(ok ? Theme.success : (pending ? Theme.warning : Theme.textTertiary.opacity(0.45)))
            .frame(width: 7, height: 7)
            .shadow(color: ok ? Theme.success.opacity(0.7) : (pending ? Theme.warning.opacity(0.6) : .clear), radius: 4)
            .help(help)
    }
}

private struct RailItem: View {
    let module: AppModule
    let isSelected: Bool
    let showsAlert: Bool
    let alertText: String
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Cristal de selección: viaja y se transforma entre items
                if isSelected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(module.accentColor.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.35), module.accentColor.opacity(0.25), .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: module.accentColor.opacity(0.35), radius: 12, y: 4)
                        .matchedGeometryEffect(id: "rail.selection", in: namespace)
                        .frame(width: 46, height: 46)
                }

                Image(systemName: module.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : module.accentColor.opacity(hovering ? 1 : 0.75))
                    .symbolEffect(.bounce, value: isSelected)
                    .shadow(color: isSelected ? module.accentColor.opacity(0.8) : .clear, radius: 6)
            }
            .frame(width: 46, height: 46)
            .overlay(alignment: .topTrailing) {
                // Dato vivo: punto de alerta con el detalle en tooltip
                if showsAlert {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 8, height: 8)
                        .shadow(color: Theme.warning.opacity(0.8), radius: 4)
                        .offset(x: 1, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // 3D: el icono se inclina hacia el cursor
            .rotation3DEffect(
                .degrees(hovering && !isSelected ? 7 : 0),
                axis: (x: 0.4, y: -1, z: 0),
                perspective: 0.65
            )
            .scaleEffect(hovering ? 1.10 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Anim.snappy, value: hovering)
        .help(showsAlert ? "\(module.rawValue) — \(alertText) de basura encontrada" : "\(module.rawValue) · \(module.subtitle)")
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
