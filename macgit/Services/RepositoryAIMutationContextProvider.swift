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

nonisolated struct RepositoryAIMutationPlanningContext: Equatable, Sendable {
    let repositoryIdentity: String
    let repositoryState: RepositoryAIRepositoryState
    let status: GitStatus
    let paths: [RepositoryAIMutationPath]
    let localBranches: [RepositoryAIMutationRef]
    let startPoints: [RepositoryAIMutationRef]
    let conflictResolutions: [RepositoryAIConflictResolutionManifest]
    let stagedStatistics: RepositoryAIMutationStatistics
    let author: String?
    let signingEnabled: Bool
    let inProgressOperation: String?
    let branchesCheckedOutInOtherWorktrees: Set<String>

    var stageablePaths: [RepositoryAIMutationPath] {
        paths.filter { $0.source == .unstaged || $0.source == .untracked }
    }

    var unstageablePaths: [RepositoryAIMutationPath] {
        paths.filter { $0.source == .staged && $0.file.status != .conflict }
    }

    var isClean: Bool { status.isEmpty }

    func path(id: String) -> RepositoryAIMutationPath? {
        paths.first { $0.id == id }
    }

    func localBranch(id: String) -> RepositoryAIMutationRef? {
        localBranches.first { $0.id == id }
    }

    func startPoint(id: String) -> RepositoryAIMutationRef? {
        startPoints.first { $0.id == id }
    }

    func conflictResolution(id: String) -> RepositoryAIConflictResolutionManifest? {
        conflictResolutions.first { $0.id == id }
    }
}

nonisolated protocol RepositoryAIMutationContextProviding: Sendable {
    func context(in repositoryURL: URL) async throws -> RepositoryAIMutationPlanningContext
}

actor RepositoryAIConflictResolutionRegistry {
    static let shared = RepositoryAIConflictResolutionRegistry()

    private var manifestsByRepository: [String: [String: RepositoryAIConflictResolutionManifest]] = [:]

    func register(_ manifest: RepositoryAIConflictResolutionManifest) {
        manifestsByRepository[manifest.repositoryIdentity, default: [:]][manifest.id] = manifest
    }

    func manifests(repositoryIdentity: String) -> [RepositoryAIConflictResolutionManifest] {
        Array(manifestsByRepository[repositoryIdentity, default: [:]].values)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(id: String, repositoryIdentity: String) {
        manifestsByRepository[repositoryIdentity]?[id] = nil
        if manifestsByRepository[repositoryIdentity]?.isEmpty == true {
            manifestsByRepository[repositoryIdentity] = nil
        }
    }

    func removeAll(repositoryIdentity: String) {
        manifestsByRepository[repositoryIdentity] = nil
    }
}

actor RepositoryAIMutationContextProvider: RepositoryAIMutationContextProviding {
    nonisolated private static let maximumPathsPerSection = 100
    private let gitService: GitStatusService
    private let stateProvider: any RepositoryAIRepositoryStateProviding
    private let conflictRegistry: RepositoryAIConflictResolutionRegistry

    init(
        gitService: GitStatusService = .shared,
        stateProvider: any RepositoryAIRepositoryStateProviding = RepositoryAIRepositoryStateProvider(),
        conflictRegistry: RepositoryAIConflictResolutionRegistry = .shared
    ) {
        self.gitService = gitService
        self.stateProvider = stateProvider
        self.conflictRegistry = conflictRegistry
    }

    func context(in repositoryURL: URL) async throws -> RepositoryAIMutationPlanningContext {
        async let loadedState = stateProvider.state(in: repositoryURL)
        async let loadedStatus = gitService.status(for: repositoryURL)
        async let loadedBranches = gitService.localBranches(in: repositoryURL)
        async let loadedWorktrees = gitService.worktrees(in: repositoryURL)
        async let loadedAuthor = gitService.gitUser(in: repositoryURL)
        async let loadedOperation = gitService.inProgressOperation(in: repositoryURL)
        async let loadedUnfinishedOperation = gitService.hasUnfinishedGitFlowStartOperation(in: repositoryURL)
        async let loadedSigning = signingEnabled(in: repositoryURL)
        async let loadedStagedStatistics = stagedStatistics(in: repositoryURL)

        let state = try await loadedState
        let status = try await loadedStatus
        let branchNames = await loadedBranches.sorted()
        let worktrees = await loadedWorktrees
        let identity = Self.repositoryIdentity(for: repositoryURL)
        let currentPath = repositoryURL.resolvingSymlinksInPath().standardizedFileURL
        let operation = await loadedOperation
        let hasUnfinishedOperation = await loadedUnfinishedOperation
        let conflictResolutions = await currentConflictResolutions(
            repositoryIdentity: identity,
            status: status,
            repositoryURL: repositoryURL
        )
        let otherWorktreeBranches = Set(worktrees.compactMap { entry -> String? in
            guard entry.path.resolvingSymlinksInPath().standardizedFileURL != currentPath else { return nil }
            return entry.branch
        })

        var branchRefs: [RepositoryAIMutationRef] = []
        for (index, name) in branchNames.prefix(40).enumerated() {
            guard let tip = try? await GitBranchUndoSupport().tip(of: name, in: repositoryURL),
                  !tip.isEmpty else { continue }
            branchRefs.append(RepositoryAIMutationRef(id: "branch-\(index + 1)", name: name, commit: tip))
        }

        var startPoints = branchRefs.map {
            RepositoryAIMutationRef(id: "start-\($0.id)", name: $0.name, commit: $0.commit)
        }
        if state.head != "<unborn>" {
            startPoints.insert(RepositoryAIMutationRef(id: "start-head", name: "HEAD", commit: state.head), at: 0)
        }

        return RepositoryAIMutationPlanningContext(
            repositoryIdentity: identity,
            repositoryState: state,
            status: status,
            paths: Self.pathManifest(status: status),
            localBranches: branchRefs,
            startPoints: startPoints,
            conflictResolutions: conflictResolutions,
            stagedStatistics: await loadedStagedStatistics,
            author: await loadedAuthor,
            signingEnabled: await loadedSigning,
            inProgressOperation: operation?.displayName ?? (hasUnfinishedOperation ? "Merge or rebase" : nil),
            branchesCheckedOutInOtherWorktrees: otherWorktreeBranches
        )
    }

    nonisolated static func repositoryIdentity(for repositoryURL: URL) -> String {
        repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    nonisolated private static func pathManifest(status: GitStatus) -> [RepositoryAIMutationPath] {
        let staged = status.staged.sorted(by: statusFileOrder)
            .prefix(maximumPathsPerSection)
            .enumerated().map { index, file in
            RepositoryAIMutationPath(
                id: "staged-\(index + 1)",
                file: file,
                source: file.status == .conflict ? .conflict : .staged
            )
        }
        let unstaged = status.unstaged.sorted(by: statusFileOrder)
            .prefix(maximumPathsPerSection)
            .enumerated().map { index, file in
            RepositoryAIMutationPath(
                id: "unstaged-\(index + 1)",
                file: file,
                source: file.status == .conflict ? .conflict : .unstaged
            )
        }
        let untracked = status.untracked.sorted(by: statusFileOrder)
            .prefix(maximumPathsPerSection)
            .enumerated().map { index, file in
            RepositoryAIMutationPath(id: "untracked-\(index + 1)", file: file, source: .untracked)
        }
        return staged + unstaged + untracked
    }

    nonisolated private static func statusFileOrder(_ lhs: StatusFile, _ rhs: StatusFile) -> Bool {
        if lhs.path == rhs.path {
            return (lhs.originalPath ?? "") < (rhs.originalPath ?? "")
        }
        return lhs.path < rhs.path
    }

    private func signingEnabled(in repositoryURL: URL) async -> Bool {
        let value = (try? await gitService.runGit(
            arguments: ["config", "--bool", "commit.gpgsign"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "true" || value == "yes" || value == "on" || value == "1"
    }

    private func stagedStatistics(in repositoryURL: URL) async -> RepositoryAIMutationStatistics {
        let output = (try? await gitService.runGit(
            arguments: ["diff", "--cached", "--numstat", "--"],
            in: repositoryURL
        )) ?? ""
        var files = 0
        var additions = 0
        var deletions = 0
        var binaryFiles = 0
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            files += 1
            if columns[0] == "-" || columns[1] == "-" {
                binaryFiles += 1
            } else {
                additions += Int(columns[0]) ?? 0
                deletions += Int(columns[1]) ?? 0
            }
        }
        return RepositoryAIMutationStatistics(
            fileCount: files,
            additions: additions,
            deletions: deletions,
            binaryFileCount: binaryFiles
        )
    }

    private func currentConflictResolutions(
        repositoryIdentity: String,
        status: GitStatus,
        repositoryURL: URL
    ) async -> [RepositoryAIConflictResolutionManifest] {
        let currentConflictPaths = Set(
            (status.staged + status.unstaged)
                .filter { $0.status == .conflict }
                .map(\.path)
        )
        let manifests = await conflictRegistry.manifests(repositoryIdentity: repositoryIdentity)
        var current: [RepositoryAIConflictResolutionManifest] = []

        for manifest in manifests {
            var isCurrent = !manifest.files.isEmpty
            for resolution in manifest.files where isCurrent {
                guard currentConflictPaths.contains(resolution.loadedFile.file.path),
                      let fingerprint = try? await gitService.conflictAIFingerprint(
                        for: resolution.loadedFile.file,
                        in: repositoryURL
                      ),
                      fingerprint == resolution.loadedFile.snapshot.fingerprint else {
                    isCurrent = false
                    break
                }
            }

            if isCurrent {
                current.append(manifest)
            } else {
                await conflictRegistry.remove(id: manifest.id, repositoryIdentity: repositoryIdentity)
            }
        }
        return current
    }
}
