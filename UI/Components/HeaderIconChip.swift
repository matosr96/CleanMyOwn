//
//  HeaderIconChip.swift
//  CleanMyOwn
//
//  Chip de gradiente con el icono del módulo para las cabeceras — da a cada
//  pantalla identidad de color propia (mismo lenguaje que la sidebar).
//

import SwiftUI

struct HeaderIconChip: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint, tint.opacity(0.62)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: tint.opacity(0.45), radius: 12, y: 4)
    }
}

#Preview {
    HStack(spacing: 14) {
        HeaderIconChip(icon: "trash.fill", tint: Theme.success)
        HeaderIconChip(icon: "shippingbox.fill", tint: Theme.warning)
        HeaderIconChip(icon: "doc.zipper", tint: Color(red: 0.85, green: 0.50, blue: 1.0))
        HeaderIconChip(icon: "memorychip.fill", tint: Color(red: 0.30, green: 0.85, blue: 0.95))
        HeaderIconChip(icon: "power", tint: Theme.danger)
    }
    .padding()
    .background(Theme.background)
}
