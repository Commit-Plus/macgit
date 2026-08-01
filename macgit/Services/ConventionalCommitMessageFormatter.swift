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

enum ConventionalCommitMessageFormatter {
    private static let knownTypes = [
        "feat", "fix", "refactor", "perf", "docs", "test", "build", "ci",
        "chore", "style", "revert",
    ]

    static func format(
        type: String,
        subject: String,
        body: String
    ) throws -> GeneratedCommitMessage {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard knownTypes.contains(normalizedType) else {
            throw CommitMessageGenerationError.invalidResponse
        }

        var normalizedSubject = subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        normalizedSubject = strippingExistingType(from: normalizedSubject)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSubject.hasSuffix(".") {
            normalizedSubject.removeLast()
        }

        let formattedSubject = "\(normalizedType): \(normalizedSubject)"
        guard !normalizedSubject.isEmpty, formattedSubject.count <= 100 else {
            throw CommitMessageGenerationError.invalidResponse
        }

        let normalizedBody = deduplicatedBody(
            body,
            subject: normalizedSubject,
            formattedSubject: formattedSubject
        )
        return GeneratedCommitMessage(
            subject: formattedSubject,
            body: normalizedBody.isEmpty ? nil : normalizedBody
        )
    }

    private static func strippingExistingType(from subject: String) -> String {
        guard let colonIndex = subject.firstIndex(of: ":") else { return subject }
        let prefix = subject[..<colonIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let baseType = prefix.split(separator: "(", maxSplits: 1).first.map(String.init) ?? prefix
        guard knownTypes.contains(baseType) else { return subject }
        return String(subject[subject.index(after: colonIndex)...])
    }

    private static func deduplicatedBody(
        _ body: String,
        subject: String,
        formattedSubject: String
    ) -> String {
        var lines = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)

        while let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.isEmpty || equivalent(first, subject) || equivalent(first, formattedSubject) {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        normalizedComparisonText(lhs) == normalizedComparisonText(rhs)
    }

    private static func normalizedComparisonText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

