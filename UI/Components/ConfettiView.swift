//
//  ConfettiView.swift
//  CleanMyOwn
//
//  Sistema de partículas de celebración. Cuando `trigger` cambia, lanza
//  un nuevo lote de partículas que caen con gravedad, rotan y se desvanecen.
//  Implementado con Canvas + TimelineView para animación fluida sin
//  golpear el view tree con cada frame.
//

import SwiftUI

struct ConfettiView: View {
    /// Cambia este valor (ej: con un counter) para disparar una nueva ráfaga.
    let trigger: Int
    /// Cantidad de partículas por ráfaga.
    var count: Int = 80
    /// Paleta de colores. Por defecto los acentos del tema.
    var colors: [Color] = [
        Theme.success,
        Theme.accent,
        Theme.warning,
        Color(red: 0.85, green: 0.50, blue: 1.0),
        Color(red: 0.30, green: 0.85, blue: 0.95)
    ]

    @State private var particles: [Particle] = []
    @State private var startedAt: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { context in
            Canvas { ctx, size in
                let elapsed = context.date.timeIntervalSince(startedAt)
                guard elapsed >= 0, elapsed < 4.0 else { return }
                for p in particles {
                    let pos = p.position(at: elapsed, in: size)
                    let alpha = p.alpha(at: elapsed)
                    guard alpha > 0.01 else { continue }
                    var ctx2 = ctx
                    ctx2.opacity = alpha
                    ctx2.translateBy(x: pos.x, y: pos.y)
                    ctx2.rotate(by: .degrees(p.rotation(at: elapsed)))
                    let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2,
                                      width: p.size.width, height: p.size.height)
                    let path = Path(roundedRect: rect, cornerRadius: 1)
                    ctx2.fill(path, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        startedAt = Date()
        particles = (0..<count).map { _ in
            Particle.random(colors: colors)
        }
    }

    // MARK: - Modelo de partícula

    private struct Particle {
        let originX: CGFloat              // 0..1 (porción del width)
        let originYBias: CGFloat          // 0..0.3 desde el top
        let velocityX: CGFloat            // -250..250 px/s
        let velocityY: CGFloat            // -800..-300 px/s (negativo: sube primero)
        let gravity: CGFloat = 1400       // px/s²
        let rotationStart: Double         // grados
        let rotationSpeed: Double         // grados/s
        let lifetime: Double              // 1.6..3.5 s
        let size: CGSize
        let color: Color

        static func random(colors: [Color]) -> Particle {
            Particle(
                originX: CGFloat.random(in: 0.3...0.7),
                originYBias: CGFloat.random(in: 0.0...0.15),
                velocityX: CGFloat.random(in: -260...260),
                velocityY: CGFloat.random(in: -780 ... -340),
                rotationStart: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -360...360),
                lifetime: Double.random(in: 2.0...3.4),
                size: CGSize(width: CGFloat.random(in: 6...11),
                             height: CGFloat.random(in: 4...8)),
                color: colors.randomElement() ?? Theme.accent
            )
        }

        func position(at t: TimeInterval, in size: CGSize) -> CGPoint {
            let x = originX * size.width + velocityX * CGFloat(t)
            // y = y0 + vy*t + 0.5*g*t²
            let y0 = originYBias * size.height
            let y = y0 + velocityY * CGFloat(t) + 0.5 * gravity * CGFloat(t * t)
            return CGPoint(x: x, y: y)
        }

        func rotation(at t: TimeInterval) -> Double {
            rotationStart + rotationSpeed * t
        }

        func alpha(at t: TimeInterval) -> Double {
            // Fade-out en el último 30% de vida
            guard t < lifetime else { return 0 }
            let fadeStart = lifetime * 0.7
            if t < fadeStart { return 1.0 }
            return max(0, 1 - (t - fadeStart) / (lifetime - fadeStart))
        }
    }
}
