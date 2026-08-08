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
    let onFinish: (GitFlowFinishPlan) async -> Bool

    @State private var deleteSourceBranch: Bool

    init(
        plan: GitFlowFinishPlan,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner,
        onFinish: @escaping (GitFlowFinishPlan) async -> Bool
    ) {
        initialPlan = plan
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onFinish = onFinish
        _deleteSourceBranch = State(initialValue: plan.deleteSourceBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Finish \(initialPlan.kind.displayName)")
                .font(.title2)
                .bold()

            LabeledContent("Source") { Text(initialPlan.sourceBranch).bold() }
            LabeledContent("Merge into") { Text(initialPlan.targetBranch).bold() }
            LabeledContent("Strategy") { Text("Merge with --no-ff") }

            Toggle("Delete local branch after a successful merge", isOn: $deleteSourceBranch)

            Label(
                "Commit+ will check out \(initialPlan.targetBranch) and create a merge commit.",
                systemImage: "arrow.triangle.merge"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Finish \(initialPlan.kind.displayName)") {
                    var plan = initialPlan
                    plan.deleteSourceBranch = deleteSourceBranch
                    onRunRepositoryOperation("Finishing \(plan.sourceBranch)…") {
                        if await onFinish(plan) {
                            await MainActor.run { dismiss() }
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
            }
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 500)
    }
}
