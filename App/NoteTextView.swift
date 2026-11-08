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
        NoteTextView.toggleList(.bullet, in: view, isTitleRun: activeIsFirst)
    }

    func toggleChecklist() {
        guard let view = activeView else { return }
        NoteTextView.toggleList(.checklist, in: view, isTitleRun: activeIsFirst)
    }

    /// Cursor position in the active run, or nil if nothing is being edited.
    var cursor: Int? { activeView?.selectedRange.location }
}

/// Text view that can tell whether a touch landed on a checklist box.
final class NoteUITextView: UITextView {
    /// Where the latest touch began, so we can refuse to start editing when it hit a box.
    var touchStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = touches.first?.location(in: self)
        super.touchesBegan(touches, with: event)
    }

    /// The box character under a point, if the point is on a checklist box.
    func checkboxRange(at point: CGPoint) -> NSRange? {
        let text = self.text as NSString
        guard text.length > 0, let position = closestPosition(to: point) else { return nil }
        let offset = self.offset(from: beginningOfDocument, to: position)
        let paragraph = text.paragraphRange(for: NSRange(location: min(offset, text.length), length: 0))
        let line = text.substring(with: paragraph)
        guard line.hasPrefix(NoteDocument.uncheckedPrefix) || line.hasPrefix(NoteDocument.checkedPrefix),
              let start = self.position(from: beginningOfDocument, offset: paragraph.location),
              let end = self.position(from: start, offset: 1),
              let range = textRange(from: start, to: end) else { return nil }
        let box = firstRect(for: range).insetBy(dx: -16, dy: -12)
        return box.contains(point) ? NSRange(location: paragraph.location, length: 1) : nil
    }
}

/// A run of text in a note. Grows with its content, so tables can sit between runs.
/// The first line of the first run is the title: bold and larger.
/// Bullet lines start with "• ", checklist lines with "○ " or "◉ ". They behave like lists:
/// Return continues them, Return on an empty one ends the list, tapping a box checks it.
struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    let segmentId: UUID
    let isFirst: Bool
    @Binding var focusRequest: UUID?
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = NoteUITextView()
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
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

        /// A touch on a checklist box toggles it and does not open the keyboard.
        func textViewShouldBeginEditing(_ view: UITextView) -> Bool {
            guard let view = view as? NoteUITextView, let point = view.touchStart else { return true }
            return view.checkboxRange(at: point) == nil
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? NoteUITextView,
                  let range = view.checkboxRange(at: gesture.location(in: view)) else { return }
            let text = view.text as NSString
            let done = String(NoteDocument.checkedPrefix.prefix(1))
            let open = String(NoteDocument.uncheckedPrefix.prefix(1))
            let isDone = text.substring(with: range) == done
            view.textStorage.replaceCharacters(in: range, with: isDone ? open : done)
            textViewDidChange(view)
        }

        func textView(
            _ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
        ) -> Bool {
            guard view.markedTextRange == nil else { return true }
            let text = view.text as NSString

            // Return: continue the list, or end it on an empty item.
            if replacement == "\n" {
                let paragraph = text.paragraphRange(for: NSRange(location: min(range.location, text.length), length: 0))
                let line = Self.withoutLineBreak(text.substring(with: paragraph))
                guard let prefix = NoteTextView.listPrefix(of: line),
                      range.location >= paragraph.location + (prefix as NSString).length else { return true }
                if line.count == prefix.count {
                    replace(NSRange(location: paragraph.location, length: (prefix as NSString).length), with: "", in: view)
                } else {
                    view.insertText("\n" + NoteTextView.continuation(of: prefix))
                }
                return false
            }

            // Backspace right after the marker removes the whole marker, not just its space.
            if replacement.isEmpty, range.length == 1 {
                let paragraph = text.paragraphRange(for: NSRange(location: min(range.location, text.length), length: 0))
                let line = text.substring(with: paragraph)
                if let prefix = NoteTextView.listPrefix(of: line),
                   range.location == paragraph.location + (prefix as NSString).length - 1 {
                    replace(NSRange(location: paragraph.location, length: (prefix as NSString).length), with: "", in: view)
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
            // Keep the caret out of the marker itself.
            let text = view.text as NSString
            let selection = view.selectedRange
            if selection.length == 0, text.length > 0 {
                let paragraph = text.paragraphRange(for: NSRange(location: min(selection.location, text.length), length: 0))
                if let prefix = NoteTextView.listPrefix(of: text.substring(with: paragraph)) {
                    let markerEnd = paragraph.location + (prefix as NSString).length
                    if selection.location > paragraph.location, selection.location < markerEnd {
                        view.selectedRange = NSRange(location: markerEnd, length: 0)
                        return
                    }
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

    // MARK: Lists, shared with the header buttons

    /// Edit through UIKit so undo and the delegate keep working.
    static func replace(_ range: NSRange, with string: String, in view: UITextView) {
        guard let start = view.position(from: view.beginningOfDocument, offset: range.location),
              let end = view.position(from: start, offset: range.length),
              let textRange = view.textRange(from: start, to: end) else { return }
        view.replace(textRange, withText: string)
    }

    enum ListKind {
        case bullet, checklist

        var prefix: String {
            self == .bullet ? NoteDocument.bulletPrefix : NoteDocument.uncheckedPrefix
        }

        func matches(_ line: String) -> Bool {
            switch self {
            case .bullet: line.hasPrefix(NoteDocument.bulletPrefix)
            case .checklist: line.hasPrefix(NoteDocument.uncheckedPrefix) || line.hasPrefix(NoteDocument.checkedPrefix)
            }
        }
    }

    /// The list marker a line starts with, if any.
    static func listPrefix(of line: String) -> String? {
        NoteDocument.listPrefixes.first { line.hasPrefix($0) }
    }

    /// What the next line starts with after Return on a list line: checklists restart unchecked.
    static func continuation(of prefix: String) -> String {
        prefix == NoteDocument.bulletPrefix ? NoteDocument.bulletPrefix : NoteDocument.uncheckedPrefix
    }

    /// Turn the selected lines into a list, or back into plain text if they all are one already.
    /// Switching between bullets and checklist just swaps the marker. The title line is never a list.
    static func toggleList(_ kind: ListKind, in view: UITextView, isTitleRun: Bool) {
        let text = view.text as NSString
        let block = text.paragraphRange(for: view.selectedRange)
        if isTitleRun, block.location == 0 { return }
        let original = text.substring(with: block)
        let hadBreak = original.last?.isNewline == true
        var core = original
        while core.last?.isNewline == true { core.removeLast() }
        let lines = core.components(separatedBy: "\n")
        let allInList = lines.allSatisfy { kind.matches($0) }
        let changed = lines.map { line -> String in
            let bare = listPrefix(of: line).map { String(line.dropFirst($0.count)) } ?? line
            if allInList { return bare }
            return kind.matches(line) ? line : kind.prefix + bare
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

        /// Wrapped list lines line up with the text after the marker.
        private static func indent(for prefix: String) -> CGFloat {
            (prefix as NSString).size(withAttributes: [.font: font(.body, bold: false)]).width
        }

        static var body: [NSAttributedString.Key: Any] {
            [.font: font(.body, bold: false), .foregroundColor: UIColor.label, .paragraphStyle: paragraph()]
        }

        /// Body text hanging after a list marker.
        static func listLine(prefix: String) -> [NSAttributedString.Key: Any] {
            [.font: font(.body, bold: false), .foregroundColor: UIColor.label, .paragraphStyle: paragraph(indent: indent(for: prefix))]
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
            if let prefix = NoteTextView.listPrefix(of: text.substring(with: paragraph)) { return listLine(prefix: prefix) }
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
                } else if let substring, let prefix = NoteTextView.listPrefix(of: substring) {
                    storage.setAttributes(listLine(prefix: prefix), range: enclosing)
                    // The marker is a small brown detail.
                    storage.addAttribute(.foregroundColor, value: Theme.accentUI, range: NSRange(location: range.location, length: 1))
                    // Checked items are crossed out and softer.
                    if prefix == NoteDocument.checkedPrefix {
                        let length = (prefix as NSString).length
                        let content = NSRange(location: range.location + length, length: max(range.length - length, 0))
                        storage.addAttributes([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: UIColor.secondaryLabel,
                        ], range: content)
                    }
                }
                index += 1
            }
            storage.endEditing()
            view.selectedRange = selection
            view.typingAttributes = typingAttributes(for: view, isFirst: isFirst)
        }
    }
}
