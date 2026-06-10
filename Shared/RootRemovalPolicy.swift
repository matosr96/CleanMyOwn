//
//  RootRemovalPolicy.swift
//  CleanMyOwnShared
//
//  Allowlist de rutas borrables como root. Compartida entre la app (defensa
//  en el cliente) y el helper privilegiado (defensa en el servidor — el lado
//  que importa: el helper NUNCA confía en que el cliente ya validó).
//

import Foundation

public enum RootRemovalPolicy {
    /// Raíces bajo las que se permite borrar como root. Dos niveles:
    ///  - `containerRoots`: sólo descendientes ESTRICTOS (nunca la raíz misma).
    ///  - `exactRoots`: cachés dev regenerables — la raíz misma también es borrable.
    /// Coincide con lo que producen JunkScanService y AppCatalogService.
    public static func isAllowed(
        _ rawPath: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard rawPath.hasPrefix("/") else { return false }
        let url = URL(fileURLWithPath: rawPath)
        // Sin componentes relativos: nada de "." ni ".." en el path.
        let components = url.pathComponents
        guard !components.contains("..") && !components.contains(".") else { return false }
        let path = url.path
        guard path != "/" else { return false }

        let homePath = home.path

        let containerRoots = [
            homePath + "/Library",
            homePath + "/.Trash",
            homePath + "/Applications",
            "/Applications"
        ]
        for root in containerRoots where path != root && path.hasPrefix(root + "/") {
            return true
        }

        let exactRoots = [
            ".npm", ".yarn/cache",
            ".cargo/registry/cache", ".cargo/registry/src", ".rustup/downloads",
            ".gradle/caches", ".m2/repository", ".cocoapods/repos",
            ".bundle/cache", ".composer/cache",
            "go/pkg/mod/cache", ".pnpm-state"
        ].map { homePath + "/" + $0 }
        for root in exactRoots where path == root || path.hasPrefix(root + "/") {
            return true
        }
        return false
    }
}
