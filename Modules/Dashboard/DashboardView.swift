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
    @StateObject private var systemInfo = SystemInfoService()
    @EnvironmentObject private var permissions: PermissionsMonitor

    var body: some View {
        ZStack {
            AnimatedBackground(intensity: 0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    healthCard
                    heroDisk
                    secondaryRings
                    statsGrid
                }
                .padding(36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { systemInfo.startAutoRefresh() }
        .onDisappear { systemInfo.stopAutoRefresh() }
    }

    // MARK: - Header (greeting hero)

    private var header: some View {
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

    // MARK: - Hero del disco

    private var heroDisk: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 640
            let ringSize: CGFloat = isWide ? 240 : 200

            HStack(alignment: .center, spacing: isWide ? 32 : 22) {
                // Anillo gigante
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: ringSize + 30, height: ringSize + 30)
                        .blur(radius: 60)
                        .opacity(0.30)
                    ProgressRing(
                        progress: systemInfo.snapshot?.diskUsageFraction ?? 0,
                        label: "\(Int((systemInfo.snapshot?.diskUsageFraction ?? 0) * 100))%",
                        sublabel: "ocupado",
                        gradient: Theme.brandGradient,
                        lineWidth: 20,
                        size: ringSize,
                        glowColor: Theme.accent
                    )
                }
                .frame(width: ringSize + 30, height: ringSize + 30)

                // Texto al lado
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALMACENAMIENTO")
                        .font(.label).foregroundStyle(Theme.textTertiary).tracking(2)
                    Text(Int64(systemInfo.snapshot?.freeDiskBytes ?? 0).formattedAsBytes)
                        .font(.heroNumber)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.success, Color(red: 0.30, green: 0.85, blue: 0.95)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .contentTransition(.numericText())
                    Text("libres de \(Int64(systemInfo.snapshot?.totalDiskBytes ?? 0).formattedAsBytes)")
                        .font(.titleMedium).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // Barra horizontal con progreso de disco
                    GeometryReader { barGeo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule()
                                .fill(Theme.brandGradient)
                                .frame(width: barGeo.size.width * CGFloat(systemInfo.snapshot?.diskUsageFraction ?? 0))
                                .shadow(color: Theme.accent.opacity(0.6), radius: 8)
                        }
                    }
                    .frame(height: 10)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(isWide ? 28 : 22)
            .frame(width: geo.size.width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.accent.opacity(0.30), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 25, y: 10)
        }
        .frame(height: 290)
    }

    // MARK: - Anillos secundarios (RAM y CPU)

    private var secondaryRings: some View {
        HStack(spacing: 18) {
            ringCard(
                title: "MEMORIA",
                tint: Theme.success,
                ring: ProgressRing(
                    progress: systemInfo.snapshot?.memoryUsageFraction ?? 0,
                    label: "\(Int((systemInfo.snapshot?.memoryUsageFraction ?? 0) * 100))%",
                    sublabel: ramSublabel,
                    gradient: Theme.healthGradient,
                    glowColor: Theme.success
                )
            )
            ringCard(
                title: "CPU",
                tint: Color(red: 0.30, green: 0.85, blue: 0.95),
                ring: ProgressRing(
                    progress: (systemInfo.snapshot?.cpuUsagePercent ?? 0) / 100.0,
                    label: "\(Int(systemInfo.snapshot?.cpuUsagePercent ?? 0))%",
                    sublabel: "uso actual",
                    gradient: LinearGradient(
                        colors: [Theme.warning, Theme.danger],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    glowColor: Theme.warning
                )
            )
        }
    }

    private func ringCard<R: View>(title: String, tint: Color, ring: R) -> some View {
        VStack(spacing: 14) {
            Text(title).font(.label).foregroundStyle(Theme.textTertiary).tracking(2)
            ring
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.18), radius: 18, y: 6)
    }

    private var ramSublabel: String {
        guard let s = systemInfo.snapshot else { return "—" }
        let used = Int64(s.usedMemoryBytes).formattedAsBytes
        let total = Int64(s.totalMemoryBytes).formattedAsBytes
        return "\(used) / \(total)"
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

    // MARK: - Grid de stats secundarios

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resumen rápido")
                .font(.titleMedium)
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                StatCard(
                    icon: "internaldrive.fill",
                    title: "DISCO TOTAL",
                    value: systemInfo.snapshot?.totalDiskBytes.formattedAsBytes ?? "—",
                    subtitle: "capacidad del volumen",
                    accentColor: Theme.accent
                )
                StatCard(
                    icon: "tray.full.fill",
                    title: "ESPACIO USADO",
                    value: systemInfo.snapshot?.usedDiskBytes.formattedAsBytes ?? "—",
                    subtitle: "incluye cachés y temporales",
                    accentColor: Theme.warning
                )
                StatCard(
                    icon: "memorychip.fill",
                    title: "RAM TOTAL",
                    value: Int64(systemInfo.snapshot?.totalMemoryBytes ?? 0).formattedAsBytes,
                    subtitle: "memoria física instalada",
                    accentColor: Theme.success
                )
                StatCard(
                    icon: "cpu",
                    title: "PROCESADOR",
                    value: "\(Int(systemInfo.snapshot?.cpuUsagePercent ?? 0))% activo",
                    subtitle: "promedio del sistema",
                    accentColor: Color(red: 0.85, green: 0.50, blue: 1.0)
                )
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(PermissionsMonitor.shared)
        .frame(width: 1100, height: 800)
}
