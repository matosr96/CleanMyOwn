//
//  PolishedButtonStyle.swift
//  CleanMyOwn
//
//  Estilos de botón que se sienten vivos: scale al press, glow al hover,
//  shadow expandida cuando el cursor está encima. Toda la app debería usar
//  estos estilos en lugar de fondos custom inline.
//

import SwiftUI

/// Botón principal con gradiente de marca. Para acciones primarias
/// (Escanear, Continuar, Activar admin, etc.).
struct PolishedPrimaryButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.brandGradient)
    var glow: Color = Theme.accent
    var horizontal: CGFloat = 22
    var vertical: CGFloat = 12

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                // Glow ring que aparece al hover
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .stroke(Color.white.opacity(hovering ? 0.18 : 0), lineWidth: 1)
            )
            .shadow(color: glow.opacity(hovering ? 0.45 : 0.20),
                    radius: hovering ? 18 : 10,
                    y: hovering ? 6 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.02 : 1.0))
            .animation(Anim.snappy, value: configuration.isPressed)
            .animation(Anim.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Botón secundario (gris suave). Para acciones de bajo peso (Cancelar,
/// Desactivar, Actualizar).
struct PolishedSecondaryButtonStyle: ButtonStyle {
    var horizontal: CGFloat = 14
    var vertical: CGFloat = 9

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMedium)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(hovering ? 0.10 : 0.04), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Anim.snappy, value: configuration.isPressed)
            .animation(Anim.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Botón destructivo (rojo). Solo para confirmaciones de borrado.
struct PolishedDestructiveButtonStyle: ButtonStyle {
    var horizontal: CGFloat = 22
    var vertical: CGFloat = 12

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.danger, Color(red: 1.0, green: 0.55, blue: 0.40)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: Theme.danger.opacity(hovering ? 0.5 : 0.25),
                    radius: hovering ? 18 : 10, y: hovering ? 6 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.02 : 1.0))
            .animation(Anim.snappy, value: configuration.isPressed)
            .animation(Anim.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}
