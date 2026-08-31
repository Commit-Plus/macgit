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

nonisolated struct ConflictAIPlanApplication: Equatable, Sendable {
    var document: ConflictResolutionDocument
    let questions: [ConflictAIUserQuestion]
}

nonisolated enum ConflictAIResolutionPlanApplier {
    static func apply(
        _ response: ConflictAIResolutionResponse,
        to document: ConflictResolutionDocument,
        filePath: String
    ) throws -> ConflictAIPlanApplication {
        let expectedIndices = Set(
            document.sections.indices.filter { document.sections[$0].isConflict }
        )
        let suppliedIndices = response.decisions.map(\.sectionIndex)
        guard Set(suppliedIndices) == expectedIndices,
              Set(suppliedIndices).count == suppliedIndices.count else {
            throw ConflictAIResolutionError.incompletePlan(
                "AI returned missing, duplicate, or unknown conflict decisions for \(filePath)."
            )
        }

        var resolvedDocument = document
        resolvedDocument.manualResolvedText = nil
        var questions: [ConflictAIUserQuestion] = []

        for decision in response.decisions {
            guard resolvedDocument.sections.indices.contains(decision.sectionIndex),
                  resolvedDocument.sections[decision.sectionIndex].isConflict else {
                throw ConflictAIResolutionError.incompletePlan(
                    "AI referenced an invalid conflict section in \(filePath)."
                )
            }

            if decision.action == .needsUser {
                let question = try validatedQuestion(from: decision, filePath: filePath)
                questions.append(question)
                continue
            }
            try apply(
                action: decision.action,
                replacementText: decision.replacementText,
                to: &resolvedDocument.sections[decision.sectionIndex],
                filePath: filePath
            )
        }

        return ConflictAIPlanApplication(document: resolvedDocument, questions: questions)
    }

    static func apply(
        _ option: ConflictAIResolutionOption,
        to document: inout ConflictResolutionDocument,
        sectionIndex: Int,
        filePath: String
    ) throws {
        guard document.sections.indices.contains(sectionIndex),
              document.sections[sectionIndex].isConflict else {
            throw ConflictAIResolutionError.incompletePlan(
                "The selected AI option no longer matches \(filePath)."
            )
        }
        try apply(
            action: option.action,
            replacementText: option.replacementText,
            to: &document.sections[sectionIndex],
            filePath: filePath
        )
        document.manualResolvedText = nil
    }

    private static func validatedQuestion(
        from decision: ConflictAIResolutionDecision,
        filePath: String
    ) throws -> ConflictAIUserQuestion {
        let question = decision.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, decision.options.count >= 2 else {
            throw ConflictAIResolutionError.incompletePlan(
                "AI could not resolve a section in \(filePath) but did not provide actionable options."
            )
        }
        for option in decision.options {
            let label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, option.action != .needsUser else {
                throw ConflictAIResolutionError.incompletePlan(
                    "AI returned an invalid user option for \(filePath)."
                )
            }
            if option.action == .replace {
                try validateReplacement(option.replacementText, filePath: filePath)
            }
        }
        return ConflictAIUserQuestion(
            filePath: filePath,
            sectionIndex: decision.sectionIndex,
            question: question,
            reason: decision.reason,
            options: decision.options
        )
    }

    private static func apply(
        action: ConflictAIResolutionAction,
        replacementText: String,
        to section: inout ConflictResolutionSection,
        filePath: String
    ) throws {
        section.manualResult = ""
        switch action {
        case .current:
            section.resolution = .current
        case .incoming:
            section.resolution = .incoming
        case .bothCurrentFirst:
            section.resolution = .both
        case .bothIncomingFirst:
            section.resolution = .bothIncomingFirst
        case .replace:
            try validateReplacement(replacementText, filePath: filePath)
            section.resolution = .manual
            section.manualResult = replacementText
        case .needsUser:
            throw ConflictAIResolutionError.incompletePlan(
                "AI left an unanswered decision in \(filePath)."
            )
        }
    }

    private static func validateReplacement(_ replacementText: String, filePath: String) throws {
        guard !replacementText.isEmpty else {
            throw ConflictAIResolutionError.unsafeReplacement(
                "AI returned an empty replacement for \(filePath)."
            )
        }
        let hasMarkers = replacementText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { line in
                line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>")
            }
        guard !hasMarkers, !replacementText.hasPrefix("```") else {
            throw ConflictAIResolutionError.unsafeReplacement(
                "AI returned unsafe replacement text for \(filePath)."
            )
        }
    }
}
