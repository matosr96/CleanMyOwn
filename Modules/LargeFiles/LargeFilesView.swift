//
//  LargeFilesView.swift
//  CleanMyOwn
//
//  UI: scanner de archivos grandes y duplicados.
//

import AppKit
import SwiftUI

struct LargeFilesView: View {
    @StateObject private var service = LargeFilesService()
    @State private var tab: Tab = .large
    @State private var thresholdMB: Double = 100
    @State private var showingConfirm = false
    @State private var isDeleting = false
    @State private var showingResult = false
    @State private var lastFreed: Int64 = 0

    enum Tab { case large, dupes }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            controls
            tabs
            content
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .alert("¿Eliminar \(service.selectedBytes.formattedAsBytes) permanentemente?", isPresented: $showingConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar permanentemente", role: .destructive) { Task { await runDelete() } }
        } message: {
            Text("Los archivos se borrarán de forma permanente del disco. Esta acción NO se puede deshacer.")
        }
        .alert("Limpieza completada", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Se liberaron \(lastFreed.formattedAsBytes).")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ARCHIVOS GRANDES").font(.label).foregroundStyle(Theme.textTertiary)
            Text("Encuentra qué ocupa espacio").font(.displayMedium).foregroundStyle(Theme.textPrimary)
            Text("Escanea archivos pesados y detecta duplicados por contenido (SHA256).")
                .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            // Carpeta
            Button(action: pickFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(service.rootURL.path).lineLimit(1).truncationMode(.middle)
                }
                .font(.bodyMedium)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 320, alignment: .leading)

            // Slider de tamaño
            HStack(spacing: 8) {
                Text("Mín. \(Int(thresholdMB)) MB")
                    .font(.bodySmall).foregroundStyle(Theme.textSecondary).frame(width: 90, alignment: .trailing)
                Slider(value: $thresholdMB, in: 10...2000, step: 10)
                    .frame(width: 200)
                    .onChange(of: thresholdMB) { _, v in
                        service.minSizeBytes = Int64(v) * 1_048_576
                    }
            }

            Spacer()

            // Botón scan
            if service.isScanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white); Text("Escaneando…") }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Button(action: { service.startScan() }) {
                    Text("Escanear").font(.titleMedium)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.brandGradient))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }

            if service.selectedBytes > 0 {
                Button(action: { showingConfirm = true }) {
                    Text("Eliminar \(service.selectedBytes.formattedAsBytes)").font(.titleMedium)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(
                            colors: [Theme.danger, Color(red: 1.0, green: 0.55, blue: 0.40)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain).disabled(isDeleting)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabButton("Archivos · \(service.files.count)", isSelected: tab == .large) { tab = .large }
            tabButton("Duplicados · \(service.duplicates.count)", isSelected: tab == .dupes) {
                tab = .dupes
                if service.duplicates.isEmpty && !service.files.isEmpty { service.computeDuplicates() }
            }
            Spacer()
            if !service.progressLabel.isEmpty {
                Text(service.progressLabel).font(.bodySmall).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func tabButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.bodyMedium)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .large: largeFilesList
        case .dupes: duplicatesList
        }
    }

    private var largeFilesList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(service.files) { file in fileRow(file) }
                if service.files.isEmpty && !service.isScanning {
                    Text("Pulsa «Escanear» para encontrar archivos grandes.")
                        .font(.bodyMedium).foregroundStyle(Theme.textTertiary).padding(.top, 40)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }

    private func fileRow(_ file: LargeFile) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { service.selection.contains(file.id) },
                set: { _ in service.toggle(file) }
            )) { EmptyView() }
                .toggleStyle(CheckboxToggleStyle(partial: false, tint: Theme.warning))
            Image(systemName: file.isDirectory ? "shippingbox.fill" : "doc.fill")
                .foregroundStyle(file.isDirectory ? Theme.warning : Theme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName).font(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(file.parentDir).font(.bodySmall).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let date = file.modifiedDate {
                Text(date, style: .date).font(.bodySmall).foregroundStyle(Theme.textTertiary)
            }
            Text(file.sizeBytes.formattedAsBytes)
                .font(.bodyMedium).foregroundStyle(Theme.textPrimary).monospacedDigit().frame(width: 100, alignment: .trailing)
            Button(action: { showInFinder(file.url) }) {
                Image(systemName: "magnifyingglass.circle").foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.plain).help("Mostrar en Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var duplicatesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if service.isHashing { ProgressView().controlSize(.small) }
                Text("Espacio desperdiciado: \(service.totalWastedBytes.formattedAsBytes)")
                    .font(.titleMedium).foregroundStyle(Theme.warning)
                Spacer()
                Button(action: { service.autoSelectDuplicatesKeepingOldest() }) {
                    Text("Seleccionar duplicados (mantener uno)").font(.bodyMedium)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .foregroundStyle(Theme.textPrimary)
                }.buttonStyle(.plain).disabled(service.duplicates.isEmpty)
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(service.duplicates) { group in
                        DuplicateGroupCard(group: group, service: service)
                    }
                    if service.duplicates.isEmpty && !service.isHashing {
                        Text(service.files.isEmpty
                             ? "Escanea primero para detectar duplicados."
                             : "No se encontraron duplicados entre los archivos escaneados.")
                            .font(.bodyMedium).foregroundStyle(Theme.textTertiary)
                            .padding(.top, 40).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Acciones

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = service.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            service.rootURL = url
        }
    }

    private func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func runDelete() async {
        isDeleting = true
        lastFreed = await service.deleteSelected()
        isDeleting = false
        showingResult = true
    }
}

private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @ObservedObject var service: LargeFilesService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.files.count) copias · \(group.files.first?.sizeBytes.formattedAsBytes ?? "—") c/u")
                    .font(.titleMedium).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(group.wastedBytes.formattedAsBytes) desperdiciados")
                    .font(.bodyMedium).foregroundStyle(Theme.warning)
            }
            VStack(spacing: 4) {
                ForEach(group.files) { file in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { service.selection.contains(file.id) },
                            set: { _ in service.toggle(file) }
                        )) { EmptyView() }
                            .toggleStyle(CheckboxToggleStyle(partial: false, tint: Theme.warning))
                        Image(systemName: "doc").foregroundStyle(Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.displayName).font(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(file.parentDir).font(.bodySmall).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let date = file.modifiedDate {
                            Text(date, style: .date).font(.bodySmall).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }
}

#Preview {
    LargeFilesView().frame(width: 1100, height: 700)
}
