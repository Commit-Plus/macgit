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

struct FinishGitFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialPlan: GitFlowFinishPlan
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onValidateTag: (String) async -> String?
    let onFinish: (GitFlowFinishPlan) async -> Bool

    @State private var strategy: GitFlowTopicFinishStrategy
    @State private var createTag: Bool
    @State private var tagName: String
    @State private var tagValidationMessage: String?
    @State private var isValidatingTag = false
    @State private var deleteSourceBranch: Bool

    init(
        plan: GitFlowFinishPlan,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner,
        onValidateTag: @escaping (String) async -> String?,
        onFinish: @escaping (GitFlowFinishPlan) async -> Bool
    ) {
        initialPlan = plan
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onValidateTag = onValidateTag
        self.onFinish = onFinish
        _strategy = State(initialValue: plan.strategy)
        _createTag = State(initialValue: plan.createTag)
        _tagName = State(initialValue: plan.tagName ?? "")
        _deleteSourceBranch = State(initialValue: plan.deleteSourceBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Finish \(initialPlan.kind.displayName)")
                .font(.title2)
                .bold()

            LabeledContent("Source") { Text(initialPlan.sourceBranch).bold() }
            targetSummary
            finishControls
            executionPreview

            Toggle("Delete local branch after a successful finish", isOn: $deleteSourceBranch)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("Finish \(initialPlan.kind.displayName)", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                    .disabled(isFinishDisabled)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 540)
        .task(id: tagValidationKey) {
            await validateTagIfNeeded()
        }
    }

    @ViewBuilder
    private var targetSummary: some View {
        if initialPlan.kind.requiresReleaseTag {
            LabeledContent("Merge order") {
                Text(initialPlan.targetBranches.joined(separator: " → ")).bold()
            }
            LabeledContent("Strategy") { Text("Merge with --no-ff") }
        } else {
            LabeledContent("Finish into") { Text(initialPlan.targetBranch).bold() }
        }
    }

    @ViewBuilder
    private var finishControls: some View {
        if initialPlan.kind.requiresReleaseTag {
            Toggle("Create annotated tag", isOn: $createTag)
                .toggleStyle(.checkbox)
            if createTag {
                LabeledContent("Tag name") {
                    TextField("Version tag", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                }
                if isValidatingTag {
                    Label("Checking tag…", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let tagValidationMessage {
                    Label(tagValidationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Picker("Strategy", selection: $strategy) {
                ForEach(GitFlowTopicFinishStrategy.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var executionPreview: some View {
        Label(previewText, systemImage: strategyIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var previewText: String {
        if initialPlan.kind.requiresReleaseTag {
            let tagCopy = createTag ? " An annotated tag will be created on the Main merge." : " No tag will be created."
            return "Commit+ will merge into \(initialPlan.targetBranches.joined(separator: ", then ")).\(tagCopy)"
        }
        if strategy == .rebaseFastForward {
            return "Commit+ will rebase \(initialPlan.sourceBranch) onto \(initialPlan.targetBranch), then fast-forward \(initialPlan.targetBranch). This rewrites the local topic branch and will not force-push it."
        }
        return "Commit+ will check out \(initialPlan.targetBranch) and create a merge commit."
    }

    private var strategyIcon: String {
        strategy == .rebaseFastForward && !initialPlan.kind.requiresReleaseTag
            ? "arrow.triangle.2.circlepath"
            : "arrow.triangle.merge"
    }

    private var tagValidationKey: String {
        "\(createTag):\(tagName)"
    }

    private var isFinishDisabled: Bool {
        initialPlan.kind.requiresReleaseTag
            && createTag
            && (isValidatingTag || tagValidationMessage != nil)
    }

    private func validateTagIfNeeded() async {
        guard initialPlan.kind.requiresReleaseTag, createTag else {
            tagValidationMessage = nil
            isValidatingTag = false
            return
        }
        isValidatingTag = true
        tagValidationMessage = await onValidateTag(tagName)
        isValidatingTag = false
    }

    private func finish() {
        var plan = initialPlan
        plan.strategy = initialPlan.kind.requiresReleaseTag ? .mergeNoFastForward : strategy
        plan.createTag = initialPlan.kind.requiresReleaseTag && createTag
        plan.tagName = plan.createTag ? tagName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        plan.deleteSourceBranch = deleteSourceBranch
        onRunRepositoryOperation("Finishing \(plan.sourceBranch)…") {
            if await onFinish(plan) {
                await MainActor.run { dismiss() }
            }
        }
    }
}
