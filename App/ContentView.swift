//
//  ContentView.swift
//  CleanMyOwn
//
//  Vista raíz: sidebar + área de contenido del módulo seleccionado.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppModule = .dashboard
    /// Dirección del último cambio de módulo (para la transición direccional).
    @State private var movedDown = true

    /// Binding que captura la DIRECCIÓN del salto en el menú antes de animar.
    private var directedSelection: Binding<AppModule> {
        Binding(
            get: { selection },
            set: { newValue in
                let all = AppModule.allCases
                let from = all.firstIndex(of: selection) ?? 0
                let to = all.firstIndex(of: newValue) ?? 0
                movedDown = to >= from
                selection = newValue
            }
        )
    }

    var body: some View {
        // UN solo lienzo: el fondo vivo corre bajo TODA la ventana — sidebar
        // incluido — sin divisor. La navegación flota sobre la misma
        // superficie que el contenido; nada se siente "componente aparte".
        ZStack {
            AnimatedBackground(intensity: 0.35)

            HStack(spacing: 0) {
                Sidebar(selection: directedSelection)

                Group {
                    switch selection {
                    case .dashboard:    DashboardView(selection: directedSelection)
                    case .junkCleaner:  JunkCleanerView()
                    case .uninstaller:  UninstallerView()
                    case .largeFiles:   LargeFilesView()
                    case .memoryFreer:  MemoryFreerView()
                    case .loginItems:   LoginItemsView()
                    }
                }
                .id(selection)
                // Bajas en el menú → el contenido entra desde abajo; subes →
                // desde arriba. La navegación y el contenido se sienten una
                // sola pieza física.
                .transition(.moduleSlide(up: movedDown))
                .animation(Anim.modulePush, value: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(PermissionsMonitor.shared)
        .environmentObject(AdminSessionService())
        .frame(width: 1100, height: 700)
}
