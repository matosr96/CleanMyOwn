//
//  StatCard.swift
//  CleanMyOwn
//
//  Card de estadística usada en el dashboard.
//

import SwiftUI

struct StatCard: View {
    let icon: String          // SF Symbol
    let title: String
    let value: String
    let subtitle: String
    let accentColor: Color
    
    @State private var hovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icono con fondo de color tenue
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.label)
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.titleLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(hovering ? Theme.cardHover : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

#Preview {
    VStack(spacing: 12) {
        StatCard(
            icon: "internaldrive.fill",
            title: "ALMACENAMIENTO",
            value: "240 GB",
            subtitle: "de 500 GB usados",
            accentColor: Theme.accent
        )
        StatCard(
            icon: "memorychip.fill",
            title: "MEMORIA",
            value: "12.4 GB",
            subtitle: "de 16 GB en uso",
            accentColor: Theme.success
        )
    }
    .padding()
    .background(Theme.background)
    .frame(width: 400)
}
