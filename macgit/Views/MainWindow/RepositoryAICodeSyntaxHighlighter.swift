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

import MarkdownUI
import SwiftUI

struct RepositoryAICodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ content: String, language: String?) -> Text {
        let highlighter = SyntaxHighlighter(
            fileExtension: Self.normalizedLanguage(language)
        )
        return Text(highlighter.attributedString(for: content, fontSize: 12))
    }

    private static func normalizedLanguage(_ language: String?) -> String {
        let identifier = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        return switch identifier {
        case "javascript", "node", "nodejs":
            "js"
        case "typescript":
            "ts"
        case "python":
            "py"
        case "shell", "console":
            "sh"
        case "objective-c", "objc":
            "m"
        case "objective-c++", "objc++":
            "mm"
        case "c++":
            "cpp"
        case "kotlin":
            "kt"
        case "rust":
            "rs"
        default:
            identifier
        }
    }
}
