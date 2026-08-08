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
        CommitSheetView(
            aiProviderController: aiProviderController,
            repositoryURL: repositoryURL,
            hasStagedChanges: syncState.stagedBadgeCount > 0
        ) { message, commitAllChanges in
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
            runRemoteOperation("Pulling \(remote)/\(branch)...", remotes: [remote]) { credentialResolver in
                await syncState.performPull(
                    remote: remote,
                    branch: branch,
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: credentialResolver
                )
            }
        }
    }

    @ViewBuilder
    var pushSheet: some View {
        PushSheetView(repositoryURL: repositoryURL) { options in
            runRemoteOperation("Pushing branches...", remotes: [options.remote]) { credentialResolver in
                await syncState.performPush(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: credentialResolver
                )
            }
        }
    }

    @ViewBuilder
    var fetchSheet: some View {
        FetchSheetView(repositoryURL: repositoryURL) { options in
            Task {
                guard let credentialResolver = await credentialResolverForFetch(options: options) else { return }
                runRepositoryOperation("Fetching remotes...") {
                    await syncState.performFetch(
                        options: options,
                        repositoryURL: repositoryURL,
                        credentialResolver: credentialResolver
                    )
                }
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
                    credentialResolver: providerCredentialResolver
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
                    credentialResolver: providerCredentialResolver
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            if let startPoint = tagStartPoint {
                Text("Create tag from commit: \(startPoint.message) - \(startPoint.shortHash)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
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
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty || tagStartPoint == nil)
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
            initialGitFlowConfiguration: gitFlowConfiguration,
            initiallySelectGitFlow: initiallySelectGitFlowSettings,
            providerAccountResolver: providerAccountController.credentialResolver(
                preferredAccountIDsByRemoteIdentity: providerAccountPreferenceStore.preferences
            ),
            providerAccountPreferences: providerAccountPreferenceStore.preferences,
            onSave: { newSettings in
                repoSettings = newSettings
                repoSettingsStore.update(for: repositoryURL.path, settings: newSettings)
                Task {
                    try? await GitStatusService.shared.updateGitUserConfiguration(
                        useGlobalSettings: newSettings.useGlobalUserSettings,
                        name: newSettings.userName,
                        email: newSettings.userEmail,
                        in: repositoryURL
                    )
                }
                syncState.startBackgroundSync(
                    repositoryURL: repositoryURL,
                    settings: newSettings,
                    globalAutoFetchEnabled: appState.autoFetchEnabled
                )
                Task {
                    await refreshRemotePresentation(for: newSettings.defaultRemoteName)
                }
            },
            onSaveGitFlowConfiguration: { configuration in
                gitFlowConfiguration = configuration
                Task {
                    do {
                        try await gitFlowConfigurationStore.save(configuration, in: repositoryURL)
                    } catch {
                        await MainActor.run {
                            syncState.showError(error.localizedDescription)
                        }
                    }
                }
            },
            onCreateGitFlowDevelopBranch: { name, startingPoint in
                let branch = try await GitFlowService().createDevelopBranch(
                    name: name,
                    startingPoint: startingPoint,
                    in: repositoryURL
                )
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
                return branch
            },
            onSaveProviderAccountPreferences: { preferences in
                for (preferenceKey, accountID) in preferences {
                    providerAccountPreferenceStore.update(
                        accountID: accountID,
                        forPreferenceKey: preferenceKey
                    )
                }
            },
            onOpenGitIgnore: openGitIgnoreFile,
            onOpenGitConfig: openGitConfigFile,
            onOpenRemoteURL: { remote in
                openRemoteURL(remote: remote)
            }
        )
    }

    @ViewBuilder
    func startGitFlowSheet(for kind: GitFlowTopicKind) -> some View {
        StartGitFlowSheet(
            kind: kind,
            configuration: gitFlowConfiguration,
            worktreeRootURL: gitFlowWorktreeRootURL ?? repositoryURL,
            onRunRepositoryOperation: runRepositoryOperation,
            onStart: startGitFlow
        )
    }

    @ViewBuilder
    func finishGitFlowSheet(for plan: GitFlowFinishPlan) -> some View {
        FinishGitFlowSheet(
            plan: plan,
            onRunRepositoryOperation: runRepositoryOperation,
            onFinish: finishGitFlow
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
                changedFileCount: pullRequestController.createDraftChangedFileCount,
                isLoadingChanges: pullRequestController.isLoadingCreateDraftChanges,
                changesErrorMessage: pullRequestController.createDraftChangesErrorMessage,
                onCancel: { pullRequestController.dismissCreatePullRequest() },
                onBranchesChanged: { sourceBranch, targetBranch in
                    Task {
                        guard await authorizePullRequestAccess() else { return }
                        await pullRequestController.loadCreateDraftChanges(
                            sourceBranch: sourceBranch,
                            targetBranch: targetBranch
                        )
                    }
                },
                onCreate: { draft in
                    Task {
                        guard await authorizePullRequestAccess() else { return }
                        await pullRequestController.createPullRequest(draft)
                    }
                }
            )
        }
    }

    func tagMoveConfirmationSheet(for confirmation: PendingTagMoveConfirmation) -> some View {
        MoveTagConfirmationSheet(
            confirmation: confirmation,
            onConfirm: { remote in
                pendingTagMoveConfirmation = nil
                runRepositoryOperation("Moving tag \(confirmation.tagName)...") {
                    await performTagMove(confirmation, forcePushRemote: remote)
                }
            },
            onCancel: {
                pendingTagMoveConfirmation = nil
            }
        )
    }
}

struct MoveTagConfirmationSheet: View {
    let confirmation: PendingTagMoveConfirmation
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @State private var forcePush = false
    @State private var selectedRemote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move Tag \(confirmation.tagName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Move the tag to a different commit. This changes the local tag and may require a force-push if it has already been published.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            commitSummary(title: "Current commit", hash: confirmation.currentCommit.commitHash, message: confirmation.currentCommit.subject)

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            commitSummary(title: "New commit", hash: confirmation.newCommit.hash, message: confirmation.newCommit.message)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Force-push updated tag to remote", isOn: $forcePush)
                    .toggleStyle(.checkbox)
                    .disabled(confirmation.remotes.isEmpty)

                if forcePush {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(confirmation.remotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Move Tag") {
                    onConfirm(forcePush ? selectedRemote : nil)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(forcePush && selectedRemote.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500, maxWidth: 560)
        .task {
            selectedRemote = confirmation.remotes.first ?? ""
        }
    }

    private func commitSummary(title: String, hash: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(String(hash.prefix(7))) — \(message)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
