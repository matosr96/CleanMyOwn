//
//  Animations.swift
//  CleanMyOwn
//
//  Presets de animación reutilizables. Centralizar acá garantiza
//  consistencia: una pulsación, un hover y una transición de selección
//  comparten la misma curva.
//

import SwiftUI

enum Anim {
    /// Para hovers cortos (cambio de color, leve scale). Casi instantáneo.
    static let hover = Animation.easeOut(duration: 0.14)

    /// Spring rápido para press-down de botones, toggles, taps.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)

    /// Spring con un poquito de rebote para confirmar acciones (selección).
    static let bouncy = Animation.spring(response: 0.40, dampingFraction: 0.65)

    /// Spring suave y largo para cambios de layout (apertura de paneles).
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.88)

    /// Para crossfades entre módulos / vistas grandes.
    static let crossfade = Animation.easeInOut(duration: 0.22)

    /// Curva infinita "respirar". Usar con `repeatForever(autoreverses: true)`.
    static let breathe = Animation.easeInOut(duration: 1.6)

    /// Transición entre módulos: deslizamiento corto + fade con spring.
    static let modulePush = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

// MARK: - Transición direccional entre módulos

private struct SlideFade: ViewModifier {
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.offset(y: y).opacity(opacity)
    }
}

extension AnyTransition {
    /// El módulo entra deslizándose DESDE la dirección del movimiento en el
    /// menú (bajas en el sidebar → el contenido sube, y viceversa). Conecta
    /// físicamente la navegación con el contenido.
    static func moduleSlide(up: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SlideFade(y: up ? 28 : -28, opacity: 0),
                identity: SlideFade(y: 0, opacity: 1)
            ),
            removal: .modifier(
                active: SlideFade(y: up ? -14 : 14, opacity: 0),
                identity: SlideFade(y: 0, opacity: 1)
            )
        )
    }
}

// MARK: - Entrada en cascada de secciones

private struct CascadeIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.05)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

extension View {
    /// Las secciones de un módulo se componen en cascada al entrar
    /// (0, 1, 2…) en vez de aparecer todas de golpe.
    func cascadeIn(_ index: Int) -> some View {
        modifier(CascadeIn(index: index))
    }
}
