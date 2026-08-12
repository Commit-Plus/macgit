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

    static func decode(from text: String) throws -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8) else {
            throw CommitMessageGenerationError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
    }

    func formatted() throws -> GeneratedCommitMessage {
        try ConventionalCommitMessageFormatter.format(type: type, subject: subject, body: body)
    }
}
