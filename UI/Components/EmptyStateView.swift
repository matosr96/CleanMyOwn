//
//  EmptyStateView.swift
//  CleanMyOwn
//
//  Empty state con ilustración animada, perfectamente centrado en el
//  espacio disponible. Pensado para reemplazar los `VStack { Image; Text }`
//  pelados que estaban repetidos en cada módulo.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// Vista opcional para una acción primaria (botón, etc.).
    var action: AnyView? = nil

    @State private var pulse: CGFloat = 0.95
    @State private var float: CGFloat = -4

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Halos respirantes
                Circle().fill(tint.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulse * 1.05)
                Circle().fill(tint.opacity(0.14))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse)
                Circle().fill(tint.opacity(0.20))
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.7), radius: 12)
                    .offset(y: float)
            }
            .frame(width: 220, height: 220)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    pulse = 1.05
                }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    float = 4
                }
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            if let action {
                action.padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
