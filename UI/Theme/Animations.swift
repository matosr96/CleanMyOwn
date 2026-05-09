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
}
