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

import SwiftUI

struct CreatePullRequestView: View {
    let seed: PullRequestDraftSeed
    let repositoryURL: URL
    let isSubmitting: Bool
    let changedFileCount: Int?
    let isLoadingChanges: Bool
    let changesErrorMessage: String?
    let participants: [PullRequestParticipant]
    let isLoadingParticipants: Bool
    let participantsErrorMessage: String?
    var onCancel: () -> Void
    var onBranchesChanged: (String, String) -> Void
    var onCreate: (PullRequestDraft) -> Void

    @State private var sourceBranch: String
    @State private var targetBranch: String
    @State private var title: String
    @State private var bodyText: String = ""
    @State private var selectedReviewerIDs: Set<String> = []
    @State private var selectedAssigneeIDs: Set<String> = []
    @State private var validationMessage: String?
    @State private var showingDiscardConfirmation = false

    init(
        seed: PullRequestDraftSeed,
        repositoryURL: URL,
        isSubmitting: Bool,
        changedFileCount: Int?,
        isLoadingChanges: Bool,
        changesErrorMessage: String?,
        participants: [PullRequestParticipant],
        isLoadingParticipants: Bool,
        participantsErrorMessage: String?,
        onCancel: @escaping () -> Void,
        onBranchesChanged: @escaping (String, String) -> Void,
        onCreate: @escaping (PullRequestDraft) -> Void
    ) {
        self.seed = seed
        self.repositoryURL = repositoryURL
        self.isSubmitting = isSubmitting
        self.changedFileCount = changedFileCount
        self.isLoadingChanges = isLoadingChanges
        self.changesErrorMessage = changesErrorMessage
        self.participants = participants
        self.isLoadingParticipants = isLoadingParticipants
        self.participantsErrorMessage = participantsErrorMessage
        self.onCancel = onCancel
        self.onBranchesChanged = onBranchesChanged
        self.onCreate = onCreate
        _sourceBranch = State(initialValue: seed.sourceBranch)
        _targetBranch = State(initialValue: seed.targetBranch)
        _title = State(initialValue: seed.suggestedTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PersistentHSplit(
                autosaveName: "CreatePullRequestMainSplit",
                left: {
                    formPanel
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                },
                right: {
                    PullRequestDraftChangesView(
                        repositoryURL: repositoryURL,
                        remoteName: seed.remoteName,
                        sourceBranch: sourceBranch,
                        targetBranch: targetBranch
                    )
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                }
            )
        }
        .onChange(of: sourceBranch) { _, _ in
            reloadChanges()
        }
        .onChange(of: targetBranch) { _, _ in
            reloadChanges()
        }
        .confirmationDialog(
            "Discard Pull Request Draft?",
            isPresented: $showingDiscardConfirmation
        ) {
            Button("Discard Draft", role: .destructive, action: onCancel)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your title, description, and selections will be lost.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Back to Pull Requests", systemImage: "chevron.left", action: requestCancel)
                .buttonStyle(.borderless)
            Text("Create Pull Request")
                .font(.headline)
            Spacer()
            Button("Cancel", action: requestCancel)
                .keyboardShortcut(.cancelAction)
            Button("Create Pull Request") {
                submit()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || !canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var formPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Source", selection: $sourceBranch) {
                        ForEach(seed.sourceBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Target", selection: $targetBranch) {
                        ForEach(seed.targetBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                }

                changeSummary

                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Pull request title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $bodyText)
                        .font(.body)
                        .frame(minHeight: 220)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        }
                }

                PullRequestParticipantPicker(
                    title: "Reviewers",
                    participants: participants,
                    selectedIDs: $selectedReviewerIDs,
                    isLoading: isLoadingParticipants
                )

                PullRequestParticipantPicker(
                    title: "Assignees",
                    participants: participants,
                    selectedIDs: $selectedAssigneeIDs,
                    isLoading: isLoadingParticipants
                )

                if let participantsErrorMessage {
                    Label(participantsErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sourceBranch != targetBranch
            && changedFileCount.map { $0 > 0 } == true
            && !isLoadingChanges
    }

    @ViewBuilder
    private var changeSummary: some View {
        HStack(spacing: 8) {
            if isLoadingChanges {
                ProgressView()
                    .controlSize(.small)
                Text("Checking file changes...")
            } else if let changesErrorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(changesErrorMessage)
                    .foregroundStyle(.secondary)
            } else if let changedFileCount {
                Image(systemName: changedFileCount > 0 ? "doc.on.doc" : "exclamationmark.circle")
                    .foregroundStyle(changedFileCount > 0 ? Color.secondary : Color.orange)
                    .accessibilityHidden(true)
                Text(changedFileCount == 1 ? "1 file changed" : "\(changedFileCount) files changed")
                    .foregroundStyle(changedFileCount > 0 ? .primary : .secondary)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func reloadChanges() {
        validationMessage = nil
        onBranchesChanged(sourceBranch, targetBranch)
    }

    private func requestCancel() {
        if hasDraftChanges {
            showingDiscardConfirmation = true
        } else {
            onCancel()
        }
    }

    private var hasDraftChanges: Bool {
        sourceBranch != seed.sourceBranch
            || targetBranch != seed.targetBranch
            || title != seed.suggestedTitle
            || !bodyText.isEmpty
            || !selectedReviewerIDs.isEmpty
            || !selectedAssigneeIDs.isEmpty
    }

    private func submit() {
        do {
            let draft = try PullRequestDraft(
                repository: seed.repository,
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                title: title,
                body: bodyText,
                reviewers: participants.filter { selectedReviewerIDs.contains($0.id) },
                assignees: participants.filter { selectedAssigneeIDs.contains($0.id) }
            )
            validationMessage = nil
            onCreate(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct PullRequestCommentSheet: View {
    let pullRequest: PullRequestSummary
    let isSubmitting: Bool
    var onCancel: () -> Void
    var onSubmit: (String) -> Void

    @State private var bodyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Comment on #\(pullRequest.number)")
                .font(.title3.weight(.semibold))

            TextEditor(text: $bodyText)
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Comment") {
                    onSubmit(bodyText)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560)
    }
}
