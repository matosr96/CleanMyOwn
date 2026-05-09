//
//  SearchField.swift
//  CleanMyOwn
//
//  Campo de búsqueda con estilo moderno: glass background, icono de lupa,
//  altura cómoda y border iluminado al focus.
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Buscar…"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focused ? Theme.accent : Theme.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(focused ? Theme.accent.opacity(0.55) : Color.white.opacity(0.06),
                        lineWidth: 1)
        )
        .shadow(color: focused ? Theme.accent.opacity(0.18) : .clear, radius: 8, y: 2)
        .animation(Anim.hover, value: focused)
    }
}
