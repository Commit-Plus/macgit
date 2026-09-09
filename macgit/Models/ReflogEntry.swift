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

nonisolated struct ReflogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let hash: String
    let reference: String
    let date: Date?
    let actor: String
    let email: String
    let message: String
    let commitMessage: String

    var action: String { String(message.split(separator: ":", maxSplits: 1).first ?? "update") }
    var displayCommitMessage: String { commitMessage.isEmpty ? message : commitMessage }

    // A page can begin with an identical event from the previous page (same second,
    // hash and message). Continue occurrence IDs instead of dropping real events.
    static func appending(_ page: [ReflogEntry], to previous: [ReflogEntry]) -> [ReflogEntry] {
        var occurrences: [String: Int] = [:]
        for entry in previous {
            let key = String(entry.id[..<(entry.id.lastIndex(of: "#") ?? entry.id.endIndex)])
            occurrences[key, default: 0] += 1
        }
        let appended = page.map { entry in
            let key = String(entry.id[..<(entry.id.lastIndex(of: "#") ?? entry.id.endIndex)])
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return ReflogEntry(id: key + "#\(occurrence)", hash: entry.hash,
                               reference: entry.reference, date: entry.date,
                               actor: entry.actor, email: entry.email, message: entry.message,
                               commitMessage: entry.commitMessage)
        }
        return previous + appended
    }

    static func parse(_ output: String) -> [ReflogEntry] {
        let dateFormatter = ISO8601DateFormatter()
        var occurrences: [String: Int] = [:]
        let records: [String.SubSequence] = output.contains("\u{1e}")
            ? output.split(separator: "\u{1e}", omittingEmptySubsequences: true)
            : output.split(separator: "\n", omittingEmptySubsequences: true)
        return records.compactMap { record in
            let fields = record
                .trimmingCharacters(in: .newlines)
                .split(separator: "\0", omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 5 || fields.count == 6,
                  let marker = fields[1].range(of: "@{", options: .backwards),
                  fields[1].hasSuffix("}") else { return nil }
            let selector = fields[1]
            let dateText = String(selector[marker.upperBound..<selector.index(before: selector.endIndex)])
            let key = fields.joined(separator: "\0")
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return ReflogEntry(
                id: key + "#\(occurrence)", hash: fields[0],
                reference: String(selector[..<marker.lowerBound]),
                date: dateFormatter.date(from: dateText),
                actor: fields[2], email: fields[3], message: fields[4],
                commitMessage: fields.count == 6 ? fields[5].trimmingCharacters(in: .newlines) : ""
            )
        }
    }
}
