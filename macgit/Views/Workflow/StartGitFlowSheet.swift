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

struct StartGitFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: GitFlowTopicKind
    let configuration: GitFlowConfiguration
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onStart: (GitFlowStartPlan) async -> Bool

    @State private var topicName = ""

    private var plan: GitFlowStartPlan? {
        try? GitFlowPlanner().startPlan(
            kind: kind,
            topicName: topicName,
            configuration: configuration
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start \(kind.displayName)")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)

                HStack(spacing: 0) {
                    Text(configuration.normalized().prefix(for: kind))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)

                    TextField("branch-name", text: $topicName)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.trailing, 8)
                }
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }
            }

            LabeledContent("Starting point") {
                Text(configuration.baseBranch(for: kind))
                    .bold()
            }

            if let plan {
                Label("Commit+ will create and check out \(plan.branchName).", systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Start \(kind.displayName)") {
                    guard let plan else { return }
                    onRunRepositoryOperation("Starting \(plan.branchName)...") {
                        if await onStart(plan) {
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(plan == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 480)
    }
}
