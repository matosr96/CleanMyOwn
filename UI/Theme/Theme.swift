//
//  Theme.swift
//  CleanMyOwn
//
//  Paleta de colores y gradientes inspirada en apps modernas
//  de limpieza/optimización (CleanMyMac, Sensei, etc.)
//

import SwiftUI

enum Theme {
    // MARK: - Colores base
    
    /// Fondo principal de la app (gris muy oscuro, casi negro azulado)
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    
    /// Fondo de la sidebar (un toque más claro)
    static let sidebar = Color(red: 0.10, green: 0.11, blue: 0.14)
    
    /// Fondo de cards y paneles
    static let card = Color(red: 0.13, green: 0.14, blue: 0.18)
    
    /// Fondo de cards al hacer hover
    static let cardHover = Color(red: 0.16, green: 0.17, blue: 0.22)
    
    /// Texto principal
    static let textPrimary = Color.white
    
    /// Texto secundario (subido para legibilidad sobre superficies de cristal)
    static let textSecondary = Color(white: 0.74)

    /// Texto terciario / labels (ídem)
    static let textTertiary = Color(white: 0.56)
    
    // MARK: - Acentos
    
    /// Azul/morado de marca (botones primarios, items activos)
    static let accent = Color(red: 0.40, green: 0.55, blue: 1.0)
    
    /// Verde de éxito (espacio liberado, todo OK)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    
    /// Naranja de advertencia
    static let warning = Color(red: 1.0, green: 0.65, blue: 0.20)
    
    /// Rojo de error/peligro
    static let danger = Color(red: 1.0, green: 0.40, blue: 0.45)
    
    // MARK: - Gradientes (la firma visual)
    
    /// Gradiente de marca para el botón "Scan" gigante
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.45, green: 0.40, blue: 1.0),
            Color(red: 0.30, green: 0.65, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Gradiente verde (espacio limpio, salud)
    static let healthGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.85, blue: 0.55),
            Color(red: 0.10, green: 0.65, blue: 0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Gradiente sutil para fondos de cards destacados
    static let cardGradient = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.17, blue: 0.22),
            Color(red: 0.13, green: 0.14, blue: 0.18)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // MARK: - Sombras
    
    static let shadowColor = Color.black.opacity(0.35)
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
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
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
