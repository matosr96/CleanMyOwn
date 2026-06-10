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
            
            // Un ÚNICO fondo animado que persiste entre vistas: si viviera
            // dentro de cada módulo, cada cambio desmontaría y volvería a
            // montar el Canvas (blur de 90px) y el fondo se vería "asentarse".
            // Aquí sólo el CONTENIDO cruza el fade; el fondo nunca parpadea.
            ZStack {
                AnimatedBackground(intensity: 0.35)

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
            }
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
