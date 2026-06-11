//
//  Shimmer.swift
//  CleanMyOwn
//
//  Modificador para skeletons de loading. Aplica un brillo que recorre
//  el contenido de izquierda a derecha en loop mientras `active` sea true.
//

import SwiftUI

struct Shimmer: ViewModifier {
    var active: Bool = true
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if active {
                        LinearGradient(
                            stops: [
                                .init(color: Theme.onSurface(0), location: 0),
                                .init(color: Theme.onSurface(0.20), location: 0.45),
                                .init(color: Theme.onSurface(0.45), location: 0.5),
                                .init(color: Theme.onSurface(0.20), location: 0.55),
                                .init(color: Theme.onSurface(0), location: 1)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .blendMode(.plusLighter)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: phase * geo.size.width * 1.6)
                        .mask(content)
                    }
                }
            )
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Aplica un shimmer en loop. Útil para skeletons de loading.
    func shimmering(active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

/// Fila esqueleto reutilizable que imita una row de categoría con icono,
/// dos líneas de texto y un valor. Se renderiza con shimmer.
struct SkeletonCategoryRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.onSurface(0.10)).frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 8).fill(Theme.onSurface(0.10)).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.onSurface(0.10)).frame(width: 160, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Theme.onSurface(0.06)).frame(width: 240, height: 9)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(Theme.onSurface(0.10)).frame(width: 70, height: 12)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).stroke(Theme.onSurface(0.04), lineWidth: 1))
        .shimmering()
    }
}
