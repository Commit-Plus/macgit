//
//  SyntaxHighlighter.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation
import SwiftUI

@MainActor
struct SyntaxHighlighter {
    enum TokenType {
        case keyword
        case string
        case comment
        case number
        case type
        case attribute
        case normal
    }

    struct TokenRule {
        let regex: NSRegularExpression
        let type: TokenType
    }

    private static let keywordPattern: String = {
        let commonKeywords = Array(Set([
            "func", "var", "let", "if", "else", "for", "while", "return", "import", "class", "struct", "enum",
            "protocol", "extension", "init", "switch", "case", "default", "break", "continue", "in",
            "where", "typealias", "operator", "throws", "throw", "try", "catch", "do", "guard", "defer",
            "self", "Self", "super", "static", "final", "override", "open", "public", "internal", "private",
            "fileprivate", "weak", "inout", "await", "async", "actor", "some", "any", "macro",
            "const", "goto", "typedef", "union", "extern", "auto", "register", "volatile", "sizeof", "inline", "restrict",
            "function", "interface", "extends", "implements", "new", "this", "typeof", "instanceof", "of", "yield", "export", "from",
            "package", "namespace", "module", "protected", "abstract", "synchronized", "finally",
            "def", "elif", "as", "with", "except", "raise", "assert", "lambda",
            "nonlocal", "global", "pass", "del", "and", "or", "not", "is", "True", "False",
            "None", "match", "print", "println", "mut", "fn",
            "impl", "trait", "pub", "use", "mod", "crate", "unsafe",
            "move", "loop", "delete", "void"
        ]))
        return commonKeywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }()

    private static var rulesCache: [String: [TokenRule]] = [:]

    private let rules: [TokenRule]
    private let fileExtension: String

    init(fileExtension: String) {
        self.fileExtension = fileExtension.lowercased()
        self.rules = SyntaxHighlighter.rules(for: self.fileExtension)
    }

    func attributedString(for text: String, fontSize: CGFloat = 12) -> AttributedString {
        var attributed = AttributedString(text)

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        attributed.font = Font(baseFont)
        attributed.foregroundColor = .primary

        for (range, type) in mergedTokenRanges(in: text) {
            if let swiftRange = Range(range, in: text),
               let attrRange = convertRange(swiftRange, in: attributed) {
                if let color = tokenColor(for: type) {
                    attributed[attrRange].foregroundColor = Color(nsColor: color)
                }
            }
        }

        return attributed
    }

    func nsAttributedString(for text: String, fontSize: CGFloat = 12) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ]
        )

        for (range, type) in mergedTokenRanges(in: text) {
            guard NSMaxRange(range) <= NSMaxRange(fullRange),
                  let color = tokenColor(for: type) else {
                continue
            }
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    private func mergedTokenRanges(in text: String) -> [(NSRange, TokenType)] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var tokenRanges: [(NSRange, TokenType)] = []

        for rule in rules {
            for match in rule.regex.matches(in: text, range: fullRange) {
                let range = match.range
                if range.location != NSNotFound {
                    tokenRanges.append((range, rule.type))
                }
            }
        }

        tokenRanges.sort { $0.0.location < $1.0.location }

        var mergedRanges: [(NSRange, TokenType)] = []
        for (range, type) in tokenRanges {
            if let last = mergedRanges.last, NSIntersectionRange(last.0, range).length > 0 {
                if range.length > last.0.length {
                    mergedRanges[mergedRanges.count - 1] = (range, type)
                }
            } else {
                mergedRanges.append((range, type))
            }
        }
        return mergedRanges
    }

    private func tokenColor(for type: TokenType) -> NSColor? {
        switch type {
        case .keyword:
            NSColor(calibratedRed: 0.80, green: 0.35, blue: 0.60, alpha: 1.0)
        case .string:
            NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.20, alpha: 1.0)
        case .comment:
            NSColor(calibratedRed: 0.50, green: 0.50, blue: 0.50, alpha: 1.0)
        case .number:
            NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.75, alpha: 1.0)
        case .type:
            NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.70, alpha: 1.0)
        case .attribute:
            NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.20, alpha: 1.0)
        case .normal:
            nil
        }
    }

    private func convertRange(_ range: Range<String.Index>, in attributed: AttributedString) -> Range<AttributedString.Index>? {
        guard let start = AttributedString.Index(range.lowerBound, within: attributed),
              let end = AttributedString.Index(range.upperBound, within: attributed) else {
            return nil
        }
        return start..<end
    }

    private static func rules(for ext: String) -> [TokenRule] {
        if let cached = rulesCache[ext] {
            return cached
        }

        let patterns: [(String, TokenType)]

        switch ext {
        case "swift":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("@\\w+", .attribute),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "js", "ts", "jsx", "tsx", "json":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("`([^`\\\\\\\\]|\\\\\\\\.)*`", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "py":
            patterns = [
                ("#[^\n]*", .comment),
                ("\"\"\"[\\s\\S]*?\"\"\"", .string),
                ("'''[\\s\\S]*?'''", .string),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "c", "cpp", "h", "hpp", "m", "mm":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
                ("#\\w+", .attribute),
            ]
        case "go":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("`([^`\\\\\\\\]|\\\\\\\\.)*`", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "rs":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
                ("#\\w+", .attribute),
            ]
        case "java", "kt":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
                ("@\\w+", .attribute),
            ]
        case "sh", "bash", "zsh":
            patterns = [
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "yaml", "yml":
            patterns = [
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "sql":
            patterns = [
                ("--[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|CREATE|TABLE|INDEX|DROP|ALTER|ADD|COLUMN|VALUES|SET|AND|OR|NOT|NULL|IS|IN|BETWEEN|LIKE|EXISTS|CASE|WHEN|THEN|ELSE|END|AS|WITH|RECURSIVE|RETURNING|INTO|USING|NATURAL|CROSS|FULL|FETCH|FOR|OF|NOWAIT|SKIP|LOCKED|SHARE|KEY|PRIMARY|FOREIGN|REFERENCES|CONSTRAINT|CHECK|DEFAULT|UNIQUE|VIEW|TRIGGER|PROCEDURE|FUNCTION|DATABASE|SCHEMA|TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|GRANT|REVOKE|PRIVILEGES|TO|IDENTIFIED|PASSWORD|ACCOUNT|LOCK|UNLOCK|IF|CASCADE|RESTRICT)\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        default:
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(SyntaxHighlighter.keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        }

        let result: [TokenRule] = patterns.compactMap { pattern, type in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return TokenRule(regex: regex, type: type)
        }
        rulesCache[ext] = result
        return result
    }
}
