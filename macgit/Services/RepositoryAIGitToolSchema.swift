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
        forGemini: Bool = false
    ) -> [[String: Any]] {
        let executeGit: [String: Any] = [
            "name": executeGitName,
            "description": "Run one bounded, read-only Git query in the current repository.",
            "parameters": forGemini ? geminiGitParameters : gitParameters,
        ]
        guard includingQuickActions else { return [executeGit] }
        return [executeGit] + RepositoryAIQuickAction.allCases.map { action in
            [
                "name": action.rawValue,
                "description": action.toolDescription,
                "parameters": forGemini ? geminiEmptyParameters : emptyParameters,
            ]
        }
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
}
