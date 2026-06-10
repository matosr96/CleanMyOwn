//
//  ProgressRing.swift
//  CleanMyOwn
//
//  Anillo circular animado para mostrar uso de disco/RAM/CPU.
//

import SwiftUI

struct ProgressRing: View {
    /// Valor entre 0.0 y 1.0
    let progress: Double
    
    /// Texto principal en el centro (ej: "47%")
    let label: String
    
    /// Texto secundario debajo del label (ej: "120 GB libres")
    let sublabel: String
    
    /// Gradiente del anillo
    let gradient: LinearGradient
    
    var lineWidth: CGFloat = 14
    var size: CGFloat = 160
    /// Color del glow detrás del anillo (suele coincidir con el gradient).
    var glowColor: Color = Theme.accent
    /// Fuente del label central — pásala proporcional al `size` (el default
    /// de 32pt sólo funciona bien en anillos grandes).
    var labelFont: Font = .displayMedium

    @State private var animatedProgress: Double = 0
    @State private var breath: CGFloat = 0.7

    var body: some View {
        ZStack {
            // Glow exterior — respira suavemente, intensifica con progreso alto
            Circle()
                .stroke(glowColor, lineWidth: lineWidth)
                .blur(radius: 24)
                .opacity(0.18 + Double(breath) * 0.12 + min(animatedProgress * 0.25, 0.25))

            // Track de fondo
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            // Progreso
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glowColor.opacity(0.4), radius: 6)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: animatedProgress)

            // Textos centrales
            VStack(spacing: 2) {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if !sublabel.isEmpty {
                    Text(sublabel)
                        .font(.bodySmall)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            animatedProgress = progress
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breath = 1.0
            }
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
    }
}

#Preview {
    ProgressRing(
        progress: 0.47,
        label: "47%",
        sublabel: "120 GB libres",
        gradient: Theme.brandGradient
    )
    .padding(40)
    .background(Theme.background)
}
