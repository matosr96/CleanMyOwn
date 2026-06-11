//
//  JunkCleanerView.swift
//  CleanMyOwn
//
//  UI del Limpiador: dispara el escaneo, muestra resultados por categoría
//  con selección granular, y borra lo seleccionado tras confirmación
//  (permanente o a la Papelera según el toggle de modo).
//

import AppKit
import SwiftUI

struct JunkCleanerView: View {
    @EnvironmentObject private var service: JunkScanService
    @EnvironmentObject private var admin: AdminSessionService
    @State private var expanded: Set<String> = []
    @State private var showingConfirm = false
    @State private var isCleaning = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @AppStorage(DeleteMode.storageKey) private var deleteToTrash = false
    @EnvironmentObject private var permissions: PermissionsMonitor
    @EnvironmentObject private var history: CleaningHistoryService

    // Hero moment al completar limpieza exitosa
    @State private var showingHero: Bool = false
    @State private var heroBytes: Int64 = 0
    @State private var confettiTrigger: Int = 0

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header.cascadeIn(0)
                    if !service.results.isEmpty {
                        // Con el asistente activo el modo admin por contraseña
                        // es irrelevante: una sola fila verde, cero fricción.
                        if !admin.helperEnabled {
                            adminBanner
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        HelperStatusControls()
                            .transition(.move(edge: .top).combined(with: .opacity))
                        if !permissions.hasFullDiskAccess {
                            fdaBanner
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    if service.isScanning && service.results.isEmpty {
                        // Skeletons mientras arranca el primer scan
                        scanningSkeleton.transition(.opacity)
                    } else if service.results.isEmpty {
                        emptyState.transition(.opacity).cascadeIn(1)
                    } else {
                        summaryCard.cascadeIn(1)
                        categoryList.cascadeIn(2)
                    }
                    if let err = service.lastError {
                        errorBanner(err).transition(.opacity)
                    }
                }
                .padding(32)
                .animation(Anim.smooth, value: service.results.count)
                .animation(Anim.smooth, value: service.isScanning)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlay Hero — confetti + counter al completar limpieza exitosa
            if showingHero {
                heroOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(10)
            }
        }
        .alert(deleteToTrash
                ? "¿Mover \(service.selectedBytes.formattedAsBytes) a la Papelera?"
                : "¿Eliminar \(service.selectedBytes.formattedAsBytes) permanentemente?",
               isPresented: $showingConfirm) {
            Button("Cancelar", role: .cancel) { }
            Button(deleteToTrash ? "Mover a Papelera" : "Eliminar permanentemente",
                   role: .destructive) {
                Task { await runClean() }
            }
        } message: {
            Text(confirmMessage)
        }
        // El alert se queda sólo para casos con error; el éxito muestra el Hero.
        .alert("Limpieza con errores", isPresented: $showingResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Hero overlay (drop the mic)

    private var heroOverlay: some View {
        ZStack {
            // Backdrop oscuro con blur
            Rectangle()
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(Anim.smooth) { showingHero = false } }

            // Confetti detrás del card
            ConfettiView(trigger: confettiTrigger)
                .ignoresSafeArea()

            // Card central
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.success.opacity(0.18))
                        .frame(width: 110, height: 110)
                    Circle().fill(Theme.success.opacity(0.08))
                        .frame(width: 150, height: 150)
                        .blur(radius: 20)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .symbolEffect(.bounce, value: confettiTrigger)
                }
                VStack(spacing: 6) {
                    Text(deleteToTrash ? "A LA PAPELERA" : "LIBERASTE")
                        .font(.label).foregroundStyle(Theme.textTertiary)
                    AnimatedByteCounter(bytes: heroBytes)
                    Text(deleteToTrash ? "Recuperables desde la Papelera 🗑️" : "Tu Mac respira mejor 🎉")
                        .font(.titleMedium).foregroundStyle(Theme.textSecondary)
                }
                Button(action: { withAnimation(Anim.smooth) { showingHero = false } }) {
                    Text("Genial").frame(minWidth: 140)
                }
                .buttonStyle(PolishedPrimaryButtonStyle(
                    fill: AnyShapeStyle(Theme.healthGradient),
                    glow: Theme.success
                ))
            }
            .padding(40)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.success.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Theme.success.opacity(0.25), radius: 30, y: 8)
        }
    }

    // MARK: - Skeleton de escaneo

    private var scanningSkeleton: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.onSurface(0.06))
                        .frame(height: 70)
                        .shimmering()
                }
            }
            ForEach(0..<5, id: \.self) { _ in
                SkeletonCategoryRow()
            }
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
                Text("macOS protege los datos de algunas apps con un permiso adicional. Concede «Acceso completo al disco» a CleanMyOwn en Configuración del Sistema para poder limpiarlos.")
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
                     ? "Las copias de Time Machine y los archivos protegidos se borrarán sin pedir la contraseña otra vez."
                     : "Necesario para borrar copias de Time Machine y archivos protegidos. Pedimos la contraseña una sola vez.")
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

    private var confirmMessage: String {
        if deleteToTrash {
            var msg = "Los elementos se moverán a la Papelera del sistema; podrás recuperarlos desde ahí."
            if service.selectionIncludesAlwaysPermanent {
                msg += "\n\nExcepción: snapshots de Time Machine, simuladores y el contenido de la propia Papelera se eliminan SIEMPRE de forma permanente."
            }
            return msg
        }
        return "Los elementos se borrarán de forma permanente. Esta acción NO se puede deshacer."
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: 16) {
                HeaderIconChip(icon: "trash.fill", tint: Theme.success)
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIMPIEZA")
                        .font(.label)
                        .foregroundStyle(Theme.textTertiary)
                    Text("Liberar espacio")
                        .font(.displayMedium)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Archivos temporales, registros y datos que tu Mac ya no necesita.")
                        .font(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                actionButton
                TrashModeToggle()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if service.isScanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Escaneando…")
            }
            .frame(minWidth: 140)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.card))
            .foregroundStyle(Theme.textPrimary)
        } else if service.results.isEmpty {
            Button(action: { service.startScan() }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Escanear")
                }
            }
            .buttonStyle(PolishedPrimaryButtonStyle())
        } else if service.selectedBytes > 0 {
            Button(action: { showingConfirm = true }) {
                HStack(spacing: 8) {
                    if isCleaning { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: deleteToTrash ? "arrow.up.bin.fill" : "trash.fill") }
                    Text(isCleaning ? "Limpiando…" : "Limpiar \(service.selectedBytes.formattedAsBytes)")
                }
            }
            .buttonStyle(PolishedDestructiveButtonStyle())
            .disabled(isCleaning)
        } else {
            Button(action: { service.startScan() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-escanear")
                }
            }
            .buttonStyle(PolishedPrimaryButtonStyle())
        }
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
            } else {
                HStack(spacing: 6) {
                    quickSelectButton("Todo") { service.selectAll() }
                    quickSelectButton("Nada") { service.selectNone() }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .stroke(Theme.onSurface(0.04), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.onSurface(0.06)).frame(width: 1, height: 36)
    }

    private func summaryStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.label).foregroundStyle(Theme.textTertiary)
            Text(value).font(.titleLarge).foregroundStyle(tint)
        }
    }

    private func quickSelectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.bodySmall.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
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
        EmptyStateView(
            icon: "magnifyingglass",
            tint: Theme.success,
            title: "Listo para escanear",
            subtitle: "Pulsa «Escanear» para revisar archivos temporales, registros y papelera.\nNada se borra hasta que tú lo confirmes."
        )
        .frame(minHeight: 460)
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

        // Si hay items que requieren admin y no hay vía de escalado (sesión
        // AEWP o helper), activar la sesión (un único prompt)
        if service.selectionRequiresAdmin && !admin.canEscalate {
            let ok = await admin.activate()
            if !ok {
                isCleaning = false
                resultMessage = admin.lastError ?? "Necesitas activar el modo administrador para borrar snapshots."
                showingResult = true
                return
            }
        }

        let plannedItems = service.selection.count
        let plannedCategories = service.results.filter { res in
            res.items.contains { service.selection.contains($0.id) }
        }.count
        let freed = await service.cleanSelected(adminSession: admin, moveToTrash: deleteToTrash)
        isCleaning = false
        history.record(kind: .junk, freedBytes: freed, itemCount: plannedItems,
                       mode: deleteToTrash ? .trash : .permanent,
                       summary: "\(plannedCategories) categoría\(plannedCategories == 1 ? "" : "s")")
        if let err = service.lastError {
            // Caso con errores: alert
            let verb = deleteToTrash ? "Se enviaron \(freed.formattedAsBytes) a la Papelera" : "Se liberaron \(freed.formattedAsBytes)"
            resultMessage = "\(verb), pero hubo errores:\n\n\(err)"
            showingResult = true
        } else {
            // Caso éxito: Hero moment con confetti + counter
            heroBytes = freed
            withAnimation(Anim.smooth) { showingHero = true }
            // Pequeño delay para que el counter empiece desde 0 y luego se dispara confetti
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                confettiTrigger += 1
            }
        }
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

            // Proporción de esta categoría sobre el total encontrado
            if result.totalBytes > 0 && service.totalBytes > 0 {
                GeometryReader { geo in
                    let fraction = CGFloat(result.totalBytes) / CGFloat(service.totalBytes)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.onSurface(0.05))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [result.category.tint, result.category.tint.opacity(0.45)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(geo.size.width * fraction, 6))
                            .shadow(color: result.category.tint.opacity(0.5), radius: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if expanded {
                Divider().background(Theme.onSurface(0.06))
                VStack(spacing: 0) {
                    ForEach(result.items) { item in
                        JunkItemRow(item: item, service: service, tint: result.category.tint)
                        if item.id != result.items.last?.id {
                            Divider().background(Theme.onSurface(0.04))
                        }
                    }
                }
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card)
                // Tint del color de la categoría (sutil)
                LinearGradient(
                    colors: [result.category.tint.opacity(0.10), result.category.tint.opacity(0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .stroke(result.category.tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: result.category.tint.opacity(0.08), radius: 12, y: 4)
    }
}

private struct JunkItemRow: View {
    let item: JunkItem
    @ObservedObject var service: JunkScanService
    let tint: Color

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Toggle(isOn: Binding(
                get: { service.selection.contains(item.id) },
                set: { _ in service.toggle(item) }
            )) { EmptyView() }
                .toggleStyle(CheckboxToggleStyle(partial: false, tint: tint))

            Image(systemName: iconName)
                .foregroundStyle(tint.opacity(0.85))
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

            // Acción contextual al hover (patrón Finder)
            if hovering, let url = item.url {
                Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                    Image(systemName: "magnifyingglass.circle")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Mostrar en Finder")
                .transition(.opacity)
            }

            Text(sizeLabel)
                .font(.bodyMedium)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hovering ? Theme.onSurface(0.03) : Color.clear)
        .onHover { hovering = $0 }
        .animation(Anim.hover, value: hovering)
    }

    private var iconName: String {
        switch item.kind {
        case .file(let url): return FileTypeIcon.symbol(for: url, isDirectory: item.isDirectory)
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
                    .stroke(configuration.isOn || partial ? tint : Theme.onSurface(0.25), lineWidth: 1.5)
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
    JunkCleanerView()
        .environmentObject(PermissionsMonitor.shared)
        .environmentObject(AdminSessionService())
        .environmentObject(JunkScanService())
        .frame(width: 900, height: 700)
}
