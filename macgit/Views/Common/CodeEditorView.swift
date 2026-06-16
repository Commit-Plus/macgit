//
//  CodeEditorView.swift
//  macgit
//

import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String
    let fontSize: CGFloat

    init(text: Binding<String>, fileExtension: String, fontSize: CGFloat = 12) {
        self._text = text
        self.fileExtension = fileExtension
        self.fontSize = fontSize
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.autoresizingMask = [.width, .height]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 8
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // Apply syntax highlighting
        applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = textView.string
        if currentText != text {
            textView.string = text
            applyHighlighting(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyHighlighting(to textView: NSTextView) {
        let highlighter = SyntaxHighlighter(fileExtension: fileExtension)
        let attributed = highlighter.attributedString(for: textView.string, fontSize: fontSize)
        let mutable = NSMutableAttributedString(attributed)
        textView.textStorage?.setAttributedString(mutable)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.applyHighlighting(to: textView)
        }
    }
}
