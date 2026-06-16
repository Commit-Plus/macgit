//
//  CodeBlockView.swift
//  macgit
//

import SwiftUI

struct CodeBlockView: View {
    let text: String
    let fileExtension: String
    let fontSize: CGFloat

    init(text: String, fileExtension: String, fontSize: CGFloat = 12) {
        self.text = text
        self.fileExtension = fileExtension
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(spacing: 0) {
            lineNumberGutter
            highlightedText
        }
    }

    private var lineNumberGutter: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<lines.count, id: \.self) { index in
                Text("\(index + 1)")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.05))
    }

    private var highlightedText: some View {
        let highlighter = SyntaxHighlighter(fileExtension: fileExtension)
        let attributed = highlighter.attributedString(for: text, fontSize: fontSize)
        return Text(attributed)
            .textSelection(.enabled)
            .lineSpacing(2)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
    }
}
