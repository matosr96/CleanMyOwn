//
//  ThemeManager.swift
//  CleanMyOwn
//
//  Sistema de temas estándar de macOS: Sistema (sigue la apariencia del
//  Mac), Claro, Oscuro y Multicolor (la firma de la app: base oscura con
//  el lienzo vibrante a plena intensidad).
//
//  Las constantes de `Theme` leen la paleta activa de aquí, así que los
//  ~40 archivos que usan `Theme.x` se adaptan sin tocarse. El re-render
//  global lo fuerza ContentView con `.id(themeKey)`.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case multicolor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        case .multicolor: return "Multicolor"
        }
    }

    var blurb: String {
        switch self {
        case .system: return "Sigue la apariencia de tu Mac"
        case .light: return "Lienzo luminoso y suave"
        case .dark: return "Sobrio, con el fondo en calma"
        case .multicolor: return "La firma de la app: color a plena intensidad"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .multicolor: return "paintpalette.fill"
        }
    }

    /// Resolución pura (testeable): ¿este tema renderiza en base oscura?
    func resolvesDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .light: return false
        case .dark, .multicolor: return true
        case .system: return systemIsDark
        }
    }
}

/// Paleta resuelta — un valor por cada constante que antes era fija.
struct Palette {
    let isDark: Bool
    let background: Color
    let card: Color
    let cardHover: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    /// Base de las tintas "sobre superficie" (bordes, fills sutiles):
    /// blanco en oscuro, negro en claro.
    let onSurface: Color
    let shadow: Color
    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color
    let cardGradientTop: Color
    let cardGradientBottom: Color

    static let dark = Palette(
        isDark: true,
        background: Color(red: 0.07, green: 0.08, blue: 0.10),
        card: Color(red: 0.13, green: 0.14, blue: 0.18),
        cardHover: Color(red: 0.16, green: 0.17, blue: 0.22),
        textPrimary: .white,
        textSecondary: Color(white: 0.74),
        textTertiary: Color(white: 0.56),
        onSurface: .white,
        shadow: Color.black.opacity(0.35),
        accent: Color(red: 0.40, green: 0.55, blue: 1.0),
        success: Color(red: 0.30, green: 0.85, blue: 0.55),
        warning: Color(red: 1.0, green: 0.65, blue: 0.20),
        danger: Color(red: 1.0, green: 0.40, blue: 0.45),
        cardGradientTop: Color(red: 0.16, green: 0.17, blue: 0.22),
        cardGradientBottom: Color(red: 0.13, green: 0.14, blue: 0.18)
    )

    static let light = Palette(
        isDark: false,
        background: Color(red: 0.95, green: 0.95, blue: 0.97),
        card: Color(red: 0.89, green: 0.90, blue: 0.93),
        cardHover: Color(red: 0.85, green: 0.86, blue: 0.90),
        textPrimary: Color(red: 0.09, green: 0.10, blue: 0.13),
        textSecondary: Color(white: 0.32),
        textTertiary: Color(white: 0.46),
        onSurface: .black,
        shadow: Color.black.opacity(0.14),
        accent: Color(red: 0.32, green: 0.45, blue: 0.95),
        success: Color(red: 0.05, green: 0.62, blue: 0.36),
        warning: Color(red: 0.85, green: 0.50, blue: 0.02),
        danger: Color(red: 0.85, green: 0.22, blue: 0.28),
        cardGradientTop: Color(red: 0.99, green: 0.99, blue: 1.0),
        cardGradientBottom: Color(red: 0.94, green: 0.94, blue: 0.96)
    )
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "appTheme"

    @Published var selection: AppTheme {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: Self.storageKey) }
    }

    /// Apariencia actual de macOS (para el tema Sistema).
    @Published private(set) var systemIsDark: Bool

    private var observer: NSObjectProtocol?

    private init() {
        selection = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? "")
            ?? .multicolor
        systemIsDark = Self.readSystemIsDark()

        // macOS avisa por notificación distribuida cuando cambia la apariencia.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemIsDark = Self.readSystemIsDark()
            }
        }
    }

    private static func readSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    var resolvedDark: Bool { selection.resolvesDark(systemIsDark: systemIsDark) }

    var palette: Palette { resolvedDark ? .dark : .light }

    /// Para `.preferredColorScheme`: nil en Sistema (que decida macOS).
    var colorScheme: ColorScheme? {
        selection == .system ? nil : (resolvedDark ? .dark : .light)
    }

    /// Cambiar de tema reconstruye el árbol (las constantes de Theme son
    /// computadas — sin esto las vistas no se enterarían).
    var themeKey: String { "\(selection.rawValue)-\(resolvedDark ? "dark" : "light")" }

    // MARK: - Estilo del lienzo por tema

    var canvasIntensity: Double {
        switch selection {
        case .multicolor: return 0.55
        case .dark: return 0.16
        case .light: return 0.30
        case .system: return systemIsDark ? 0.35 : 0.30
        }
    }

    /// En Oscuro el lienzo queda en calma (sin teñirse por módulo).
    var canvasTintEnabled: Bool { selection != .dark }
}
