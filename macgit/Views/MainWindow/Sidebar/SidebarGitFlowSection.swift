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

struct SidebarGitFlowSection: View {
    let configuration: GitFlowConfiguration
    let currentBranch: String
    let hasPendingFinish: Bool
    let isExpanded: Bool
    let isOperationDisabled: Bool
    let actions: SidebarGitFlowActions

    private var currentKind: GitFlowTopicKind? {
        GitFlowPlanner().topicKind(for: currentBranch, configuration: configuration)
    }

    var body: some View {
        Section {
            SidebarSectionHeader(
                section: .gitFlow,
                isExpanded: isExpanded,
                activeDropLabel: nil,
                onToggle: actions.toggleSection
            ) {
                EmptyView()
            }
            .contextMenu {
                if configuration.isEnabled {
                    actionMenu
                } else {
                    Button("Set Up Git Flow…", action: actions.editWorkflow)
                        .disabled(isOperationDisabled)
                }
            }

            if isExpanded {
                if configuration.isEnabled {
                    ForEach(GitFlowTopicKind.allCases) { kind in
                        Button {
                            actions.start(kind)
                        } label: {
                            Label("Start \(kind.displayName)…", systemImage: kind.sidebarIcon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOperationDisabled || hasPendingFinish)
                        .padding(.leading, 6)
                    }
                } else {
                    Button("Set Up Git Flow…", systemImage: "gearshape", action: actions.editWorkflow)
                    .buttonStyle(.plain)
                    .disabled(isOperationDisabled)
                    .padding(.leading, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var actionMenu: some View {
        if hasPendingFinish {
            Button("Resume Finish", action: actions.resumeFinish)
                .disabled(isOperationDisabled)
            Button("Abort Finish", role: .destructive, action: actions.abortFinish)
                .disabled(isOperationDisabled)
            Divider()
        }

        flowMenuPair(.bugfix)
        Divider()
        flowMenuPair(.feature)
        Divider()
        flowMenuPair(.hotfix)
        Divider()
        flowMenuPair(.release)
        Divider()
        Button("Edit Workflow…", action: actions.editWorkflow)
        Button("Disable Workflow", action: actions.disableWorkflow)
    }

    @ViewBuilder
    private func flowMenuPair(_ kind: GitFlowTopicKind) -> some View {
        Button("Start \(kind.displayName)…") { actions.start(kind) }
            .disabled(isOperationDisabled || hasPendingFinish)
        Button("Finish \(kind.displayName)…") { actions.finish(kind) }
            .disabled(!canFinish(kind))
    }

    private func canFinish(_ kind: GitFlowTopicKind) -> Bool {
        configuration.isEnabled
            && !isOperationDisabled
            && !hasPendingFinish
            && kind.supportsFinish
            && currentKind == kind
    }
}

private extension GitFlowTopicKind {
    var sidebarIcon: String {
        switch self {
        case .feature: return "sparkles"
        case .bugfix: return "ladybug"
        case .release: return "shippingbox"
        case .hotfix: return "bandage"
        }
    }
}
