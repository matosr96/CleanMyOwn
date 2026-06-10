//
//  SmartScanButton.swift
//  CleanMyOwn
//
//  El botón circular gigante del Dashboard — la pieza de identidad de las
//  apps de limpieza. Anillo de gradiente angular que gira mientras escanea
//  (animado vía TimelineView: sin repeatForever que cancelar), halo que
//  respira y un interior tipo card.
//

import SwiftUI

struct SmartScanButton: View {
    let isScanning: Bool
    let action: () -> Void

    var size: CGFloat = 190

    @State private var hovering = false

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.45, green: 0.40, blue: 1.0),
                Color(red: 0.30, green: 0.65, blue: 1.0),
                Color(red: 0.85, green: 0.50, blue: 1.0),
                Color(red: 0.45, green: 0.40, blue: 1.0)
            ],
            center: .center
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Halo exterior
                Circle()
                    .fill(Theme.accent)
                    .frame(width: size * 0.92, height: size * 0.92)
                    .blur(radius: 40)
                    .opacity(isScanning ? 0.55 : (hovering ? 0.45 : 0.28))

                // Anillo de gradiente (gira mientras escanea)
                ring
                    .frame(width: size, height: size)

                // Interior
                Circle()
                    .fill(Theme.cardGradient)
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                    .frame(width: size - 30, height: size - 30)

                VStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.21, weight: .bold))
                        .foregroundStyle(Theme.brandGradient)
                        .symbolEffect(.pulse, isActive: isScanning)
                    Text(isScanning ? "Escaneando…" : "Escanear")
                        .font(.titleMedium)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: size + 16, height: size + 16)
            .scaleEffect(hovering && !isScanning ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Anim.hover, value: hovering)
        .disabled(isScanning)
    }

    @ViewBuilder
    private var ring: some View {
        if isScanning {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: 1.8) / 1.8) * 360
                Circle()
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
        } else {
            Circle()
                .stroke(ringGradient, lineWidth: 11)
        }
    }
}

#Preview {
    HStack(spacing: 40) {
        SmartScanButton(isScanning: false, action: {})
        SmartScanButton(isScanning: true, action: {})
    }
    .padding(60)
    .background(Theme.background)
}
