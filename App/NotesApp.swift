import SwiftUI
import UIKit

@main
struct NotesApp: App {
    @State private var model = AppModel()
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }
}

enum SettingsKey {
    static let appearance = "appearance"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    /// nil follows the phone setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Theme {
    /// Soft caramel brown. Lighter in dark mode so it stays readable.
    static let accentUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.80, green: 0.65, blue: 0.50, alpha: 1)
            : UIColor(red: 0.66, green: 0.49, blue: 0.34, alpha: 1)
    }
    static let accent = Color(uiColor: accentUI)

    /// Pure white in light mode, pure black in dark mode. Text is black and white to match.
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })

    /// Corner radius for cards, fields and highlights. Soft, not round.
    static let corner: CGFloat = 12
    /// Faint fill that makes a row read as a button.
    static let card = Color.primary.opacity(0.06)

    static let serifBody = Font.system(.body, design: .serif)
    static let serifTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let meta = Font.system(.caption, design: .monospaced)
}
