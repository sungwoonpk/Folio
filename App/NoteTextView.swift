import NoteCore
import SwiftUI
import UIKit

/// Lets the buttons in the editor header act on whichever text run has the cursor.
final class EditorController {
    weak var activeView: UITextView?
    var activeSegmentId: UUID?
    var activeIsFirst = false

    func toggleBullet() {
        guard let view = activeView else { return }
        NoteTextView.toggleBullets(in: view, isTitleRun: activeIsFirst)
    }

    /// Cursor position in the active run, or nil if nothing is being edited.
    var cursor: Int? { activeView?.selectedRange.location }
}

/// A run of text in a note. Grows with its content, so tables can sit between runs.
/// The first line of the first run is the title: bold and larger.
/// Bullet lines start with "• " and behave like a list.
struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    let segmentId: UUID
    let isFirst: Bool
    @Binding var focusRequest: UUID?
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.tintColor = Theme.accentUI
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 16
        view.typingAttributes = Style.body
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Only push text in when it changed from outside (loading, table insert).
        // Never touch it mid-composition, that breaks Korean/Japanese/Chinese input.
        if view.text != text, view.markedTextRange == nil {
            view.text = text
            Style.apply(to: view, isFirst: isFirst)
        }
        if focusRequest == segmentId, !view.isFirstResponder {
            DispatchQueue.main.async {
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: 0, length: 0)
                focusRequest = nil
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 44))
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextView
        weak var view: UITextView?

        init(_ parent: NoteTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ view: UITextView) {
            parent.controller.activeView = view
            parent.controller.activeSegmentId = parent.segmentId
            parent.controller.activeIsFirst = parent.isFirst
        }

        // MARK: Editing rules

        func textView(
            _ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
        ) -> Bool {
            guard view.markedTextRange == nil else { return true }
            let text = view.text as NSString
            let prefix = NoteDocument.bulletPrefix
            let prefixLength = (prefix as NSString).length

            // Return: continue the list, or end it on an empty bullet.
            if replacement == "\n" {
                let paragraph = text.paragraphRange(for: NSRange(location: min(range.location, text.length), length: 0))
                let line = Self.withoutLineBreak(text.substring(with: paragraph))
                guard line.hasPrefix(prefix), range.location >= paragraph.location + prefixLength else { return true }
                if line.count == prefix.count {
                    replace(NSRange(location: paragraph.location, length: prefixLength), with: "", in: view)
                } else {
                    view.insertText("\n" + prefix)
                }
                return false
            }

            // Backspace right after the bullet removes the bullet, not just its space.
            if replacement.isEmpty, range.length == 1 {
                let paragraph = text.paragraphRange(for: NSRange(location: min(range.location, text.length), length: 0))
                let line = text.substring(with: paragraph)
                if line.hasPrefix(prefix), range.location == paragraph.location + prefixLength - 1 {
                    replace(NSRange(location: paragraph.location, length: prefixLength), with: "", in: view)
                    return false
                }
            }
            return true
        }

        func textViewDidChange(_ view: UITextView) {
            if view.markedTextRange == nil {
                Style.apply(to: view, isFirst: parent.isFirst)
            } else {
                view.typingAttributes = Style.typingAttributes(for: view, isFirst: parent.isFirst)
            }
            parent.text = view.text
            scrollCaretIntoView(view)
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            // Keep the caret out of the bullet itself.
            let text = view.text as NSString
            let selection = view.selectedRange
            if selection.length == 0, text.length > 0 {
                let paragraph = text.paragraphRange(for: NSRange(location: min(selection.location, text.length), length: 0))
                let prefixLength = (NoteDocument.bulletPrefix as NSString).length
                if text.substring(with: paragraph).hasPrefix(NoteDocument.bulletPrefix),
                   selection.location > paragraph.location,
                   selection.location < paragraph.location + prefixLength {
                    view.selectedRange = NSRange(location: paragraph.location + prefixLength, length: 0)
                    return
                }
            }
            view.typingAttributes = Style.typingAttributes(for: view, isFirst: parent.isFirst)
            if view.isFirstResponder { scrollCaretIntoView(view) }
        }

        // MARK: Helpers

        private static func withoutLineBreak(_ line: String) -> String {
            var result = line
            while result.last?.isNewline == true { result.removeLast() }
            return result
        }

        private func replace(_ range: NSRange, with string: String, in view: UITextView) {
            NoteTextView.replace(range, with: string, in: view)
        }

        /// The text view does not scroll, its parent does. Keep the caret above the keyboard.
        private func scrollCaretIntoView(_ view: UITextView) {
            DispatchQueue.main.async {
                guard let range = view.selectedTextRange else { return }
                let caret = view.caretRect(for: range.end)
                var parent: UIView? = view.superview
                while let candidate = parent, !(candidate is UIScrollView) { parent = candidate.superview }
                guard let scroll = parent as? UIScrollView else { return }
                scroll.scrollRectToVisible(view.convert(caret, to: scroll).insetBy(dx: 0, dy: -28), animated: false)
            }
        }
    }

    // MARK: Bullet toggle, shared with the header button

    /// Edit through UIKit so undo and the delegate keep working.
    static func replace(_ range: NSRange, with string: String, in view: UITextView) {
        guard let start = view.position(from: view.beginningOfDocument, offset: range.location),
              let end = view.position(from: start, offset: range.length),
              let textRange = view.textRange(from: start, to: end) else { return }
        view.replace(textRange, withText: string)
    }

    /// Add bullets to the selected lines, or remove them if every line already has one.
    /// The title line never becomes a bullet.
    static func toggleBullets(in view: UITextView, isTitleRun: Bool) {
        let text = view.text as NSString
        let prefix = NoteDocument.bulletPrefix
        let block = text.paragraphRange(for: view.selectedRange)
        if isTitleRun, block.location == 0 { return }
        let original = text.substring(with: block)
        let hadBreak = original.last?.isNewline == true
        var core = original
        while core.last?.isNewline == true { core.removeLast() }
        let lines = core.components(separatedBy: "\n")
        let allBulleted = lines.allSatisfy { $0.hasPrefix(prefix) }
        let changed = lines.map { line -> String in
            if allBulleted { return String(line.dropFirst(prefix.count)) }
            return line.hasPrefix(prefix) ? line : prefix + line
        }
        let replacement = changed.joined(separator: "\n") + (hadBreak ? "\n" : "")
        replace(block, with: replacement, in: view)
        let end = block.location + (replacement as NSString).length - (hadBreak ? 1 : 0)
        view.selectedRange = NSRange(location: max(end, block.location), length: 0)
    }

    // MARK: Style

    enum Style {
        static func font(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            var descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            if bold, let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
                descriptor = boldDescriptor
            }
            return UIFont(descriptor: descriptor, size: 0)
        }

        private static func paragraph(indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            style.firstLineHeadIndent = 0
            style.headIndent = indent
            return style
        }

        /// Wrapped bullet lines line up with the text after the bullet.
        private static var bulletIndent: CGFloat {
            (NoteDocument.bulletPrefix as NSString).size(withAttributes: [.font: font(.body, bold: false)]).width
        }

        static var body: [NSAttributedString.Key: Any] {
            [.font: font(.body, bold: false), .foregroundColor: UIColor.label, .paragraphStyle: paragraph()]
        }

        static var bullet: [NSAttributedString.Key: Any] {
            [.font: font(.body, bold: false), .foregroundColor: UIColor.label, .paragraphStyle: paragraph(indent: bulletIndent)]
        }

        /// A step above body size, always bold.
        static var title: [NSAttributedString.Key: Any] {
            [.font: font(.title2, bold: true), .foregroundColor: UIColor.label, .paragraphStyle: paragraph()]
        }

        static func typingAttributes(for view: UITextView, isFirst: Bool) -> [NSAttributedString.Key: Any] {
            let text = view.text as NSString
            let location = min(view.selectedRange.location, text.length)
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            if isFirst, paragraph.location == 0 { return title }
            if text.substring(with: paragraph).hasPrefix(NoteDocument.bulletPrefix) { return bullet }
            return body
        }

        /// Restyle the run: title first (first run only), bullet lines indented, the rest body.
        static func apply(to view: UITextView, isFirst: Bool) {
            let text = view.text as NSString
            let storage = view.textStorage
            let selection = view.selectedRange
            storage.beginEditing()
            storage.setAttributes(body, range: NSRange(location: 0, length: text.length))
            var index = 0
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) {
                substring, range, enclosing, _ in
                if isFirst, index == 0 {
                    storage.setAttributes(title, range: enclosing)
                } else if let substring, substring.hasPrefix(NoteDocument.bulletPrefix) {
                    storage.setAttributes(bullet, range: enclosing)
                    storage.addAttribute(.foregroundColor, value: Theme.accentUI, range: NSRange(location: range.location, length: 1))
                }
                index += 1
            }
            storage.endEditing()
            view.selectedRange = selection
            view.typingAttributes = typingAttributes(for: view, isFirst: isFirst)
        }
    }
}
