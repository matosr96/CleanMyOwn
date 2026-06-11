//
//  HistorySheet.swift
//  CleanMyOwn
//
//  Historial de limpiezas: qué se borró, cuándo, cuánto y en qué modo.
//  Transparencia total — la respuesta permanente a "¿qué me hizo esta app?".
//

import SwiftUI

struct HistorySheet: View {
    @EnvironmentObject private var history: CleaningHistoryService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cabecera con el total acumulado
            HStack(alignment: .center, spacing: 16) {
                HeaderIconChip(icon: "clock.arrow.circlepath", tint: Theme.accent, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("HISTORIAL").font(.label).foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(history.totalFreedDiskBytes.formattedAsBytes)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.success)
                            .monospacedDigit()
                        Text("liberados en total")
                            .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if !history.records.isEmpty {
                    Button("Borrar historial") { history.clear() }
                        .buttonStyle(.plain)
                        .font(.bodySmall)
                        .foregroundStyle(Theme.textTertiary)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar historial")
            }
            .padding(24)

            Divider().overlay(Theme.onSurface(0.06))

            if history.records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Aún no hay limpiezas registradas")
                        .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                    Text("Cada operación quedará anotada aquí: qué se limpió, cuándo y cuánto espacio recuperaste.")
                        .font(.bodySmall).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(history.records) { record in
                            recordRow(record)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 520, height: 480)
        .background(Theme.background)
    }

    private func recordRow(_ record: CleaningRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: record.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.kind.displayName)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("· \(record.summary)")
                        .font(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(record.date, format: .dateTime.day().month().hour().minute())
                        .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                    if let modeName = record.mode.displayName {
                        Text("· \(modeName)")
                            .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer()
            if record.freedBytes > 0 {
                Text(record.freedBytes.formattedAsBytes)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(record.kind == .memory ? Theme.accent : Theme.success)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.onSurface(0.025)))
    }
}

#Preview {
    HistorySheet()
        .environmentObject(CleaningHistoryService())
}
