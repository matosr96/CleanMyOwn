//
//  UninstallerView.swift
//  CleanMyOwn
//
//  Lista de apps instaladas, con búsqueda. Al seleccionar una app se buscan
//  sus archivos asociados (Application Support, Caches, Preferences, etc.) y
//  el usuario elige qué incluir. El borrado es PERMANENTE (no pasa por la
//  Papelera) y se confirma con un alert destructivo.
//
//  Los matches por bundle ID vienen preseleccionados; los matches por nombre
//  (heurística con riesgo de colisión) se muestran sin marcar.
//

import AppKit
import SwiftUI

struct UninstallerView: View {
    @StateObject private var catalog = AppCatalogService()
    @EnvironmentObject private var admin: AdminSessionService
    @State private var query: String = ""
    @State private var selectedAppID: String?
    @State private var selectedApp: AppEntry?
    @State private var associated: [AssociatedItem] = []
    @State private var loadingAssoc = false
    @State private var assocSelection: Set<UUID> = []
    @State private var showingConfirm = false
    @State private var isUninstalling = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultIsSuccess = true
    @AppStorage(DeleteMode.storageKey) private var deleteToTrash = false

    private var filteredApps: [AppEntry] {
        guard !query.isEmpty else { return catalog.apps }
        return catalog.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            AnimatedBackground(intensity: 0.28)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 12)
                adminBanner.padding(.horizontal, 32).padding(.bottom, 8)
                HelperStatusControls().padding(.horizontal, 32).padding(.bottom, 18)

                HStack(spacing: 18) {
                    appList
                    detail
                }
                .padding(.horizontal, 32).padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if catalog.apps.isEmpty { catalog.reload() }
        }
        .alert(deleteToTrash
                ? "¿Mover \(selectedApp?.name ?? "") a la Papelera?"
                : "¿Desinstalar \(selectedApp?.name ?? "") permanentemente?",
               isPresented: $showingConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button(deleteToTrash ? "Mover a Papelera" : "Eliminar permanentemente",
                   role: .destructive) {
                Task { await runUninstall() }
            }
        } message: {
            Text(deleteToTrash
                 ? "La app y los archivos asociados seleccionados se moverán a la Papelera; podrás recuperarlos desde ahí. Las apps protegidas del sistema pueden requerir el modo permanente."
                 : "La app y los archivos asociados seleccionados se borrarán de forma permanente del disco. Esta acción NO se puede deshacer.")
        }
        .alert(resultIsSuccess ? "Desinstalación completada" : "No se pudo eliminar todo",
               isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Admin banner

    private var adminBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: admin.isActive ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(admin.isActive ? Theme.success : Theme.warning)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(admin.isActive ? "Modo administrador activo" : "Modo administrador desactivado")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Text(admin.isActive
                     ? "Las apps protegidas se eliminarán sin pedir contraseña adicional durante esta sesión."
                     : "Algunas apps en /Applications requieren contraseña para borrarse. Activa este modo y la pedimos una sola vez.")
                    .font(.bodySmall).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if admin.isActive {
                Button(action: { admin.deactivate() }) {
                    Text("Desactivar").font(.bodyMedium)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .foregroundStyle(Theme.textPrimary)
                }.buttonStyle(.plain)
            } else {
                Button(action: { Task { await admin.activate() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                        Text("Activar").font(.bodyMedium.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.brandGradient))
                    .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .fill(admin.isActive ? Theme.success.opacity(0.10) : Theme.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .stroke((admin.isActive ? Theme.success : Theme.warning).opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DESINSTALADOR")
                    .font(.label).foregroundStyle(Theme.textTertiary)
                Text("Aplicaciones instaladas")
                    .font(.displayMedium).foregroundStyle(Theme.textPrimary)
                Text("Desinstala una app y todos sus archivos asociados de forma limpia.")
                    .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: { catalog.reload() }) {
                Label(catalog.isLoading ? "Cargando…" : "Actualizar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PolishedSecondaryButtonStyle())
            .disabled(catalog.isLoading)
        }
    }

    // MARK: - Lista

    private var appList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchField(text: $query, placeholder: "Buscar app…")

            ScrollView {
                LazyVStack(spacing: 4) {
                    if catalog.isLoading && catalog.apps.isEmpty {
                        ForEach(0..<8, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.10))
                                        .frame(width: 130, height: 11)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                                        .frame(width: 60, height: 9)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .shimmering()
                        }
                    } else {
                        ForEach(filteredApps) { app in
                            AppRow(app: app, isSelected: selectedAppID == app.id) {
                                select(app: app)
                            }
                        }
                        if !catalog.isLoading && filteredApps.isEmpty {
                            Text(query.isEmpty ? "No se encontraron aplicaciones." : "Sin resultados para «\(query)».")
                                .font(.bodyMedium).foregroundStyle(Theme.textTertiary)
                                .padding(20)
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }

    // MARK: - Detalle

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let app = selectedApp {
                detailHeader(app: app)
                associatedSection
                Spacer(minLength: 0)
                actionBar(app: app)
            } else {
                EmptyStateView(
                    icon: "shippingbox.fill",
                    tint: Theme.warning,
                    title: "Elige una app",
                    subtitle: "Selecciona una app de la lista para ver sus archivos asociados (Application Support, Caches, Containers, etc.) y desinstalarla limpiamente."
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }

    private func detailHeader(app: AppEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 56, height: 56)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Theme.card).frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.titleLarge).foregroundStyle(Theme.textPrimary)
                if let v = app.version { Text("Versión \(v)").font(.bodySmall).foregroundStyle(Theme.textSecondary) }
                if let bid = app.bundleID { Text(bid).font(.bodySmall).foregroundStyle(Theme.textTertiary) }
                Text("\(app.sizeBytes.formattedAsBytes) · \(app.location.path)")
                    .font(.bodySmall).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var associatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Archivos asociados").font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Spacer()
                if loadingAssoc { ProgressView().controlSize(.small) }
                else if !associated.isEmpty {
                    Text(associated.reduce(Int64(0)) { $0 + $1.sizeBytes }.formattedAsBytes)
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }
            }

            if !loadingAssoc && associated.isEmpty {
                Text("No se encontraron archivos asociados.")
                    .font(.bodySmall).foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(associated) { item in
                            HStack(spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { assocSelection.contains(item.id) },
                                    set: { v in
                                        if v { assocSelection.insert(item.id) }
                                        else { assocSelection.remove(item.id) }
                                    }
                                )) { EmptyView() }
                                    .toggleStyle(CheckboxToggleStyle(partial: false, tint: Theme.warning))

                                Text(item.category)
                                    .font(.label).foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.warning.opacity(0.12)))

                                if item.isNameMatch {
                                    Text("POR NOMBRE")
                                        .font(.label).foregroundStyle(Theme.textTertiary)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.06)))
                                        .help("Coincide sólo por el nombre de la app — puede pertenecer a otra. Revisa la ruta antes de marcarlo.")
                                }

                                Text(item.url.path).font(.bodySmall)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(item.sizeBytes.formattedAsBytes)
                                    .font(.bodySmall).foregroundStyle(Theme.textSecondary).monospacedDigit()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func actionBar(app: AppEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ESPACIO TOTAL A LIBERAR").font(.label).foregroundStyle(Theme.textTertiary)
                Text(totalToFree(app: app).formattedAsBytes)
                    .font(.titleLarge).foregroundStyle(Theme.success)
            }
            Spacer()
            TrashModeToggle()
            Button(action: { showingConfirm = true }) {
                HStack(spacing: 8) {
                    if isUninstalling { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: deleteToTrash ? "arrow.up.bin.fill" : "trash.fill") }
                    Text(isUninstalling ? "Desinstalando…" : "Desinstalar")
                }
            }
            .buttonStyle(PolishedDestructiveButtonStyle())
            .disabled(isUninstalling || app.isSystemApp)
            .opacity(app.isSystemApp ? 0.4 : 1)
        }
    }

    private func totalToFree(app: AppEntry) -> Int64 {
        app.sizeBytes + associated.filter { assocSelection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: - Acciones

    private func select(app: AppEntry) {
        selectedAppID = app.id
        selectedApp = app
        associated = []
        assocSelection = []
        loadingAssoc = true
        Task {
            let items = await catalog.findAssociatedFiles(for: app)
            await MainActor.run {
                self.associated = items
                // Sólo se preseleccionan los matches por bundle ID; los de
                // nombre los revisa y marca el usuario.
                self.assocSelection = Set(items.filter { !$0.isNameMatch }.map(\.id))
                self.loadingAssoc = false
            }
        }
    }

    private func runUninstall() async {
        guard let app = selectedApp else { return }
        isUninstalling = true
        let toRemove = associated.filter { assocSelection.contains($0.id) }

        var result = await catalog.uninstall(app, includingAssociated: toRemove,
                                             adminSession: admin, moveToTrash: deleteToTrash)

        // Si se requiere admin y el modo no estaba activo, lo activamos AHORA
        // (un único prompt) y reintentamos automáticamente.
        if result.needsAdmin {
            let activated = await admin.activate()
            if activated {
                result = await catalog.uninstall(app, includingAssociated: toRemove,
                                                 adminSession: admin, moveToTrash: deleteToTrash)
            } else {
                isUninstalling = false
                showResult(success: false,
                           message: admin.lastError ?? "Esta app requiere autorización de administrador.")
                return
            }
        }

        isUninstalling = false

        let killedNote = result.processesKilled > 0
            ? " Cerré \(result.processesKilled) proceso\(result.processesKilled == 1 ? "" : "s") activo\(result.processesKilled == 1 ? "" : "s") antes de borrar."
            : ""
        let freedVerb = deleteToTrash
            ? "Se enviaron \(result.freedBytes.formattedAsBytes) a la Papelera."
            : "Se liberaron \(result.freedBytes.formattedAsBytes)."

        if result.appRemoved && result.failedURLs.isEmpty {
            clearSelection()
            showResult(success: true,
                       message: "\(freedVerb)\(killedNote)")
        } else if !result.appRemoved {
            showResult(success: false,
                       message: "La app sigue en disco.\(killedNote) " + (result.errors.first ?? "Operación cancelada."))
        } else {
            let lines = result.errors.prefix(6).joined(separator: "\n")
            showResult(success: false,
                       message: "Se liberaron \(result.freedBytes.formattedAsBytes).\(killedNote)\nAlgunos archivos asociados quedaron:\n\n\(lines)")
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedApp = nil
        selectedAppID = nil
        associated = []
        assocSelection = []
    }

    private func showResult(success: Bool, message: String) {
        resultIsSuccess = success
        resultMessage = message
        showingResult = true
    }
}

private struct AppRow: View {
    let app: AppEntry
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.card).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(app.name).font(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        if app.requiresAdmin {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.warning)
                                .help("Requiere autorización de administrador")
                        }
                    }
                    Text(app.sizeBytes.formattedAsBytes).font(.bodySmall).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : (hovering ? Color.white.opacity(0.03) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

#Preview {
    UninstallerView()
        .environmentObject(AdminSessionService())
        .frame(width: 1000, height: 700)
}
