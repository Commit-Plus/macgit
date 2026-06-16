//
//  SyntaxHighlighter.swift
//  macgit
//

import Foundation
import SwiftUI

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

    private let rules: [TokenRule]
    private let fileExtension: String

    init(fileExtension: String) {
        self.fileExtension = fileExtension.lowercased()
        self.rules = SyntaxHighlighter.rules(for: self.fileExtension)
    }

    func attributedString(for text: String, fontSize: CGFloat = 12) -> AttributedString {
        var attributed = AttributedString(text)
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        attributed.font = Font(baseFont)
        attributed.foregroundColor = .primary

        var tokenRanges: [(NSRange, TokenType)] = []

        for rule in rules {
            let matches = rule.regex.matches(in: text, range: fullRange)
            for match in matches {
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

        for (range, type) in mergedRanges {
            if let swiftRange = Range(range, in: text) {
                let attrRange = convertRange(swiftRange, in: attributed)
                switch type {
                case .keyword:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.80, green: 0.35, blue: 0.60, alpha: 1.0))
                case .string:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.20, alpha: 1.0))
                case .comment:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.50, green: 0.50, blue: 0.50, alpha: 1.0))
                case .number:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.75, alpha: 1.0))
                case .type:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.70, alpha: 1.0))
                case .attribute:
                    attributed[attrRange].foregroundColor = Color(nsColor: NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.20, alpha: 1.0))
                case .normal:
                    break
                }
            }
        }

        return attributed
    }

    private func convertRange(_ range: Range<String.Index>, in attributed: AttributedString) -> Range<AttributedString.Index> {
        let start = AttributedString.Index(range.lowerBound, within: attributed)!
        let end = AttributedString.Index(range.upperBound, within: attributed)!
        return start..<end
    }

    private static func rules(for ext: String) -> [TokenRule] {
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
            "move", "loop", "delete", "void", "with"
        ]))
        let keywordPattern = commonKeywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let patterns: [(String, TokenType)]

        switch ext {
        case "swift":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("#\\[.*\\]", .attribute),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
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
                ("\\b(?:\(keywordPattern))\\b", .keyword),
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
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "c", "cpp", "h", "hpp", "m", "mm":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
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
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "rs":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
                ("#\\w+", .attribute),
            ]
        case "java", "kt":
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b[A-Z][A-Za-z0-9_]*\\b", .type),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
                ("@\\w+", .attribute),
            ]
        case "sh", "bash", "zsh":
            patterns = [
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "yaml", "yml":
            patterns = [
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        case "sql":
            patterns = [
                ("--[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|CREATE|TABLE|INDEX|DROP|ALTER|ADD|COLUMN|VALUES|SET|AND|OR|NOT|NULL|IS|IN|BETWEEN|LIKE|EXISTS|CASE|WHEN|THEN|ELSE|END|AS|WITH|RECURSIVE|RETURNING|INTO|USING|NATURAL|CROSS|FULL|FETCH|FOR|UPDATE|OF|NOWAIT|SKIP|LOCKED|SHARE|KEY|PRIMARY|FOREIGN|REFERENCES|CONSTRAINT|CHECK|DEFAULT|UNIQUE|VIEW|TRIGGER|PROCEDURE|FUNCTION|DATABASE|SCHEMA|TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|GRANT|REVOKE|PRIVILEGES|TO|IDENTIFIED|BY|PASSWORD|ACCOUNT|LOCK|UNLOCK|IF|EXISTS|CASCADE|RESTRICT)\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        default:
            patterns = [
                ("//[^\n]*", .comment),
                ("/\\*[\\s\\S]*?\\*/", .comment),
                ("#[^\n]*", .comment),
                ("\"([^\"\\\\\\\\]|\\\\\\\\.)*\"", .string),
                ("'([^'\\\\\\\\]|\\\\\\\\.)*'", .string),
                ("\\b(?:\(keywordPattern))\\b", .keyword),
                ("\\b\\d+(\\.\\d+)?\\b", .number),
            ]
        }

        return patterns.compactMap { pattern, type in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return TokenRule(regex: regex, type: type)
        }
    }
}
