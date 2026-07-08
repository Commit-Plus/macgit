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

struct CreatePullRequestSheet: View {
    let seed: PullRequestDraftSeed
    let isSubmitting: Bool
    var onCancel: () -> Void
    var onCreate: (PullRequestDraft) -> Void

    @State private var sourceBranch: String
    @State private var targetBranch: String
    @State private var title: String
    @State private var bodyText: String = ""
    @State private var validationMessage: String?

    init(
        seed: PullRequestDraftSeed,
        isSubmitting: Bool,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (PullRequestDraft) -> Void
    ) {
        self.seed = seed
        self.isSubmitting = isSubmitting
        self.onCancel = onCancel
        self.onCreate = onCreate
        _sourceBranch = State(initialValue: seed.sourceBranch)
        _targetBranch = State(initialValue: seed.targetBranch)
        _title = State(initialValue: seed.suggestedTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Pull Request")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Source", selection: $sourceBranch) {
                        ForEach(seed.sourceBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
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
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Pull request title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create Pull Request") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !canSubmit)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sourceBranch != targetBranch
    }

    private func submit() {
        do {
            let draft = try PullRequestDraft(
                repository: seed.repository,
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                title: title,
                body: bodyText
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
