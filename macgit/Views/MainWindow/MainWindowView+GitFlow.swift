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

extension MainWindowView {
    var gitFlowMenu: some View {
        Menu {
            gitFlowMenuItems
        } label: {
            ToolbarButtonLabel(
                icon: "point.3.connected.trianglepath.dotted",
                label: "Git Flow",
                showText: appState.showToolbarButtonText
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(operationProgress.activeOperation != nil)
        .help("Git Flow")
    }

    var gitFlowMoreMenu: some View {
        Menu("Git Flow") {
            gitFlowMenuItems
        }
    }

    @ViewBuilder
    var gitFlowMenuItems: some View {
        if gitFlowConfiguration.isEnabled {
            ForEach(GitFlowTopicKind.allCases) { kind in
                Button("Start \(kind.displayName)...") {
                    pendingGitFlowTopicKind = kind
                }
            }

            Divider()

            Button("Configure Git Flow...") {
                initiallySelectGitFlowSettings = true
                showingRepositorySettings = true
            }
            Button("Disable Git Flow") {
                disableGitFlow()
            }
        } else {
            Button("Set Up Git Flow...") {
                initiallySelectGitFlowSettings = true
                showingRepositorySettings = true
            }
        }
    }

    func startGitFlow(_ plan: GitFlowStartPlan) async -> Bool {
        do {
            let result = try await GitFlowService().start(plan, in: repositoryURL)
            await MainActor.run {
                undoManager.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Start \(plan.kind.displayName) \(plan.branchName)",
                        undoOperation: .sequence([
                            .checkoutRef(ref: result.previousRef),
                            .deleteLocalBranch(
                                name: result.plan.branchName,
                                force: true,
                                expectedTip: result.createdTip
                            )
                        ]),
                        redoOperation: .createLocalBranch(
                            name: result.plan.branchName,
                            startPoint: result.createdTip,
                            checkout: true
                        )
                    )
                )
                selectedItem = .branch(result.plan.branchName)
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            return true
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
            return false
        }
    }

    func disableGitFlow() {
        var configuration = gitFlowConfiguration
        configuration.isEnabled = false
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
    }
}
