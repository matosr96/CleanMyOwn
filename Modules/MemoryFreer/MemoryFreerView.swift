//
//  MemoryFreerView.swift
//  CleanMyOwn
//
//  Visualización en tiempo real del uso de memoria y botón para liberar
//  memoria inactiva/comprimida vía `purge` (requiere autorización admin).
//

import SwiftUI

struct MemoryFreerView: View {
    @StateObject private var service = MemoryService()
    @State private var showResult = false

    var body: some View {
        ZStack {
            AnimatedBackground(intensity: 0.32)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let stats = service.stats {
                        HStack(alignment: .top, spacing: 24) {
                            ringPanel(stats: stats)
                            breakdownPanel(stats: stats).frame(maxWidth: .infinity)
                        }
                        actionPanel(stats: stats)
                        if let err = service.lastError { errorBanner(err) }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { service.startAutoRefresh() }
        .onDisappear { service.stopAutoRefresh() }
        .alert("Memoria liberada", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Se liberaron \(service.lastFreedBytes.formattedAsBytes) de memoria comprimida/inactiva.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMORIA").font(.label).foregroundStyle(Theme.textTertiary)
            Text("Liberar RAM").font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("Ejecuta `purge` para liberar memoria inactiva y comprimida. Requiere autorización del administrador.")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
        }
    }

    private func ringPanel(stats: MemoryStats) -> some View {
        VStack(spacing: 14) {
            ProgressRing(
                progress: stats.pressureFraction,
                label: "\(Int(stats.pressureFraction * 100))%",
                sublabel: "en uso",
                gradient: Theme.healthGradient,
                size: 200
            )
            Text("\(Int64(stats.pressureBytes).formattedAsBytes) de \(Int64(stats.totalBytes).formattedAsBytes)")
                .font(.titleMedium).foregroundStyle(Theme.textPrimary)
        }
        .padding(28)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge)
            .stroke(Theme.success.opacity(0.22), lineWidth: 1))
        .shadow(color: Theme.success.opacity(0.18), radius: 18, y: 6)
    }

    private func breakdownPanel(stats: MemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribución").font(.titleMedium).foregroundStyle(Theme.textPrimary)
            breakdownRow(label: "Apps", bytes: stats.appBytes, total: stats.totalBytes, tint: Theme.accent)
            breakdownRow(label: "Wired", bytes: stats.wiredBytes, total: stats.totalBytes, tint: Color(red: 0.30, green: 0.85, blue: 0.95))
            breakdownRow(label: "Comprimida", bytes: stats.compressedBytes, total: stats.totalBytes, tint: Theme.warning)
            breakdownRow(label: "Caché de archivos", bytes: stats.cachedBytes, total: stats.totalBytes, tint: Color(red: 0.85, green: 0.50, blue: 1.0))
            breakdownRow(label: "Libre", bytes: stats.freeBytes, total: stats.totalBytes, tint: Theme.success)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge)
            .stroke(Color(red: 0.30, green: 0.85, blue: 0.95).opacity(0.18), lineWidth: 1))
    }

    private func breakdownRow(label: String, bytes: UInt64, total: UInt64, tint: Color) -> some View {
        let frac = total > 0 ? Double(bytes) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Int64(bytes).formattedAsBytes).font(.bodyMedium).foregroundStyle(Theme.textPrimary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.85))
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 6)
        }
    }

    private func actionPanel(stats: MemoryStats) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memoria comprimida actual").font(.label).foregroundStyle(Theme.textTertiary)
                Text(Int64(stats.compressedBytes).formattedAsBytes)
                    .font(.titleLarge).foregroundStyle(Theme.warning)
            }
            Spacer()
            if service.isPurging {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Liberando…").font(.titleMedium)
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.card))
                .foregroundStyle(Theme.textPrimary)
            } else {
                Button(action: { Task { await runPurge() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Liberar memoria")
                    }
                }
                .buttonStyle(PolishedPrimaryButtonStyle(
                    fill: AnyShapeStyle(Theme.healthGradient),
                    glow: Theme.success,
                    horizontal: 24, vertical: 13
                ))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(msg).font(.bodySmall).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.warning.opacity(0.1)))
    }

    private func runPurge() async {
        await service.purge()
        if service.lastError == nil {
            showResult = true
        }
    }
}

#Preview {
    MemoryFreerView().frame(width: 1000, height: 700)
}
