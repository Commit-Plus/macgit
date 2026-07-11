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
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let macgitGitDragPayload = UTType(exportedAs: "dev.thanhtran.commitplus.git-drag-payload")
}

nonisolated struct GitDraggedCommit: Codable, Hashable, Sendable {
    let hash: String
    let message: String
    let isMerge: Bool
}

nonisolated struct GitDragPayload: Codable, Hashable, Sendable, Transferable {
    enum Content: Codable, Hashable, Sendable {
        case commits([GitDraggedCommit])
        case branch(String)
        case remoteBranch(String)
        case files([String])
        case stash(String)
    }

    let repositoryPath: String
    let content: Content

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .macgitGitDragPayload)
    }

    nonisolated static func encodeTransferData(_ payload: GitDragPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    nonisolated static func decodeTransferData(_ data: Data) throws -> GitDragPayload {
        try JSONDecoder().decode(GitDragPayload.self, from: data)
    }

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func commits(_ commits: [GitDraggedCommit], repositoryURL: URL) -> GitDragPayload {
        GitDragPayload(
            repositoryPath: normalizedPath(repositoryURL),
            content: .commits(commits)
        )
    }

    static func branch(_ branch: String, repositoryURL: URL) -> GitDragPayload {
        GitDragPayload(
            repositoryPath: normalizedPath(repositoryURL),
            content: .branch(branch)
        )
    }

    static func remoteBranch(_ remoteBranch: String, repositoryURL: URL) -> GitDragPayload {
        GitDragPayload(
            repositoryPath: normalizedPath(repositoryURL),
            content: .remoteBranch(remoteBranch)
        )
    }

    static func files(_ paths: [String], repositoryURL: URL) -> GitDragPayload {
        GitDragPayload(
            repositoryPath: normalizedPath(repositoryURL),
            content: .files(paths)
        )
    }

    static func stash(_ ref: String, repositoryURL: URL) -> GitDragPayload {
        GitDragPayload(
            repositoryPath: normalizedPath(repositoryURL),
            content: .stash(ref)
        )
    }

    nonisolated var commits: [GitDraggedCommit] {
        content.commitsValue ?? []
    }

    nonisolated var branch: String? {
        content.branchValue
    }

    nonisolated var remoteBranch: String? {
        content.remoteBranchValue
    }

    nonisolated var files: [String] {
        content.filesValue ?? []
    }

    nonisolated var stash: String? {
        content.stashValue
    }
}

extension GitDragPayload.Content {
    nonisolated var commitsValue: [GitDraggedCommit]? {
        guard case .commits(let commits) = self else {
            return nil
        }
        return commits
    }

    nonisolated var branchValue: String? {
        guard case .branch(let branch) = self else {
            return nil
        }
        return branch
    }

    nonisolated var remoteBranchValue: String? {
        guard case .remoteBranch(let remoteBranch) = self else {
            return nil
        }
        return remoteBranch
    }

    nonisolated var filesValue: [String]? {
        guard case .files(let files) = self else {
            return nil
        }
        return files
    }

    nonisolated var stashValue: String? {
        guard case .stash(let stash) = self else {
            return nil
        }
        return stash
    }
}

nonisolated enum GitDragTarget: Equatable, Sendable {
    case localBranch(name: String, isCurrent: Bool)
    case branchesHeader
    case tagsHeader
    case remotesHeader
    case stashesHeader
    case fileStatus
}

nonisolated enum GitBranchStartPoint: Equatable, Sendable {
    case commit(hash: String, message: String)
    case branch(String)
}

nonisolated enum GitDragBranchOperation: Equatable, Sendable {
    case merge
    case rebase
}

nonisolated enum GitDragDropRequest: Equatable, Sendable {
    case cherryPick(commits: [GitDraggedCommit], targetBranch: String)
    case createBranch(startPoint: GitBranchStartPoint)
    case checkoutRemoteBranch(String)
    case createTagFromBranch(String)
    case pushBranchToRemote(String)
    case branchOperation(source: String, target: String, operation: GitDragBranchOperation)
    case stashFiles(paths: [String])
    case applyStash(ref: String)
}

nonisolated enum GitDragDropDecision: Equatable, Sendable {
    case accept(GitDragDropRequest)
    case reject(String)
}
