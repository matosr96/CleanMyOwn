//
//  MemoryFreerView.swift
//  CleanMyOwn
//
//  Presión de memoria en tiempo real. Un solo hero: anillo fino con color
//  semántico, barra apilada (Apps / Wired / Comprimida / Caché / Libre) con
//  leyenda, y el botón de liberar integrado — simple pero completo.
//

import SwiftUI

struct MemoryFreerView: View {
    @StateObject private var service = MemoryService()
    @EnvironmentObject private var admin: AdminSessionService
    @State private var showResult = false

    private let cyan = Color(red: 0.30, green: 0.85, blue: 0.95)
    private let purple = Color(red: 0.85, green: 0.50, blue: 1.0)

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let stats = service.stats {
                        heroCard(stats: stats)
                        infoNote
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

    /// Mismo esqueleto que el resto de módulos: chip + título a la izquierda,
    /// ACCIÓN PRIMARIA arriba a la derecha.
    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: 16) {
                HeaderIconChip(icon: "memorychip.fill", tint: cyan)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MEMORIA").font(.label).foregroundStyle(Theme.textTertiary)
                    Text("Liberar RAM").font(.displayMedium).foregroundStyle(Theme.textPrimary)
                    Text(admin.helperEnabled
                         ? "Ejecuta `purge` para liberar memoria inactiva y comprimida — sin contraseña, vía el asistente."
                         : "Ejecuta `purge` para liberar memoria inactiva y comprimida. La contraseña se pide una sola vez por sesión.")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            purgeControl
        }
    }

    // MARK: - Hero

    private func heroCard(stats: MemoryStats) -> some View {
        let tint = pressureTint(stats.pressureFraction)
        return HStack(spacing: 30) {
            ProgressRing(
                progress: stats.pressureFraction,
                label: "\(Int(stats.pressureFraction * 100))%",
                sublabel: "presión",
                gradient: LinearGradient(colors: [tint, tint.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 9,
                size: 130,
                glowColor: tint,
                labelFont: .system(size: 26, weight: .bold, design: .rounded)
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("MEMORIA FÍSICA")
                    .font(.label).foregroundStyle(Theme.textTertiary).tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Int64(stats.usedBytes).formattedAsBytes)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text("en uso de \(Int64(stats.totalBytes).formattedAsBytes)")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }

                stackedBar(stats: stats)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) {
                        legendDot(color: Theme.accent, label: "Apps", bytes: stats.appBytes)
                        legendDot(color: cyan, label: "Wired", bytes: stats.wiredBytes)
                        legendDot(color: Theme.warning, label: "Comprimida", bytes: stats.compressedBytes)
                    }
                    HStack(spacing: 18) {
                        legendDot(color: purple, label: "Caché de archivos", bytes: stats.cachedBytes)
                        legendDot(color: Color.white.opacity(0.25), label: "Libre", bytes: stats.freeBytes)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.14), radius: 16, y: 6)
    }

    @ViewBuilder
    private var purgeControl: some View {
        if service.isPurging {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Liberando…").font(.titleMedium)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
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
                horizontal: 20, vertical: 12
            ))
        }
    }

    /// Una sola barra apilada en vez de cinco mini-gráficos: se lee de un
    /// vistazo qué se lleva la RAM.
    private func stackedBar(stats: MemoryStats) -> some View {
        GeometryReader { geo in
            let total = max(Double(stats.totalBytes), 1)
            let w = geo.size.width
            HStack(spacing: 2) {
                segment(width: w * Double(stats.appBytes) / total, color: Theme.accent)
                segment(width: w * Double(stats.wiredBytes) / total, color: cyan)
                segment(width: w * Double(stats.compressedBytes) / total, color: Theme.warning)
                segment(width: w * Double(stats.cachedBytes) / total, color: purple.opacity(0.75))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.07))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.6), value: stats.pressureFraction)
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: max(width, 3))
    }

    private func legendDot(color: Color, label: String, bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.bodySmall).foregroundStyle(Theme.textSecondary)
            Text(Int64(bytes).formattedAsBytes)
                .font(.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Verde en uso normal, naranja con presión, rojo cuando aprieta de verdad.
    private func pressureTint(_ fraction: Double) -> Color {
        if fraction >= 0.92 { return Theme.danger }
        if fraction >= 0.75 { return Theme.warning }
        return Theme.success
    }

    /// Expectativas honestas: purge es puntual, no rutina.
    private var infoNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.textTertiary)
                .font(.system(size: 13))
            Text("purge descarta páginas inactivas y caché de archivos. macOS ya gestiona la RAM por su cuenta — úsalo de forma puntual (antes de una app pesada o un benchmark), no como rutina: las apps recargarán su caché y eso también cuesta.")
                .font(.bodySmall).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).stroke(Color.white.opacity(0.05), lineWidth: 1))
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
        await service.purge(adminSession: admin)
        if service.lastError == nil {
            showResult = true
        }
    }
}

#Preview {
    MemoryFreerView()
        .environmentObject(AdminSessionService())
        .frame(width: 1000, height: 700)
}
