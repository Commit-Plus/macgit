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

nonisolated enum RepositoryAIAgentToolSchema {
    static let executeGitName = "execute_git"

    private static let gitParameters: [String: Any] = [
        "type": "object",
        "properties": [
            "arguments": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Git subcommand and arguments, without the git executable.",
            ],
        ],
        "required": ["arguments"],
        "additionalProperties": false,
    ]

    /// Gemini FunctionDeclaration accepts a narrower OpenAPI subset than the
    /// JSON Schema dialect used by the OpenAI-compatible tool adapters.
    private static let geminiGitParameters: [String: Any] = [
        "type": "object",
        "properties": [
            "arguments": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Git subcommand and arguments, without the git executable.",
            ],
        ],
        "required": ["arguments"],
    ]

    private static let emptyParameters: [String: Any] = [
        "type": "object",
        "properties": [:],
        "required": [],
        "additionalProperties": false,
    ]

    private static let geminiEmptyParameters: [String: Any] = [
        "type": "object",
        "properties": [:],
    ]

    static func declarations(
        includingQuickActions: Bool,
        forGemini: Bool = false,
        mutationContext: RepositoryAIMutationPlanningContext? = nil
    ) -> [[String: Any]] {
        let executeGit: [String: Any] = [
            "name": executeGitName,
            "description": "Run one bounded, read-only Git query in the current repository.",
            "parameters": forGemini ? geminiGitParameters : gitParameters,
        ]
        guard includingQuickActions else { return [executeGit] }
        let quickActions = RepositoryAIQuickAction.allCases.map { action in
            [
                "name": action.rawValue,
                "description": action.toolDescription,
                "parameters": forGemini ? geminiEmptyParameters : emptyParameters,
            ]
        }
        let mutations = mutationContext.map {
            mutationDeclarations(context: $0, forGemini: forGemini)
        } ?? []
        return [executeGit] + quickActions + mutations
    }

    static func arguments(
        forToolNamed name: String,
        suppliedArguments: [String]?
    ) -> [String]? {
        if name == executeGitName {
            suppliedArguments
        } else if RepositoryAIQuickAction(rawValue: name) != nil {
            []
        } else {
            suppliedArguments ?? []
        }
    }

    private static func mutationDeclarations(
        context: RepositoryAIMutationPlanningContext,
        forGemini: Bool
    ) -> [[String: Any]] {
        var declarations: [[String: Any]] = []
        if !context.stageablePaths.isEmpty {
            declarations.append(mutationDeclaration(
                name: "stage_files",
                description: "Propose staging exactly one or more eligible path IDs. Never use a path string or wildcard.",
                argumentDescription: "Eligible path IDs to stage.",
                allowedValues: context.stageablePaths.map(\.id),
                minimumCount: 1,
                maximumCount: context.stageablePaths.count,
                forGemini: forGemini
            ))
        }
        if !context.unstageablePaths.isEmpty {
            declarations.append(mutationDeclaration(
                name: "unstage_files",
                description: "Propose unstaging exactly one or more eligible staged path IDs while preserving working-tree bytes.",
                argumentDescription: "Eligible staged path IDs to unstage.",
                allowedValues: context.unstageablePaths.map(\.id),
                minimumCount: 1,
                maximumCount: context.unstageablePaths.count,
                forGemini: forGemini
            ))
            declarations.append(mutationDeclaration(
                name: "create_commit",
                description: "Propose one commit from the current index. The sole argument is the exact non-empty commit message. Do not add amend, force, signing, hook, or staging options.",
                argumentDescription: "Exactly one commit-message string.",
                minimumCount: 1,
                maximumCount: 1,
                forGemini: forGemini
            ))
        }
        if (try? RepositoryAIMutationPolicy.validateCommitAllPreparation(context: context)) != nil {
            declarations.append(mutationDeclaration(
                name: "commit_all_changes",
                description: "Use only when the user explicitly asks to commit all/every current change. Commit+ will automatically stage the complete eligible changed-file manifest, generate a message from the staged diff, and ask the user to confirm only the final commit. Pass no arguments.",
                argumentDescription: "An empty argument array. Commit+ owns the exact stage-all scope and commit-message generation.",
                minimumCount: 0,
                maximumCount: 0,
                forGemini: forGemini
            ))
        }
        if !context.startPoints.isEmpty {
            declarations.append(mutationDeclaration(
                name: "create_branch",
                description: "Propose creating one local branch without checkout. Arguments are exactly [newBranchName, suppliedStartPointID].",
                argumentDescription: "A valid new local branch name followed by one supplied start-point ID: \(context.startPoints.map(\.id).joined(separator: ", ")).",
                minimumCount: 2,
                maximumCount: 2,
                forGemini: forGemini
            ))
        }
        if context.repositoryState.branch != nil, context.isClean,
           !context.localBranches.isEmpty, context.inProgressOperation == nil {
            declarations.append(mutationDeclaration(
                name: "checkout_branch",
                description: "Propose checking out exactly one supplied existing local-branch ID. Never pass a ref or branch name directly.",
                argumentDescription: "Exactly one local-branch ID.",
                allowedValues: context.localBranches.map(\.id),
                minimumCount: 1,
                maximumCount: 1,
                forGemini: forGemini
            ))
        }
        if !context.conflictResolutions.isEmpty {
            declarations.append(mutationDeclaration(
                name: "apply_conflict_resolution",
                description: "Propose applying one current in-memory Commit+ Conflict AI resolution.",
                argumentDescription: "Exactly one supplied resolution ID.",
                allowedValues: context.conflictResolutions.map(\.id),
                minimumCount: 1,
                maximumCount: 1,
                forGemini: forGemini
            ))
        }
        declarations.append(mutationDeclaration(
            name: RepositoryAIMutationProposalDecoder.unsupportedToolName,
            description: "Use when the requested Git mutation is unsupported, unsafe, needs unavailable context, or requires more than one mutation. The sole argument is a concise explanation.",
            argumentDescription: "Exactly one user-facing reason.",
            minimumCount: 1,
            maximumCount: 1,
            forGemini: forGemini
        ))
        return declarations
    }

    private static func mutationDeclaration(
        name: String,
        description: String,
        argumentDescription: String,
        allowedValues: [String]? = nil,
        minimumCount: Int,
        maximumCount: Int,
        forGemini: Bool
    ) -> [String: Any] {
        var items: [String: Any] = ["type": "string"]
        if let allowedValues, !allowedValues.isEmpty {
            items["enum"] = allowedValues
        }
        var arguments: [String: Any] = [
            "type": "array",
            "items": items,
            "description": argumentDescription,
        ]
        if !forGemini {
            arguments["minItems"] = minimumCount
            arguments["maxItems"] = maximumCount
            arguments["uniqueItems"] = true
        }
        var parameters: [String: Any] = [
            "type": "object",
            "properties": ["arguments": arguments],
            "required": ["arguments"],
        ]
        if !forGemini {
            parameters["additionalProperties"] = false
        }
        return ["name": name, "description": description, "parameters": parameters]
    }
}
