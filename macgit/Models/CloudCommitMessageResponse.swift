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

struct CloudCommitMessageResponse: Decodable, Sendable {
    let type: String
    let subject: String
    let body: String

    private enum CodingKeys: String, CodingKey {
        case type
        case subject
        case body
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        subject = try container.decode(String.self, forKey: .subject)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    }

    static func decode(from text: String) throws -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, fencedJSON(in: trimmed), embeddedJSONObject(in: trimmed)]
            .compactMap { $0 }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let response = try? JSONDecoder().decode(Self.self, from: data) {
                return response
            }
        }
        throw CommitMessageGenerationError.invalidResponse
    }

    func formatted() throws -> GeneratedCommitMessage {
        try ConventionalCommitMessageFormatter.format(type: type, subject: subject, body: body)
    }

    private static func fencedJSON(in text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
            return nil
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private static func embeddedJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(text[start...end])
    }
}
