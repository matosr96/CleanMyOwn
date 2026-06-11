//
//  MenuBarPanel.swift
//  CleanMyOwn
//
//  El companion de la barra de menús: estado del Mac de un vistazo y las
//  dos acciones de cada día (liberar RAM, escanear) sin abrir la ventana.
//  Esta presencia diaria es la diferencia entre una app que se usa y una
//  que se olvida.
//

import SwiftUI

/// Icono template del menubar: el glifo de marca renderizado una vez.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let renderer = ImageRenderer(content: SweepGlyph(tint: .black).frame(width: 17, height: 17))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }()
}

struct MenuBarPanel: View {
    @EnvironmentObject private var admin: AdminSessionService
    @EnvironmentObject private var junk: JunkScanService
    @EnvironmentObject private var history: CleaningHistoryService
    @EnvironmentObject private var engagement: EngagementService
    @StateObject private var systemInfo = SystemInfoService()
    @StateObject private var memory = MemoryService()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Marca
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("CleanMyOwn")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Salir de CleanMyOwn")
                .accessibilityLabel("Salir de CleanMyOwn")
            }

            // Stats de un vistazo
            HStack(spacing: 8) {
                stat(label: "RAM",
                     value: "\(Int((systemInfo.snapshot?.memoryUsageFraction ?? 0) * 100))%",
                     tint: Theme.success)
                stat(label: "CPU",
                     value: "\(Int(systemInfo.snapshot?.cpuUsagePercent ?? 0))%",
                     tint: Color(red: 0.30, green: 0.85, blue: 0.95))
                stat(label: "LIBRE",
                     value: (systemInfo.snapshot?.freeDiskBytes ?? 0).formattedAsBytes,
                     tint: Theme.accent)
            }

            // Basura pendiente, si el último escaneo encontró algo
            if junk.totalBytes > 0 && !junk.isScanning {
                Button(action: openApp) {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.warning).frame(width: 7, height: 7)
                        Text("\(junk.totalBytes.formattedAsBytes) de basura por limpiar")
                            .font(.bodySmall).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warning.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            // Acciones rápidas
            VStack(spacing: 6) {
                actionRow(
                    icon: "wand.and.stars",
                    title: memory.isPurging ? "Liberando memoria…" : "Liberar memoria",
                    running: memory.isPurging
                ) {
                    Task {
                        await memory.purge(adminSession: admin)
                        if memory.lastError == nil {
                            history.record(kind: .memory, freedBytes: memory.lastFreedBytes,
                                           itemCount: 0, mode: .none, summary: "RAM liberada (menubar)")
                        }
                    }
                }
                actionRow(
                    icon: "magnifyingglass",
                    title: junk.isScanning ? "Escaneando…" : "Escanear ahora",
                    running: junk.isScanning
                ) {
                    junk.startScan()
                    openApp()
                }
                actionRow(icon: "macwindow", title: "Abrir CleanMyOwn", running: false) {
                    openApp()
                }
            }

            Divider().overlay(Theme.onSurface(0.08))

            // Avisos inteligentes (opt-in)
            Toggle(isOn: $engagement.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Avisos inteligentes")
                        .font(.bodySmall.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Papelera muy llena o semanas sin escanear")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(16)
        .frame(width: 280)
        .background(Theme.background)
        .onAppear { systemInfo.startAutoRefresh(interval: 3) }
        .onDisappear { systemInfo.stopAutoRefresh() }
    }

    private func openApp() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.10)))
    }

    private func actionRow(icon: String, title: String, running: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if running {
                    ProgressView().controlSize(.mini)
                        .frame(width: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 14)
                }
                Text(title).font(.bodySmall).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.onSurface(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(running)
        .accessibilityLabel(title)
    }
}
