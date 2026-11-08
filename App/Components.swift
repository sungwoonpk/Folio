import SwiftUI

/// Column navigation state. We draw our own headers, so we also drive back and sidebar toggles.
@MainActor @Observable
final class Nav {
    var columns: NavigationSplitViewVisibility = .automatic
    var compactColumn: NavigationSplitViewColumn = .content
}

/// Plain icon button. No circle, no glass.
struct IconButton: View {
    let systemName: String
    var label: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? systemName : label)
    }
}

/// One header for every screen: back or sidebar toggle on the left,
/// all actions together on the right, title below.
struct Header<Actions: View>: View {
    let title: String
    var leading: (icon: String, label: String, action: () -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let leading {
                    IconButton(systemName: leading.icon, label: leading.label, action: leading.action)
                }
                Spacer()
                actions()
            }
            .foregroundStyle(Theme.accent)
            if !title.isEmpty {
                Text(title)
                    .font(Theme.serifTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
