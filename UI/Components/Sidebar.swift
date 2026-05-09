//
//  Sidebar.swift
//  CleanMyOwn
//
//  Barra lateral con navegación entre módulos.
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
}

struct Sidebar: View {
    @Binding var selection: AppModule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo / nombre de la app
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("CleanMyOwn")
                    .font(.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 28)
            
            // Items
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AppModule.allCases) { module in
                    SidebarItem(
                        module: module,
                        isSelected: selection == module,
                        action: { selection = module }
                    )
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // Footer
            VStack(alignment: .leading, spacing: 4) {
                Text("v0.1 — Fase 1")
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 220)
        .background(Theme.sidebar)
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
                Image(systemName: module.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? module.accentColor : Theme.textSecondary)
                    .frame(width: 18)
                Text(module.rawValue)
                    .font(.bodyMedium)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.07) : (hovering ? Color.white.opacity(0.03) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}

#Preview {
    Sidebar(selection: .constant(.dashboard))
        .frame(height: 600)
        .background(Theme.background)
}
