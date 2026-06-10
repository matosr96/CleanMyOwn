//
//  AnimatedBackground.swift
//  CleanMyOwn
//
//  Background con "blobs" de color que flotan despacio y se mezclan con
//  el fondo oscuro. Hace que la app se sienta viva incluso sin
//  interacción. Cada blob es un círculo grande con blur enorme y baja
//  opacidad, animado con TimelineView para no acoplar el tree de SwiftUI
//  a cada frame.
//

import SwiftUI

struct AnimatedBackground: View {
    /// Colores de los blobs. Por defecto los acentos del tema.
    var colors: [Color] = [
        Color(red: 0.45, green: 0.40, blue: 1.00),     // violeta
        Color(red: 0.30, green: 0.65, blue: 1.00),     // azul
        Color(red: 0.20, green: 0.85, blue: 0.55),     // verde
        Color(red: 1.00, green: 0.55, blue: 0.40),     // naranja
        Color(red: 0.85, green: 0.50, blue: 1.00)      // magenta
    ]
    /// Intensidad: 0.0 invisible, 1.0 muy vibrante.
    var intensity: Double = 0.85
    /// Tinte ambiental: el color del módulo activo inunda el lienzo. La
    /// transición entre tintes se interpola DENTRO del Canvas (un Canvas no
    /// es animable desde fuera) durante ~0.9 s.
    var tint: Color? = nil

    @State private var fromTint: Color? = nil
    @State private var toTint: Color? = nil
    @State private var tintChangedAt: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { context in
            Canvas { ctx, size in
                let now = context.date
                let t = now.timeIntervalSinceReferenceDate
                ctx.addFilter(.blur(radius: 90))
                ctx.opacity = intensity

                // Progreso del cambio de tinte con easing suave
                let raw = min(max(now.timeIntervalSince(tintChangedAt) / 0.9, 0), 1)
                let progress = raw * raw * (3 - 2 * raw)   // smoothstep
                let ambient = Color.lerp(fromTint, toTint, progress)

                let blobs = layout(at: t, in: size)
                for blob in blobs {
                    let rect = CGRect(
                        x: blob.center.x - blob.radius,
                        y: blob.center.y - blob.radius,
                        width: blob.radius * 2,
                        height: blob.radius * 2
                    )
                    let color = ambient.map { blob.color.blended(with: $0, ratio: 0.55) } ?? blob.color
                    ctx.fill(Circle().path(in: rect), with: .color(color))
                }
            }
            .background(Theme.background)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            toTint = tint
        }
        .onChange(of: tint) { old, new in
            // Congelar el tinte visible actual como origen de la interpolación
            let raw = min(max(Date().timeIntervalSince(tintChangedAt) / 0.9, 0), 1)
            let progress = raw * raw * (3 - 2 * raw)
            fromTint = Color.lerp(fromTint, toTint, progress)
            toTint = new
            tintChangedAt = Date()
        }
    }

    private func layout(at t: TimeInterval, in size: CGSize) -> [Blob] {
        let w = size.width
        let h = size.height
        // Cinco blobs con trayectorias circulares lentas y desfases distintos.
        let speeds: [Double] = [0.040, 0.055, 0.030, 0.048, 0.038]
        let phases: [Double] = [0, 1.3, 2.7, 4.1, 5.5]
        let amplitudes: [(CGFloat, CGFloat)] = [
            (w * 0.30, h * 0.25),
            (w * 0.35, h * 0.30),
            (w * 0.25, h * 0.35),
            (w * 0.40, h * 0.20),
            (w * 0.32, h * 0.28)
        ]
        let radii: [CGFloat] = [w * 0.32, w * 0.28, w * 0.30, w * 0.26, w * 0.34]

        return (0..<5).map { i in
            let angle = t * speeds[i] + phases[i]
            let cx = w * 0.5 + cos(angle) * amplitudes[i].0
            let cy = h * 0.5 + sin(angle * 1.3) * amplitudes[i].1
            return Blob(
                center: CGPoint(x: cx, y: cy),
                radius: radii[i],
                color: colors[i % colors.count]
            )
        }
    }

    private struct Blob {
        let center: CGPoint
        let radius: CGFloat
        let color: Color
    }
}

// MARK: - Mezcla de colores (Color.mix llega en macOS 15; esto corre en 14)

extension Color {
    /// Mezcla sRGB componente a componente.
    func blended(with other: Color, ratio: CGFloat) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let inv = 1 - ratio
        return Color(red: a.redComponent * inv + b.redComponent * ratio,
                     green: a.greenComponent * inv + b.greenComponent * ratio,
                     blue: a.blueComponent * inv + b.blueComponent * ratio)
    }

    /// Interpola entre dos tintes opcionales (nil = sin tinte).
    static func lerp(_ from: Color?, _ to: Color?, _ progress: Double) -> Color? {
        switch (from, to) {
        case (nil, nil): return nil
        case (nil, let t?): return progress >= 1 ? t : t.opacity(progress)
        case (let f?, nil): return progress >= 1 ? nil : f.opacity(1 - progress)
        case (let f?, let t?): return f.blended(with: t, ratio: progress)
        }
    }
}
