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
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Track de fondo
            Circle()
                .stroke(
                    Color.white.opacity(0.08),
                    lineWidth: lineWidth
                )
            
            // Progreso
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    gradient,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: animatedProgress)
            
            // Textos centrales
            VStack(spacing: 4) {
                Text(label)
                    .font(.displayMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text(sublabel)
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            animatedProgress = progress
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
