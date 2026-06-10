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
    @State private var showingOnboarding: Bool = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 760)
                .environmentObject(permissions)
                .environmentObject(adminSession)
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView(monitor: permissions, onFinish: {
                        showingOnboarding = false
                    })
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
