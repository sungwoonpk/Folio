import SwiftUI

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
    static let trashDays = "trashDays"
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
    static let accent = Color(red: 0.93, green: 0.69, blue: 0.0)
}
