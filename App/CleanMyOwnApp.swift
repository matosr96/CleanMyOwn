//
//  CleanMyOwnApp.swift
//  CleanMyOwn
//
//  Entry point de la aplicación.
//

import SwiftUI

@main
struct CleanMyOwnApp: App {
    @StateObject private var permissions = PermissionsMonitor.shared
    /// Sesión admin ÚNICA para toda la app: cambiar de módulo no la pierde,
    /// así la contraseña se pide de verdad una sola vez por sesión.
    @StateObject private var adminSession = AdminSessionService()
    /// Escáner de basura compartido: el Smart Scan del Dashboard y el módulo
    /// de Limpieza operan sobre el MISMO estado (escanear en uno se ve en el otro).
    @StateObject private var junkService = JunkScanService()
    /// Historial persistente de limpiezas — la memoria de confianza de la app.
    @StateObject private var history = CleaningHistoryService()
    /// Avisos inteligentes opt-in (vive porque la app queda residente).
    @StateObject private var engagement = EngagementService()
    /// Temas: Sistema / Claro / Oscuro / Multicolor.
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingOnboarding: Bool = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some Scene {
        // Ventana ÚNICA (no WindowGroup): el menubar puede reabrirla con
        // openWindow(id:) sin riesgo de duplicarla.
        Window("CleanMyOwn", id: "main") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 760)
                .environmentObject(permissions)
                .environmentObject(adminSession)
                .environmentObject(junkService)
                .environmentObject(history)
                .environmentObject(engagement)
                .environmentObject(themeManager)
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView(monitor: permissions, onFinish: {
                        showingOnboarding = false
                    })
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // Ajustes nativos: ⌘, y menú CleanMyOwn → Ajustes…
        Settings {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(engagement)
                .environmentObject(history)
                .environmentObject(adminSession)
                .preferredColorScheme(themeManager.colorScheme)
                .id(themeManager.themeKey)
        }

        // Companion de menubar: la app queda residente con el Mac de un
        // vistazo y acciones rápidas — presencia diaria.
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(permissions)
                .environmentObject(adminSession)
                .environmentObject(junkService)
                .environmentObject(history)
                .environmentObject(engagement)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}
