//
//  LoginItemsView.swift
//  CleanMyOwn
//
//  Lista los Launch Agents y Daemons del sistema, con toggle de habilitar/
//  deshabilitar para los del usuario.
//

import AppKit
import SwiftUI

struct LoginItemsView: View {
    @StateObject private var service = LaunchAgentService()
    @State private var query: String = ""
    @State private var actionError: String?

    private var grouped: [(LaunchAgentScope, [LaunchAgent])] {
        let filtered = query.isEmpty ? service.agents : service.agents.filter {
            $0.label.localizedCaseInsensitiveContains(query)
            || $0.program?.localizedCaseInsensitiveContains(query) ?? false
        }
        let dict = Dictionary(grouping: filtered, by: { $0.scope })
        return [.userAgent, .systemAgent, .systemDaemon].compactMap { scope in
            dict[scope].map { (scope, $0) }
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchAndStats
                list
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if service.agents.isEmpty { service.reload() } }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: 16) {
                HeaderIconChip(icon: "power", tint: Theme.danger)
                VStack(alignment: .leading, spacing: 8) {
                    Text("ARRANQUE").font(.label).foregroundStyle(Theme.textTertiary)
                    Text("Apps en segundo plano").font(.displayMedium).foregroundStyle(Theme.textPrimary)
                    Text("Programas que se ponen en marcha al encender tu Mac o iniciar sesión.")
                        .font(.bodyMedium).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button(action: { service.reload() }) {
                Label(service.isLoading ? "Cargando…" : "Actualizar", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                    .foregroundStyle(Theme.textPrimary)
            }.buttonStyle(.plain).disabled(service.isLoading)
        }
    }

    private var searchAndStats: some View {
        HStack(spacing: 14) {
            SearchField(text: $query, placeholder: "Buscar por nombre o programa…")
                .frame(maxWidth: 380)

            Spacer()
            statBadge(label: "TU USUARIO", value: count(.userAgent), tint: Theme.success)
            statBadge(label: "SISTEMA", value: count(.systemAgent), tint: Theme.accent)
            statBadge(label: "SERVICIOS", value: count(.systemDaemon), tint: Theme.warning)
        }
    }

    private func count(_ scope: LaunchAgentScope) -> String {
        "\(service.agents.filter { $0.scope == scope }.count)"
    }

    private func statBadge(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.label).foregroundStyle(Theme.textTertiary).tracking(1.2)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.15), radius: 8, y: 2)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(grouped, id: \.0) { (scope, agents) in
                    sectionView(scope: scope, agents: agents)
                }
                if !service.isLoading && grouped.isEmpty {
                    Text("Sin resultados.").font(.bodyMedium).foregroundStyle(Theme.textTertiary).padding(.top, 40)
                }
            }
        }
    }

    private func sectionView(scope: LaunchAgentScope, agents: [LaunchAgent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(scope.displayName).font(.titleMedium).foregroundStyle(Theme.textPrimary)
                if scope.requiresAdmin {
                    Text("Sólo lectura").font(.label).foregroundStyle(Theme.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warning.opacity(0.12)))
                }
                Spacer()
                Text("\(agents.count) items").font(.bodySmall).foregroundStyle(Theme.textTertiary)
            }
            VStack(spacing: 4) {
                ForEach(agents) { agent in
                    AgentRow(agent: agent, onToggle: { newValue in
                        Task {
                            if let err = await service.setEnabled(newValue, agent: agent) {
                                actionError = err
                            }
                        }
                    })
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.cardGradient))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).stroke(Color.white.opacity(0.04), lineWidth: 1))
        }
    }
}

private struct AgentRow: View {
    let agent: LaunchAgent
    let onToggle: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(statusColor.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor).font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.label).font(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let p = agent.program {
                    Text(p).font(.bodySmall).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if hovering {
                Button(action: { NSWorkspace.shared.activateFileViewerSelecting([agent.plistURL]) }) {
                    Image(systemName: "magnifyingglass.circle").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Mostrar plist en Finder")
                .transition(.opacity)
            }
            HStack(spacing: 6) {
                if agent.runAtLoad { badge("AL INICIAR", tint: Theme.accent) }
                if agent.keepAlive { badge("SIEMPRE ACTIVO", tint: Theme.warning) }
                if agent.isDisabledByFile { badge("DESACTIVADO", tint: Theme.danger) }
            }
            if agent.scope == .userAgent {
                Toggle("", isOn: Binding(
                    get: { !agent.isDisabledByFile },
                    set: { onToggle($0) }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            } else {
                Image(systemName: agent.isLoaded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(agent.isLoaded ? Theme.success : Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.white.opacity(0.045) : Color.white.opacity(0.02)))
        .onHover { hovering = $0 }
        .animation(Anim.hover, value: hovering)
    }

    private var statusColor: Color {
        if agent.isDisabledByFile { return Theme.danger }
        if agent.isLoaded { return Theme.success }
        return Theme.textTertiary
    }
    private var statusIcon: String {
        if agent.isDisabledByFile { return "xmark" }
        if agent.isLoaded { return "bolt.fill" }
        return "circle"
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text).font(.label).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

#Preview {
    LoginItemsView().frame(width: 1000, height: 700)
}
