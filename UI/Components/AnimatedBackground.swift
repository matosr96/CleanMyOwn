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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                ctx.addFilter(.blur(radius: 90))
                ctx.opacity = intensity

                let blobs = layout(at: t, in: size)
                for blob in blobs {
                    let rect = CGRect(
                        x: blob.center.x - blob.radius,
                        y: blob.center.y - blob.radius,
                        width: blob.radius * 2,
                        height: blob.radius * 2
                    )
                    ctx.fill(Circle().path(in: rect), with: .color(blob.color))
                }
            }
            .background(Theme.background)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
