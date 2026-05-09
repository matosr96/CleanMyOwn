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
            
            // Contenido del módulo
            Group {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .junkCleaner:
                    JunkCleanerView()
                case .uninstaller:
                    UninstallerView()
                case .largeFiles:
                    LargeFilesView()
                case .memoryFreer:
                    MemoryFreerView()
                case .loginItems:
                    LoginItemsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 700)
}
