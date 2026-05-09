//
//  DashboardView.swift
//  CleanMyOwn
//
//  Pantalla principal: muestra el estado del sistema.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var systemInfo = SystemInfoService()
    @EnvironmentObject private var permissions: PermissionsMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                healthCard
                ringsSection
                statsGrid
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { systemInfo.startAutoRefresh() }
        .onDisappear { systemInfo.stopAutoRefresh() }
    }

    // MARK: - Health Card

    private var healthCard: some View {
        let fda = permissions.hasFullDiskAccess
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill((fda ? Theme.success : Theme.warning).opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: fda ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(fda ? Theme.success : Theme.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fda ? "Permisos al día" : "Permisos incompletos")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                if fda {
                    Text("Acceso completo al disco concedido. Puedes limpiar todo, incluidos containers de apps sandboxed.")
                        .font(.bodySmall).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Falta «Acceso completo al disco». Sin él, los datos huérfanos en ~/Library/Containers no se pueden borrar.")
                        .font(.bodySmall).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if !fda {
                Button(action: { AdminSessionService.openFullDiskAccessSettings() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Conceder").font(.bodyMedium.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.brandGradient))
                    .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill((fda ? Theme.success : Theme.warning).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .stroke((fda ? Theme.success : Theme.warning).opacity(0.20), lineWidth: 1)
        )
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu Mac")
                .font(.label)
                .foregroundStyle(Theme.textTertiary)
            Text(greeting)
                .font(.displayLarge)
                .foregroundStyle(Theme.textPrimary)
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
        return "\(s.osVersion) · \(s.modelName)"
    }
    
    // MARK: - Anillos de progreso
    
    private var ringsSection: some View {
        HStack(spacing: 24) {
            // Disco
            ringCard(
                title: "ALMACENAMIENTO",
                ring: ProgressRing(
                    progress: systemInfo.snapshot?.diskUsageFraction ?? 0,
                    label: "\(Int((systemInfo.snapshot?.diskUsageFraction ?? 0) * 100))%",
                    sublabel: diskSublabel,
                    gradient: Theme.brandGradient
                )
            )
            
            // RAM
            ringCard(
                title: "MEMORIA",
                ring: ProgressRing(
                    progress: systemInfo.snapshot?.memoryUsageFraction ?? 0,
                    label: "\(Int((systemInfo.snapshot?.memoryUsageFraction ?? 0) * 100))%",
                    sublabel: ramSublabel,
                    gradient: Theme.healthGradient
                )
            )
            
            // CPU
            ringCard(
                title: "CPU",
                ring: ProgressRing(
                    progress: (systemInfo.snapshot?.cpuUsagePercent ?? 0) / 100.0,
                    label: "\(Int(systemInfo.snapshot?.cpuUsagePercent ?? 0))%",
                    sublabel: "uso actual",
                    gradient: LinearGradient(
                        colors: [Theme.warning, Theme.danger],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
        }
    }
    
    private func ringCard<R: View>(title: String, ring: R) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.label)
                .foregroundStyle(Theme.textTertiary)
            ring
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(Theme.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
    }
    
    private var diskSublabel: String {
        guard let s = systemInfo.snapshot else { return "—" }
        return "\(s.freeDiskBytes.formattedAsBytes) libres"
    }
    
    private var ramSublabel: String {
        guard let s = systemInfo.snapshot else { return "—" }
        let used = Int64(s.usedMemoryBytes).formattedAsBytes
        let total = Int64(s.totalMemoryBytes).formattedAsBytes
        return "\(used) de \(total)"
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
        .frame(width: 900, height: 700)
}
