//
//  BrandMark.swift
//  CleanMyOwn
//
//  La marca de la app: un "swoosh" orbital de pulido con punto — sugiere
//  barrido, limpieza y movimiento. Deliberadamente NO es una estrella ni
//  sparkles (el cliché visual de los productos de IA).
//
//  La misma geometría se replica en tools/make-icon.swift para el icono
//  de la app: si cambias los ángulos aquí, cámbialos allí.
//

import SwiftUI

/// Glifo del swoosh: arco principal + eco interior + punto cometa.
/// Dibuja en blanco (configurable) sobre cualquier fondo.
struct SweepGlyph: View {
    var tint: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2

            // Arco principal — barrido de ~250° con puntas redondeadas
            var sweep = Path()
            sweep.addArc(center: c, radius: r * 0.80,
                         startAngle: .degrees(-30), endAngle: .degrees(195),
                         clockwise: false)
            ctx.stroke(sweep, with: .color(tint),
                       style: StrokeStyle(lineWidth: r * 0.30, lineCap: .round))

            // Eco interior — estela del barrido
            var echo = Path()
            echo.addArc(center: c, radius: r * 0.38,
                        startAngle: .degrees(115), endAngle: .degrees(215),
                        clockwise: false)
            ctx.stroke(echo, with: .color(tint.opacity(0.55)),
                       style: StrokeStyle(lineWidth: r * 0.18, lineCap: .round))

            // Punto cometa en el hueco del arco (arriba-derecha)
            let angle = Angle.degrees(-62).radians
            let dot = CGPoint(x: c.x + cos(angle) * r * 0.80,
                              y: c.y + sin(angle) * r * 0.80)
            let dotR = r * 0.17
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - dotR, y: dot.y - dotR,
                                            width: dotR * 2, height: dotR * 2)),
                     with: .color(tint))
        }
    }
}

/// Marca completa: squircle con gradiente de marca + SweepGlyph.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.42, blue: 1.00),
                        Color(red: 0.30, green: 0.62, blue: 1.00),
                        Color(red: 0.66, green: 0.40, blue: 0.98)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            SweepGlyph()
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 24) {
        BrandMark(size: 92)
        BrandMark(size: 56)
        BrandMark(size: 34)
        SweepGlyph(tint: Theme.accent).frame(width: 44, height: 44)
    }
    .padding(40)
    .background(Theme.background)
}
