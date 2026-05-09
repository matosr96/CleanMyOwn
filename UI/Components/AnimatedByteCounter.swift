//
//  AnimatedByteCounter.swift
//  CleanMyOwn
//
//  Texto que tweenea de un valor en bytes a otro con curva easeOutCubic.
//  Pensado para el "Liberaste 12,4 GB" del Hero moment después de una
//  limpieza — los bytes "suman" en pantalla en lugar de aparecer fríos.
//

import SwiftUI

struct AnimatedByteCounter: View {
    let bytes: Int64
    var duration: Double = 1.4
    var font: Font = .system(size: 56, weight: .bold, design: .rounded)
    var color: Color = Theme.success

    @State private var displayed: Double = 0
    @State private var animating = false

    var body: some View {
        Text(Int64(displayed).formattedAsBytes)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .onAppear { animateTo(Double(bytes)) }
            .onChange(of: bytes) { _, new in animateTo(Double(new)) }
    }

    private func animateTo(_ target: Double) {
        let start = displayed
        let started = Date()
        animating = true
        Task { @MainActor in
            while animating {
                let elapsed = Date().timeIntervalSince(started)
                let t = min(elapsed / duration, 1.0)
                // easeOutCubic: empieza rápido y desacelera
                let eased = 1 - pow(1 - t, 3)
                withAnimation(.linear(duration: 0.05)) {
                    displayed = start + (target - start) * eased
                }
                if t >= 1.0 { animating = false; break }
                try? await Task.sleep(nanoseconds: 30_000_000) // ~33fps suaviza CPU
            }
        }
    }
}
