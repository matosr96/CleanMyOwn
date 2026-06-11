//
//  Theme.swift
//  CleanMyOwn
//
//  Paleta y tipografía de la app. Desde la llegada de los temas, cada
//  constante es COMPUTADA contra la paleta activa de ThemeManager — los
//  call sites (`Theme.background`, `Theme.card`…) no cambian, y el cambio
//  de tema reconstruye el árbol vía `.id(themeKey)` en ContentView.
//

import SwiftUI

@MainActor
enum Theme {
    private static var p: Palette { ThemeManager.shared.palette }

    // MARK: - Colores base

    /// Fondo principal de la app.
    static var background: Color { p.background }

    /// Fondo de la sidebar (sin uso directo desde el rail; se mantiene por paleta).
    static var sidebar: Color { p.cardGradientBottom }

    /// Fondo de cards y paneles sólidos (chips, botones secundarios).
    static var card: Color { p.card }

    /// Fondo de cards al hacer hover.
    static var cardHover: Color { p.cardHover }

    /// Texto principal.
    static var textPrimary: Color { p.textPrimary }

    /// Texto secundario.
    static var textSecondary: Color { p.textSecondary }

    /// Texto terciario / labels.
    static var textTertiary: Color { p.textTertiary }

    /// Tinta "sobre superficie" (bordes, fills y separadores sutiles):
    /// blanco en temas oscuros, negro en claro. Sustituye a los
    /// `Theme.onSurface(x)` hardcodeados.
    static func onSurface(_ opacity: Double) -> Color {
        p.onSurface.opacity(opacity)
    }

    // MARK: - Acentos

    /// Azul/morado de marca (botones primarios, items activos).
    static var accent: Color { p.accent }

    /// Verde de éxito (espacio liberado, todo OK).
    static var success: Color { p.success }

    /// Naranja de advertencia.
    static var warning: Color { p.warning }

    /// Rojo de error/peligro.
    static var danger: Color { p.danger }

    // MARK: - Gradientes (la firma visual)

    /// Gradiente de marca para el botón "Scan" gigante.
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.45, green: 0.40, blue: 1.0),
            Color(red: 0.30, green: 0.65, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gradiente verde (espacio limpio, salud).
    static let healthGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.85, blue: 0.55),
            Color(red: 0.10, green: 0.65, blue: 0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gradiente sutil para fondos de cards destacados.
    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [p.cardGradientTop, p.cardGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Sombras

    static var shadowColor: Color { p.shadow }
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 4

    // MARK: - Bordes redondeados

    static let cornerSmall: CGFloat = 8
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 18
}

// MARK: - Superficie de cristal

extension View {
    /// Tarjeta de vidrio esmerilado: el lienzo de color respira A TRAVÉS del
    /// material en vez de quedar tapado por un fill opaco.
    @MainActor
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.onSurface(0.20), Theme.onSurface(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Theme.shadowColor.opacity(0.7), radius: 18, y: 8)
    }
}

// MARK: - Tipografía

extension Font {
    /// HERO: número/valor protagonista (porcentajes grandes, contadores).
    /// Bajado de 96 a 64 para no romper layouts en ventanas estrechas. Para
    /// que escale bien hay que combinarlo con `.lineLimit(1).minimumScaleFactor(0.5)`.
    static let heroNumber = Font.system(size: 64, weight: .black, design: .rounded)
    /// HERO: título de pantalla principal (Dashboard greeting, etc.).
    static let heroTitle = Font.system(size: 44, weight: .black, design: .rounded)

    static let displayLarge = Font.system(size: 42, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titleLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let titleMedium = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .rounded)
    static let label = Font.system(size: 11, weight: .medium, design: .rounded).smallCaps()
}
