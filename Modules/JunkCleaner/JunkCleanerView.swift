//
//  JunkCleanerView.swift
//  CleanMyOwn
//
//  UI del Limpiador: dispara el escaneo, muestra resultados por categoría
//  con selección granular, y permite mover lo seleccionado a la Papelera.
//

import SwiftUI

struct JunkCleanerView: View {
    @StateObject private var service = JunkScanService()
    @StateObject private var admin = AdminSessionService()
    @State private var expanded: Set<String> = []
    @State private var showingConfirm = false
    @State private var isCleaning = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultIsSuccess = true
    @EnvironmentObject private var permissions: PermissionsMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !service.results.isEmpty {
                    adminBanner
                    if !permissions.hasFullDiskAccess {
                        fdaBanner
                    }
                }
                if service.results.isEmpty && !service.isScanning {
                    emptyState
                } else {
                    summaryCard
                    categoryList
                }
                if let err = service.lastError {
                    errorBanner(err)
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onDisappear { admin.deactivate() }
        .alert("¿Eliminar \(service.selectedBytes.formattedAsBytes) permanentemente?", isPresented: $showingConfirm) {
            Button("Cancelar", role: .cancel) { }
            Button("Eliminar permanentemente", role: .destructive) {
                Task { await runClean() }
            }
        } message: {
            Text("Los elementos se borrarán de forma permanente. Esta acción NO se puede deshacer.")
        }
        .alert(resultIsSuccess ? "Limpieza completada" : "Limpieza con errores",
               isPresented: $showingResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Banner Full Disk Access

    private var fdaBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Theme.danger)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Falta «Acceso completo al disco»")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text("macOS protege ~/Library/Containers de apps sandboxed con TCC. Sin FDA, ni siquiera con admin podemos borrar esos directorios huérfanos. Añade CleanMyOwn a la lista en Configuración del Sistema y reinícialo.")
                    .font(.bodySmall).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: {
                AdminSessionService.openFullDiskAccessSettings()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Abrir Configuración").font(.bodyMedium.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger))
                .foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button(action: { permissions.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                    .foregroundStyle(Theme.textPrimary)
            }.buttonStyle(.plain).help("Revisar estado de FDA")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.danger.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).stroke(Theme.danger.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Banner admin (sólo si hay items que lo requieren)

    private var adminBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: admin.isActive ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(admin.isActive ? Theme.success : Theme.warning)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(admin.isActive ? "Modo administrador activo" : "Algunos items requieren administrador")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(admin.isActive
                     ? "Snapshots de TM y archivos protegidos por el sistema se borrarán sin pedir contraseña adicional."
                     : "Recomendado para borrar snapshots de Time Machine y datos huérfanos protegidos por TCC. Pedimos la contraseña una sola vez.")
                    .font(.bodySmall).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if admin.isActive {
                Button(action: { admin.deactivate() }) {
                    Text("Desactivar").font(.bodyMedium)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .foregroundStyle(Theme.textPrimary)
                }.buttonStyle(.plain)
            } else {
                Button(action: { Task { await admin.activate() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                        Text("Activar").font(.bodyMedium.weight(.semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.brandGradient))
                    .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .fill((admin.isActive ? Theme.success : Theme.warning).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .stroke((admin.isActive ? Theme.success : Theme.warning).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("LIMPIEZA")
                    .font(.label)
                    .foregroundStyle(Theme.textTertiary)
                Text("Liberar espacio")
                    .font(.displayMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Cachés, logs y datos temporales que tu Mac ya no necesita.")
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            actionButton
        }
    }

    private var actionButton: some View {
        Group {
            if service.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Escaneando…").font(.titleMedium)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.card))
                .foregroundStyle(Theme.textPrimary)
            } else if service.results.isEmpty {
                Button(action: { service.startScan() }) { actionLabel(text: "Escanear") }
                    .buttonStyle(.plain)
            } else if service.selectedBytes > 0 {
                Button(action: { showingConfirm = true }) {
                    actionLabel(text: isCleaning ? "Limpiando…" : "Limpiar \(service.selectedBytes.formattedAsBytes)", danger: true, busy: isCleaning)
                }
                .buttonStyle(.plain)
                .disabled(isCleaning)
            } else {
                Button(action: { service.startScan() }) { actionLabel(text: "Re-escanear") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func actionLabel(text: String, danger: Bool = false, busy: Bool = false) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(.white) }
            Text(text).font(.titleMedium)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(danger ?
                      LinearGradient(colors: [Theme.danger, Color(red: 1.0, green: 0.55, blue: 0.40)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                      : Theme.brandGradient)
        )
        .foregroundStyle(.white)
        .shadow(color: Theme.shadowColor, radius: 10, y: 4)
    }

    // MARK: - Resumen

    private var summaryCard: some View {
        HStack(spacing: 24) {
            summaryStat(label: "ENCONTRADO", value: service.totalBytes.formattedAsBytes, tint: Theme.warning)
            divider
            summaryStat(label: "SELECCIONADO", value: service.selectedBytes.formattedAsBytes, tint: Theme.success)
            divider
            summaryStat(label: "CATEGORÍAS", value: "\(service.results.filter { !$0.items.isEmpty }.count)", tint: Theme.accent)
            Spacer()
            if service.isScanning {
                Text(service.scanProgressLabel)
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 36)
    }

    private func summaryStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.label).foregroundStyle(Theme.textTertiary)
            Text(value).font(.titleLarge).foregroundStyle(tint)
        }
    }

    // MARK: - Lista de categorías

    private var categoryList: some View {
        VStack(spacing: 10) {
            ForEach(service.results.filter { !$0.items.isEmpty }) { result in
                JunkCategoryRow(
                    result: result,
                    expanded: expanded.contains(result.id),
                    service: service,
                    onToggle: {
                        if expanded.contains(result.id) { expanded.remove(result.id) }
                        else { expanded.insert(result.id) }
                    }
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.success.opacity(0.15)).frame(width: 90, height: 90)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.success)
            }
            Text("Listo para escanear")
                .font(.titleLarge)
                .foregroundStyle(Theme.textPrimary)
            Text("Pulsa «Escanear» para inspeccionar cachés, logs y archivos temporales.\nNada se borra hasta que tú lo confirmes — y el borrado es permanente.")
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(msg).font(.bodySmall).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.warning.opacity(0.1)))
    }

    // MARK: - Acciones

    private func runClean() async {
        isCleaning = true

        // Si hay items que requieren admin y no está activo, activarlo (un único prompt)
        if service.selectionRequiresAdmin && !admin.isActive {
            let ok = await admin.activate()
            if !ok {
                isCleaning = false
                resultIsSuccess = false
                resultMessage = admin.lastError ?? "Necesitas activar el modo administrador para borrar snapshots."
                showingResult = true
                return
            }
        }

        let freed = await service.cleanSelected(adminSession: admin)
        isCleaning = false
        if let err = service.lastError {
            resultIsSuccess = false
            resultMessage = "Se liberaron \(freed.formattedAsBytes), pero hubo errores:\n\n\(err)"
        } else {
            resultIsSuccess = true
            resultMessage = "Se liberaron \(freed.formattedAsBytes)."
        }
        showingResult = true
    }
}

// MARK: - Fila de categoría expandible

private func categoryTotalLabel(_ result: JunkCategoryResult) -> String {
    if case .timeMachineSnapshots = result.category.kind {
        return "\(result.items.count) snapshot\(result.items.count == 1 ? "" : "s")"
    }
    if result.totalBytes == 0 && !result.items.isEmpty {
        return "\(result.items.count) items"
    }
    return result.totalBytes.formattedAsBytes
}

private struct JunkCategoryRow: View {
    let result: JunkCategoryResult
    let expanded: Bool
    @ObservedObject var service: JunkScanService
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle(isOn: Binding(
                    get: { service.isFullySelected(result) },
                    set: { service.setSelection(category: result, selected: $0) }
                )) { EmptyView() }
                    .toggleStyle(CheckboxToggleStyle(partial: service.isPartiallySelected(result), tint: result.category.tint))

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(result.category.tint.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: result.category.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(result.category.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.category.name).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                        if result.category.requiresAdmin {
                            Text("ADMIN").font(.label).foregroundStyle(Theme.warning)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.warning.opacity(0.15)))
                        }
                    }
                    Text(result.category.blurb).font(.bodySmall).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(categoryTotalLabel(result))
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            if expanded {
                Divider().background(Color.white.opacity(0.06))
                VStack(spacing: 0) {
                    ForEach(result.items) { item in
                        JunkItemRow(item: item, service: service, tint: result.category.tint)
                        if item.id != result.items.last?.id {
                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct JunkItemRow: View {
    let item: JunkItem
    @ObservedObject var service: JunkScanService
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Toggle(isOn: Binding(
                get: { service.selection.contains(item.id) },
                set: { _ in service.toggle(item) }
            )) { EmptyView() }
                .toggleStyle(CheckboxToggleStyle(partial: false, tint: tint))

            Image(systemName: iconName)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail).font(.bodySmall).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(sizeLabel)
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var iconName: String {
        switch item.kind {
        case .file: return item.isDirectory ? "folder.fill" : "doc.fill"
        case .localSnapshot: return "clock.arrow.circlepath"
        case .simulator: return "iphone"
        }
    }

    private var sizeLabel: String {
        if case .localSnapshot = item.kind { return "tamaño variable" }
        if item.sizeBytes == 0 { return "—" }
        return item.sizeBytes.formattedAsBytes
    }
}

// MARK: - Checkbox custom

struct CheckboxToggleStyle: ToggleStyle {
    let partial: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(configuration.isOn || partial ? tint : Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if configuration.isOn {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if partial {
                    Rectangle().fill(tint).frame(width: 9, height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JunkCleanerView().frame(width: 900, height: 700)
}
