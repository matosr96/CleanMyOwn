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
    @State private var showingOnboarding: Bool = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 760)
                .environmentObject(permissions)
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
