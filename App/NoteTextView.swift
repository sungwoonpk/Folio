import SwiftUI
import UIKit

/// Text editor where the first line is the title: bold and larger. Everything else is body text.
struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    var autofocus: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.tintColor = Theme.accentUI
        view.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 32, right: 16)
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.typingAttributes = Style.body
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Only push text in when it changed from outside (loading a note).
        // Never touch it mid-composition, that breaks Korean/Japanese/Chinese input.
        if view.text != text, view.markedTextRange == nil {
            view.text = text
            Style.apply(to: view)
        }
        if autofocus, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView
        var didFocus = false

        init(_ parent: NoteTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            if view.markedTextRange == nil {
                Style.apply(to: view)
            } else {
                view.typingAttributes = Style.typingAttributes(at: view.selectedRange.location, in: view.text)
            }
            parent.text = view.text
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            view.typingAttributes = Style.typingAttributes(at: view.selectedRange.location, in: view.text)
        }
    }

    enum Style {
        static func font(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            var descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            if bold, let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
                descriptor = boldDescriptor
            }
            return UIFont(descriptor: descriptor, size: 0)
        }

        private static var paragraph: NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return style
        }

        static var body: [NSAttributedString.Key: Any] {
            [.font: font(.body, bold: false), .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        }

        /// A step above body size, always bold.
        static var title: [NSAttributedString.Key: Any] {
            [.font: font(.title2, bold: true), .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        }

        /// End of the first line, not counting its line break.
        private static func titleEnd(in text: NSString) -> Int {
            guard text.length > 0 else { return 0 }
            let line = text.lineRange(for: NSRange(location: 0, length: 0))
            var end = line.length
            while end > 0, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
            return end
        }

        static func typingAttributes(at location: Int, in text: String) -> [NSAttributedString.Key: Any] {
            location <= titleEnd(in: text as NSString) ? title : body
        }

        /// Restyle the whole note: first line title, the rest body.
        static func apply(to view: UITextView) {
            let text = view.text as NSString
            let storage = view.textStorage
            let selection = view.selectedRange
            storage.beginEditing()
            storage.setAttributes(body, range: NSRange(location: 0, length: text.length))
            if text.length > 0 {
                let line = text.lineRange(for: NSRange(location: 0, length: 0))
                storage.setAttributes(title, range: line)
            }
            storage.endEditing()
            view.selectedRange = selection
            view.typingAttributes = typingAttributes(at: selection.location, in: view.text)
        }
    }
}
