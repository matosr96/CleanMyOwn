//
//  ContentView.swift
//  CleanMyOwn
//
//  Vista raíz: sidebar + área de contenido del módulo seleccionado.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppModule = .dashboard
    
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
            
            // Separador sutil
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 1)
            
            // Contenido del módulo con cross-fade entre cambios
            Group {
                switch selection {
                case .dashboard:    DashboardView(selection: $selection)
                case .junkCleaner:  JunkCleanerView()
                case .uninstaller:  UninstallerView()
                case .largeFiles:   LargeFilesView()
                case .memoryFreer:  MemoryFreerView()
                case .loginItems:   LoginItemsView()
                }
            }
            .id(selection)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
                removal: .opacity
            ))
            .animation(Anim.crossfade, value: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
