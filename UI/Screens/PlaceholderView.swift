//
//  PlaceholderView.swift
//  CleanMyOwn
//
//  Vista temporal para módulos que vamos a construir en próximas fases.
//

import SwiftUI

struct PlaceholderView: View {
    let module: AppModule
    let phaseDescription: String
    
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(module.accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: module.icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(module.accentColor)
            }
            Text(module.rawValue)
                .font(.displayMedium)
                .foregroundStyle(Theme.textPrimary)
            Text("Próximamente")
                .font(.titleMedium)
                .foregroundStyle(Theme.textSecondary)
            Text(phaseDescription)
                .font(.bodyMedium)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

#Preview {
    PlaceholderView(
        module: .junkCleaner,
        phaseDescription: "Este módulo escaneará archivos de caché, logs y temporales."
    )
}
