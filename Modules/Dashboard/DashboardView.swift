//
//  DashboardView.swift
//  CleanMyOwn
//
//  Pantalla principal: hero gigante con el espacio libre del disco como
//  protagonista, sub-rings de RAM y CPU, y stats de soporte abajo.
//  Apunta a sentirse como una "infografía viva" más que un dashboard plano.
//

import SwiftUI

struct DashboardView: View {
    /// Selección de módulo del ContentView — el Smart Scan navega a Limpieza.
    @Binding var selection: AppModule
    @StateObject private var systemInfo = SystemInfoService()
    @EnvironmentObject private var permissions: PermissionsMonitor
    @EnvironmentObject private var junk: JunkScanService
    @EnvironmentObject private var history: CleaningHistoryService
    @State private var showingHistory = false

    var body: some View {
        ZStack {
            // Mientras escanea, el módulo entero se convierte en UN objeto:
            // el orbe 3D con una línea de texto (concepto "Looking for junk").
            if junk.isScanning {
                scanHero
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header.cascadeIn(0)
                        smartScanCard.cascadeIn(1)
                        if !permissions.hasFullDiskAccess {
                            healthCard.cascadeIn(1)
                        }
                        storageCard.cascadeIn(2)
                        gaugesRow.cascadeIn(3)
                    }
                    .padding(32)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Anim.modulePush, value: junk.isScanning)
        .onAppear { systemInfo.startAutoRefresh() }
        .onDisappear { systemInfo.stopAutoRefresh() }
    }

    // MARK: - Orbe de escaneo (estado inmersivo)

    private var scanHero: some View {
        VStack(spacing: 40) {
            Spacer()

            ZStack {
                // Halo ambiental
                Circle()
                    .fill(Theme.success)
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .opacity(0.32)

                // Sombra de suelo — ancla el objeto al espacio
                Ellipse()
                    .fill(.black.opacity(0.35))
                    .frame(width: 230, height: 50)
                    .blur(radius: 18)
                    .offset(y: 160)

                // Disco 3D: gradiente radial descentrado (luz arriba-izquierda),
                // brillo especular y el glifo orbitando — profundidad sin Metal.
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let breathe = 1 + 0.022 * sin(t * 1.7)
                    let angle = (t.truncatingRemainder(dividingBy: 5) / 5) * 360

                    ZStack {
                        Circle()
                            .fill(RadialGradient(
                                colors: [
                                    Theme.success.blended(with: .white, ratio: 0.38),
                                    Theme.success,
                                    Theme.success.blended(with: .black, ratio: 0.38)
                                ],
                                center: UnitPoint(x: 0.35, y: 0.28),
                                startRadius: 10, endRadius: 175
                            ))
                            .frame(width: 270, height: 270)
                            .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))

                        // Especular
                        Ellipse()
                            .fill(LinearGradient(colors: [.white.opacity(0.50), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 170, height: 84)
                            .rotationEffect(.degrees(-18))
                            .offset(x: -36, y: -84)
                            .blur(radius: 5)

                        SweepGlyph()
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(angle))
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    }
                    .scaleEffect(breathe)
                }
                .shadow(color: Theme.success.opacity(0.45), radius: 50, y: 16)
            }

            VStack(spacing: 10) {
                Text("Buscando basura…")
                    .font(.displayMedium)
                    .foregroundStyle(Theme.textPrimary)
                AnimatedByteCounter(
                    bytes: junk.totalBytes,
                    font: .system(size: 32, weight: .bold, design: .rounded)
                )
                Text(junk.scanProgressLabel.isEmpty ? "Revisando tu Mac de punta a punta" : junk.scanProgressLabel)
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Smart Scan (hero)

    private var smartScanCard: some View {
        HStack(spacing: 34) {
            SmartScanButton(isScanning: junk.isScanning) {
                junk.startScan()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("SMART SCAN")
                    .font(.label).foregroundStyle(Theme.textTertiary).tracking(2)

                if junk.isScanning {
                    AnimatedByteCounter(bytes: junk.totalBytes)
                    Text(junk.scanProgressLabel.isEmpty ? "Inspeccionando tu Mac…" : junk.scanProgressLabel)
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                } else if !junk.results.isEmpty {
                    AnimatedByteCounter(bytes: junk.totalBytes)
                    Text("de basura en \(junk.results.filter { !$0.items.isEmpty }.count) categorías — \(junk.selectedBytes.formattedAsBytes) ya seleccionados de forma segura.")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        Button(action: { withAnimation(Anim.crossfade) { selection = .junkCleaner } }) {
                            HStack(spacing: 7) {
                                Text("Revisar y limpiar")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(PolishedPrimaryButtonStyle(horizontal: 18, vertical: 10))

                        Button(action: { junk.startScan() }) {
                            Image(systemName: "arrow.clockwise")
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Volver a escanear")
                    }
                    .padding(.top, 2)
                } else {
                    Text("Un escaneo, todo tu Mac")
                        .font(.titleLarge).foregroundStyle(Theme.textPrimary)
                    Text("Cachés, registros, papelera, restos de apps desinstaladas y archivos temporales del sistema — todo de un solo golpe. Nada se borra sin tu confirmación.")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .glassCard(cornerRadius: 24)
        .shadow(color: Theme.accent.opacity(0.16), radius: 24, y: 8)
    }

    // MARK: - Header (greeting hero)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TU MAC")
                    .font(.label).foregroundStyle(Theme.textTertiary)
                    .tracking(2)
                Text(greeting)
                    .font(.heroTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.75)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                Text(subgreeting)
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: { showingHistory = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    if history.totalFreedDiskBytes > 0 {
                        Text(history.totalFreedDiskBytes.formattedAsBytes)
                            .monospacedDigit()
                    }
                }
                .font(.bodyMedium.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Historial de limpiezas — total liberado")
            .accessibilityLabel("Historial de limpiezas")
        }
        .sheet(isPresented: $showingHistory) {
            HistorySheet()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Buenos días"
        case 12..<19: return "Buenas tardes"
        default:      return "Buenas noches"
        }
    }

    private var subgreeting: String {
        guard let s = systemInfo.snapshot else { return "Cargando información del sistema…" }
        return "\(s.osVersion)  ·  \(s.modelName)"
    }

    // MARK: - Almacenamiento (anillo fino + barra segmentada con la basura)

    private var storageCard: some View {
        let snap = systemInfo.snapshot
        let total = snap?.totalDiskBytes ?? 0
        let free = snap?.freeDiskBytes ?? 0
        let junkBytes = junk.isScanning ? 0 : junk.totalBytes
        let usedClean = max(total - free - junkBytes, 0)

        return HStack(spacing: 30) {
            ProgressRing(
                progress: snap?.diskUsageFraction ?? 0,
                label: "\(Int((snap?.diskUsageFraction ?? 0) * 100))%",
                sublabel: "ocupado",
                gradient: Theme.brandGradient,
                lineWidth: 9,
                size: 130,
                glowColor: Theme.accent,
                labelFont: .system(size: 26, weight: .bold, design: .rounded)
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("ALMACENAMIENTO")
                    .font(.label).foregroundStyle(Theme.textTertiary).tracking(2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(free.formattedAsBytes)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.success)
                        .contentTransition(.numericText())
                    Text("libres de \(total.formattedAsBytes)")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }

                segmentedBar(usedClean: usedClean, junkBytes: junkBytes, free: free, total: total)

                HStack(spacing: 16) {
                    legendDot(color: Theme.accent, label: "En uso", bytes: usedClean)
                    if junkBytes > 0 {
                        legendDot(color: Theme.warning, label: "Basura detectada", bytes: junkBytes)
                    }
                    legendDot(color: Color.white.opacity(0.25), label: "Libre", bytes: free)
                    if junkBytes == 0 && !junk.isScanning {
                        Text("· pasa el Smart Scan para ver cuánto es basura")
                            .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .glassCard(cornerRadius: 20)
    }

    /// Barra de un solo vistazo: en uso · basura detectada (Smart Scan) · libre.
    private func segmentedBar(usedClean: Int64, junkBytes: Int64, free: Int64, total: Int64) -> some View {
        GeometryReader { geo in
            let t = max(Double(total), 1)
            let w = geo.size.width
            HStack(spacing: 2) {
                if usedClean > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.brandGradient)
                        .frame(width: max(w * Double(usedClean) / t, 4))
                }
                if junkBytes > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Theme.warning, Theme.danger.opacity(0.8)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(w * Double(junkBytes) / t, 4))
                        .shadow(color: Theme.warning.opacity(0.55), radius: 5)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.07))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func legendDot(color: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.bodySmall).foregroundStyle(Theme.textSecondary)
            Text(bytes.formattedAsBytes).font(.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
    }

    // MARK: - Memoria y CPU (compactos, color por carga)

    private var gaugesRow: some View {
        let memFraction = systemInfo.snapshot?.memoryUsageFraction ?? 0
        let cpuFraction = (systemInfo.snapshot?.cpuUsagePercent ?? 0) / 100.0

        return HStack(spacing: 18) {
            gaugeCard(
                title: "MEMORIA",
                fraction: memFraction,
                tint: loadTint(memFraction, warnAt: 0.75, dangerAt: 0.92, cool: Theme.success),
                value: "\(Int64(systemInfo.snapshot?.usedMemoryBytes ?? 0).formattedAsBytes) de \(Int64(systemInfo.snapshot?.totalMemoryBytes ?? 0).formattedAsBytes)",
                caption: "presión de memoria"
            )
            gaugeCard(
                title: "CPU",
                fraction: cpuFraction,
                tint: loadTint(cpuFraction, warnAt: 0.55, dangerAt: 0.85,
                               cool: Color(red: 0.30, green: 0.85, blue: 0.95)),
                value: "\(Int(systemInfo.snapshot?.cpuUsagePercent ?? 0))% en uso",
                caption: "medido entre muestras"
            )
        }
    }

    /// Color con SEMÁNTICA: frío en carga normal, naranja al acercarse al
    /// límite, rojo sólo cuando de verdad hay presión.
    private func loadTint(_ fraction: Double, warnAt: Double, dangerAt: Double, cool: Color) -> Color {
        if fraction >= dangerAt { return Theme.danger }
        if fraction >= warnAt { return Theme.warning }
        return cool
    }

    private func gaugeCard(title: String, fraction: Double, tint: Color, value: String, caption: String) -> some View {
        HStack(spacing: 18) {
            ProgressRing(
                progress: fraction,
                label: "\(Int(fraction * 100))%",
                sublabel: "",
                gradient: LinearGradient(colors: [tint, tint.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 8,
                size: 88,
                glowColor: tint,
                labelFont: .system(size: 19, weight: .bold, design: .rounded)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.label).foregroundStyle(Theme.textTertiary).tracking(2)
                Text(value)
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption).font(.bodySmall).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.12), radius: 14, y: 5)
    }

    // MARK: - Health Card

    private var healthCard: some View {
        let fda = permissions.hasFullDiskAccess
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill((fda ? Theme.success : Theme.warning).opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: fda ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(fda ? Theme.success : Theme.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fda ? "Permisos al día" : "Permisos incompletos")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(fda
                     ? "Acceso completo al disco concedido. Puedes limpiar todo, incluidos containers de apps sandboxed."
                     : "Falta «Acceso completo al disco». Sin él, los datos huérfanos en ~/Library/Containers no se pueden borrar.")
                    .font(.bodySmall).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !fda {
                Button(action: { AdminSessionService.openFullDiskAccessSettings() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Conceder")
                    }
                }
                .buttonStyle(PolishedPrimaryButtonStyle(horizontal: 14, vertical: 9))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((fda ? Theme.success : Theme.warning).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((fda ? Theme.success : Theme.warning).opacity(0.24), lineWidth: 1)
        )
    }

}

#Preview {
    DashboardView(selection: .constant(.dashboard))
        .environmentObject(PermissionsMonitor.shared)
        .environmentObject(JunkScanService())
        .frame(width: 1100, height: 800)
}
