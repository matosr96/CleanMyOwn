//
//  SettingsView.swift
//  CleanMyOwn
//
//  Ventana de Ajustes estándar de macOS (⌘, / menú CleanMyOwn → Ajustes…):
//  Apariencia · General · Asistente · Acerca de.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Apariencia", systemImage: "paintpalette") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            HelperSettings()
                .tabItem { Label("Asistente", systemImage: "bolt.shield") }
            AboutSettings()
                .tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 480)
        .background(Theme.background)
    }
}

// MARK: - Apariencia

private struct AppearanceSettings: View {
    @EnvironmentObject private var themeManager: ThemeManager

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tema")
                .font(.titleMedium).foregroundStyle(Theme.textPrimary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    themeCard(theme)
                }
            }

            Text("Multicolor es la firma de la app: el lienzo se tiñe con el color de cada módulo a plena intensidad. En Oscuro el fondo queda en calma; Sistema sigue la apariencia de tu Mac.")
                .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let isSelected = themeManager.selection == theme
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) { themeManager.selection = theme }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                themePreview(theme)
                HStack(spacing: 6) {
                    Image(systemName: theme.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    Text(theme.displayName)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(theme.blurb)
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.onSurface(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.onSurface(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tema \(theme.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Mini-lienzo de muestra de cada tema.
    private func themePreview(_ theme: AppTheme) -> some View {
        let dark = theme.resolvesDark(systemIsDark: themeManager.systemIsDark)
        let bg: Color = dark ? Color(red: 0.07, green: 0.08, blue: 0.10)
                             : Color(red: 0.95, green: 0.95, blue: 0.97)
        let vivid = theme == .multicolor
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg)
            HStack(spacing: -10) {
                Circle().fill(Color(red: 0.45, green: 0.40, blue: 1.0))
                Circle().fill(Color(red: 0.20, green: 0.85, blue: 0.55))
                Circle().fill(Color(red: 0.85, green: 0.50, blue: 1.0))
            }
            .frame(height: 26)
            .blur(radius: 10)
            .opacity(theme == .dark ? 0.25 : (vivid ? 0.95 : 0.55))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 18)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(DeleteMode.storageKey) private var deleteToTrash = false
    @EnvironmentObject private var engagement: EngagementService
    @EnvironmentObject private var history: CleaningHistoryService

    var body: some View {
        Form {
            Toggle(isOn: $deleteToTrash) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mover a la Papelera al limpiar")
                    Text("Recuperable desde la Papelera. Copias de Time Machine, simuladores y borrados con privilegios siguen siendo permanentes.")
                        .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                }
            }
            Toggle(isOn: $engagement.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avisos inteligentes")
                    Text("Notifica si la Papelera supera 10 GB o llevas más de dos semanas sin escanear. Pocas veces y con criterio.")
                        .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                }
            }
            LabeledContent("Historial") {
                Text("\(history.records.count) operaciones · \(history.totalFreedDiskBytes.formattedAsBytes) liberados")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

// MARK: - Asistente

private struct HelperSettings: View {
    @EnvironmentObject private var admin: AdminSessionService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelperStatusControls()
            Text("El asistente es un proceso del sistema con permisos acotados: sólo sabe borrar dentro de las rutas que la app limpia, gestionar copias de Time Machine y liberar memoria. Sin él, la app funciona igual pidiendo tu contraseña una vez por sesión.")
                .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(22)
        .frame(height: 180)
    }
}

// MARK: - Acerca de

private struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Versión \(v)"
    }

    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 56)
                .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
            Text("CleanMyOwn")
                .font(.titleLarge).foregroundStyle(Theme.textPrimary)
            Text(version)
                .font(.bodySmall).foregroundStyle(Theme.textTertiary)
            Text("100 % local. Nada sale de tu Mac.")
                .font(.bodySmall).foregroundStyle(Theme.textSecondary)
            Link("github.com/matosr96/CleanMyOwn",
                 destination: URL(string: "https://github.com/matosr96/CleanMyOwn")!)
                .font(.bodySmall)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(EngagementService())
        .environmentObject(CleaningHistoryService())
        .environmentObject(AdminSessionService())
}
