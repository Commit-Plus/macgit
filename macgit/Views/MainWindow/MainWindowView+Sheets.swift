//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    @ViewBuilder
    var commitSheet: some View {
        CommitSheetView(hasStagedChanges: syncState.stagedBadgeCount > 0) { message, commitAllChanges in
            runRepositoryOperation("Committing changes...") {
                await commitFromToolbar(message: message, commitAllChanges: commitAllChanges)
            }
        }
    }

    @ViewBuilder
    var pullSheet: some View {
        PullSheetView(
            repositoryURL: repositoryURL,
            preselectedRemote: repoSettings.defaultRemoteName,
            preselectedBranch: resolvedPullPreselectedBranch(),
            defaultPullStrategy: repoSettings.pullStrategy
        ) { remote, branch, options in
            runRepositoryOperation("Pulling \(remote)/\(branch)...") {
                await syncState.performPull(
                    remote: remote,
                    branch: branch,
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    var pushSheet: some View {
        PushSheetView(repositoryURL: repositoryURL) { options in
            runRepositoryOperation("Pushing branches...") {
                await syncState.performPush(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    var fetchSheet: some View {
        FetchSheetView(repositoryURL: repositoryURL) { options in
            runRepositoryOperation("Fetching remotes...") {
                await syncState.performFetch(
                    options: options,
                    repositoryURL: repositoryURL,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    var addSubmoduleSheet: some View {
        AddSubmoduleSheet(
            repositoryURL: repositoryURL,
            onAdd: { request in
                try await GitStatusService.shared.addSubmodule(
                    request,
                    in: repositoryURL,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            },
            onCompleted: { request in
                appState.showSubmodules = true
                selectedItem = .submodule(request.path)
            },
            onRunRepositoryOperation: runRepositoryOperation
        )
    }

    @ViewBuilder
    var addLinkSubtreeSheet: some View {
        AddLinkSubtreeSheet(
            repositoryURL: repositoryURL,
            onAdd: { request in
                try await GitStatusService.shared.addSubtree(
                    request,
                    in: repositoryURL,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            },
            onLink: { request in
                try await GitStatusService.shared.linkExistingSubtree(request, in: repositoryURL)
            },
            onCompleted: { entry in
                appState.showSubtrees = true
                selectedItem = .subtree(entry.id)
            },
            onRunRepositoryOperation: runRepositoryOperation
        )
    }

    @ViewBuilder
    var branchSheet: some View {
        BranchSheetView(
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            initialStartPoint: branchSheetStartPoint,
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
    }

    @ViewBuilder
    var tagSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            if let startPoint = branchTagStartPoint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From branch:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(startPoint.branchName) at \(startPoint.shortHash) : \(startPoint.message)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingTagSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    Task { await createTagFromBranch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty || branchTagStartPoint == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }

    @ViewBuilder
    var newTagSheet: some View {
        TagSheetView(
            repositoryURL: repositoryURL,
            onRunRepositoryOperation: runRepositoryOperation,
            onCreate: { request in
                try await createTag(from: request)
            }
        )
    }

    @ViewBuilder
    var renameSheet: some View {
        RenameBranchSheetView(
            repositoryURL: repositoryURL,
            currentName: branchToRename,
            undoManager: undoManager,
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
    }

    @ViewBuilder
    func commitDropConfirmationSheet(for confirmation: PendingCommitDropConfirmation) -> some View {
        GitDragActionConfirmationSheet(
            title: "Cherry-pick Commits",
            message: "Cherry-pick the selected commits into the current HEAD branch.",
            targetBranchName: confirmation.targetBranch,
            commits: confirmation.commits,
            primaryActionTitle: "Cherry-pick",
            onConfirm: {
                let request = confirmation
                pendingCommitDropConfirmation = nil
                runRepositoryOperation("Cherry-picking commits...") {
                    await performCommitDropCherryPick(request)
                }
            },
            onCancel: {
                pendingCommitDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    func branchDropConfirmationSheet(for confirmation: PendingBranchDropConfirmation) -> some View {
        GitDragActionConfirmationSheet(
            title: "Merge or Rebase Branch",
            message: "Review the branch action before continuing.",
            sourceBranchName: confirmation.sourceBranch,
            targetBranchName: confirmation.targetBranch,
            commits: [],
            primaryActionTitle: "Continue",
            selectedBranchOperation: Binding(
                get: { pendingBranchDropConfirmation?.operation ?? confirmation.operation },
                set: { newValue in
                    guard var pending = pendingBranchDropConfirmation else { return }
                    pending.operation = newValue
                    pendingBranchDropConfirmation = pending
                }
            ),
            onConfirm: {
                guard let request = pendingBranchDropConfirmation else { return }
                pendingBranchDropConfirmation = nil
                runRepositoryOperation(request.operation == .merge ? "Merging \(request.sourceBranch)..." : "Rebasing onto \(request.sourceBranch)...") {
                    await performBranchDropOperation(request)
                }
            },
            onCancel: {
                pendingBranchDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    var mergeSheet: some View {
        MergeSheetView(repositoryURL: repositoryURL) { branch, _, options in
            runRepositoryOperation("Merging \(branch)...") {
                await syncState.performMerge(branch: branch, options: options, repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    var stashSheet: some View {
        StashSheetView(paths: pendingStashPaths) { options in
            let pathsToStash = options.paths
            runRepositoryOperation(pathsToStash.isEmpty ? "Stashing changes..." : "Stashing \(pathsToStash.count) files...") {
                await syncState.performStash(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
            clearPendingStashPaths()
        }
        .onDisappear {
            clearPendingStashPaths()
        }
    }

    @MainActor
    func clearPendingStashPaths() {
        guard !pendingStashPaths.isEmpty else { return }
        pendingStashPaths = []
    }

    @ViewBuilder
    var stashActionSheet: some View {
        if let ref = pendingStashRef, let action = pendingStashAction {
            StashActionConfirmationSheet(stashRef: ref, action: action) { deleteAfterApplying in
                runRepositoryOperation(action == .apply ? "Applying \(ref)..." : "Deleting \(ref)...") {
                    await performStashAction(
                        ref: ref,
                        action: action,
                        deleteAfterApplying: deleteAfterApplying
                    )
                }
            }
        }
    }

    @ViewBuilder
    var repositorySettingsSheet: some View {
        RepositorySettingsSheetView(
            repositoryURL: repositoryURL,
            initialSettings: repoSettings,
            onSave: { newSettings in
                repoSettings = newSettings
                repoSettingsStore.update(for: repositoryURL.path, settings: newSettings)
                syncState.startBackgroundSync(repositoryURL: repositoryURL, settings: newSettings)
                Task {
                    await refreshRemotePresentation(for: newSettings.defaultRemoteName)
                }
            },
            onOpenGitIgnore: openGitIgnoreFile,
            onOpenGitConfig: openGitConfigFile,
            onOpenRemoteURL: { remote in
                openRemoteURL(remote: remote)
            }
        )
    }

    var createPullRequestSheetPresented: Binding<Bool> {
        Binding(
            get: { pullRequestController.createDraftSeed != nil },
            set: { isPresented in
                if !isPresented {
                    pullRequestController.dismissCreatePullRequest()
                }
            }
        )
    }

    @ViewBuilder
    var createPullRequestSheet: some View {
        if let seed = pullRequestController.createDraftSeed {
            CreatePullRequestSheet(
                seed: seed,
                isSubmitting: pullRequestController.isPerformingAction,
                onCancel: { pullRequestController.dismissCreatePullRequest() },
                onCreate: { draft in
                    Task { await pullRequestController.createPullRequest(draft) }
                }
            )
        }
    }
}
