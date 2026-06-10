//
//  TrashModeToggle.swift
//  CleanMyOwn
//
//  Toggle persistente (UserDefaults) entre borrado permanente y mover a la
//  Papelera. Las vistas leen la misma key con @AppStorage y pasan el modo a
//  los servicios en cada operación.
//
//  Excepciones que son SIEMPRE permanentes aunque el modo Papelera esté
//  activo: snapshots de Time Machine, simuladores, el contenido de la propia
//  Papelera, y cualquier borrado privilegiado (root no puede mover archivos
//  a la Papelera del usuario).
//

import SwiftUI

/// Key compartida del modo de borrado.
enum DeleteMode {
    static let storageKey = "deleteToTrash"
}

struct TrashModeToggle: View {
    @AppStorage(DeleteMode.storageKey) private var deleteToTrash = false

    var body: some View {
        Toggle(isOn: $deleteToTrash) {
            HStack(spacing: 6) {
                Image(systemName: deleteToTrash ? "arrow.up.bin.fill" : "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deleteToTrash ? Theme.success : Theme.danger)
                Text(deleteToTrash ? "A la Papelera" : "Borrado permanente")
                    .font(.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(deleteToTrash
              ? "Los archivos se mueven a la Papelera y puedes recuperarlos. Snapshots, simuladores y borrados con admin siguen siendo permanentes."
              : "Los archivos se eliminan de forma permanente e irreversible. Activa el toggle para enviarlos a la Papelera en su lugar.")
    }
}

#Preview {
    TrashModeToggle().padding()
}
