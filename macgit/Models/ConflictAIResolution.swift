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

nonisolated enum ConflictAIResolutionAction: String, Codable, CaseIterable, Sendable {
    case current
    case incoming
    case bothCurrentFirst
    case bothIncomingFirst
    case replace
    case needsUser
}

nonisolated struct ConflictAISectionSnapshot: Equatable, Sendable {
    let sectionIndex: Int
    let contextBefore: String
    let currentText: String
    let incomingText: String
    let contextAfter: String
}

nonisolated struct ConflictAIFileSnapshot: Equatable, Sendable {
    let repositoryName: String
    let branchName: String?
    let filePath: String
    let fingerprint: String
    let baseContent: String?
    let currentContent: String
    let incomingContent: String
    let sections: [ConflictAISectionSnapshot]
    let isTruncated: Bool
}

nonisolated struct ConflictAILoadedFile: Equatable, Sendable {
    let file: StatusFile
    let document: ConflictResolutionDocument
    let snapshot: ConflictAIFileSnapshot
    let originalWorkingTreeText: String
}

nonisolated struct ConflictAIResolutionRequest: Sendable {
    let snapshot: ConflictAIFileSnapshot
}

nonisolated struct ConflictAIResolutionOption: Codable, Equatable, Sendable {
    let label: String
    let action: ConflictAIResolutionAction
    let replacementText: String

    private enum CodingKeys: String, CodingKey {
        case label
        case action
        case replacementText
    }

    init(label: String, action: ConflictAIResolutionAction, replacementText: String = "") {
        self.label = label
        self.action = action
        self.replacementText = replacementText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        action = try container.decode(ConflictAIResolutionAction.self, forKey: .action)
        replacementText = try container.decodeIfPresent(String.self, forKey: .replacementText) ?? ""
    }
}

nonisolated struct ConflictAIResolutionDecision: Codable, Equatable, Sendable {
    let sectionIndex: Int
    let action: ConflictAIResolutionAction
    let replacementText: String
    let reason: String
    let question: String
    let options: [ConflictAIResolutionOption]

    private enum CodingKeys: String, CodingKey {
        case sectionIndex
        case action
        case replacementText
        case reason
        case question
        case options
    }

    init(
        sectionIndex: Int,
        action: ConflictAIResolutionAction,
        replacementText: String = "",
        reason: String = "",
        question: String = "",
        options: [ConflictAIResolutionOption] = []
    ) {
        self.sectionIndex = sectionIndex
        self.action = action
        self.replacementText = replacementText
        self.reason = reason
        self.question = question
        self.options = options
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sectionIndex = try container.decode(Int.self, forKey: .sectionIndex)
        action = try container.decode(ConflictAIResolutionAction.self, forKey: .action)
        replacementText = try container.decodeIfPresent(String.self, forKey: .replacementText) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        options = try container.decodeIfPresent([ConflictAIResolutionOption].self, forKey: .options) ?? []
    }
}

nonisolated struct ConflictAIResolutionResponse: Codable, Equatable, Sendable {
    let decisions: [ConflictAIResolutionDecision]
    let summary: String

    private enum CodingKeys: String, CodingKey {
        case decisions
        case summary
    }

    init(decisions: [ConflictAIResolutionDecision], summary: String = "") {
        self.decisions = decisions
        self.summary = summary
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decisions = try container.decode([ConflictAIResolutionDecision].self, forKey: .decisions)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
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
        throw ConflictAIResolutionError.invalidResponse(
            "The AI provider did not return a valid conflict-resolution plan."
        )
    }

    private static func fencedJSON(in text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3,
              lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
            return nil
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private static func embeddedJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}

nonisolated struct ConflictAIUserQuestion: Identifiable, Equatable, Sendable {
    let filePath: String
    let sectionIndex: Int
    let question: String
    let reason: String
    let options: [ConflictAIResolutionOption]

    var id: String { "\(filePath):\(sectionIndex)" }
}

nonisolated struct ConflictAIFileFailure: Identifiable, Equatable, Sendable {
    let filePath: String
    let message: String

    var id: String { filePath }
}

nonisolated struct ConflictAIResolutionRunResult: Equatable, Sendable {
    let resolvedFilePaths: [String]
    let pendingQuestionCount: Int
    let failures: [ConflictAIFileFailure]
}

nonisolated enum ConflictAIResolutionError: LocalizedError, Equatable, Sendable {
    case unsupportedFile(String)
    case contextTooLarge(String)
    case invalidResponse(String)
    case staleFile(String)
    case incompletePlan(String)
    case unsafeReplacement(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let message),
             .contextTooLarge(let message),
             .invalidResponse(let message),
             .staleFile(let message),
             .incompletePlan(let message),
             .unsafeReplacement(let message):
            message
        }
    }
}
