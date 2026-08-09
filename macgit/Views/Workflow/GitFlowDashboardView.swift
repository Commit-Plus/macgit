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

struct GitFlowDashboardView: View {
    let configuration: GitFlowConfiguration
    let currentBranch: String
    let checkpoint: GitFlowFinishCheckpoint?
    let recoveryIssue: GitFlowLocalStateIssue?
    let commandState: GitFlowCommandState
    let perform: (GitFlowMenuAction) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 270), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if configuration.isEnabled {
                    workflowStatus

                    if checkpoint != nil || recoveryIssue != nil {
                        GitFlowRecoveryCard(
                            checkpoint: checkpoint,
                            issue: recoveryIssue,
                            actionsEnabled: commandState.canResumeOrAbortFinish,
                            onResume: { perform(.resumeFinish) },
                            onAbort: { perform(.abortFinish) }
                        )
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(GitFlowTopicKind.allCases) { kind in
                            GitFlowTopicCard(
                                kind: kind,
                                prefix: configuration.prefix(for: kind),
                                baseBranch: configuration.baseBranch(for: kind),
                                canStart: commandState.canStart(kind),
                                canFinish: commandState.canFinish(kind),
                                onStart: { perform(.start(kind)) },
                                onFinish: { perform(.finish(kind)) }
                            )
                        }
                    }

                    Text("Finish is available for the flow that matches the current branch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    setupPrompt
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Git Flow")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text("Git Flow")
                    .font(.title2)
                    .bold()
                Text("Start and finish structured branches without leaving your repository workspace.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Configure…", systemImage: "gearshape") {
                perform(.configure)
            }
            .disabled(!commandState.canConfigure)
        }
    }

    private var workflowStatus: some View {
        HStack(spacing: 0) {
            statusColumn(
                title: "CURRENT BRANCH",
                value: currentBranch.isEmpty ? "Detached HEAD" : currentBranch,
                icon: "arrow.triangle.branch"
            )

            Divider()
                .padding(.vertical, 4)

            statusColumn(
                title: "PRIMARY BRANCHES",
                value: "\(configuration.mainBranch)  ·  \(configuration.developBranch)",
                icon: "point.topleft.down.to.point.bottomright.curvepath"
            )

            Divider()
                .padding(.vertical, 4)

            statusColumn(
                title: "STATUS",
                value: activeFlowName,
                icon: commandState.currentKind == nil ? "checkmark.circle.fill" : "circle.fill"
            )
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var activeFlowName: String {
        if let kind = commandState.currentKind {
            return "Active \(kind.displayName)"
        }
        return "Ready"
    }

    private func statusColumn(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(value, systemImage: icon)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var setupPrompt: some View {
        ContentUnavailableView {
            Label("Set Up Git Flow", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Choose your Main and Develop branches, branch prefixes, and finish strategy to get started.")
        } actions: {
            Button("Set Up Git Flow…") {
                perform(.configure)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!commandState.canConfigure)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
