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
    var gitFlowCommandState: GitFlowCommandState {
        GitFlowCommandState(
            isEnabled: gitFlowConfiguration.isEnabled,
            currentKind: GitFlowPlanner().topicKind(
                for: gitFlowCurrentBranch,
                configuration: gitFlowConfiguration
            ),
            operationInProgress: operationProgress.activeOperation != nil
        )
    }

    func handleGitFlowMenuAction(_ action: GitFlowMenuAction) {
        guard operationProgress.activeOperation == nil else { return }
        switch action {
        case .start(let kind):
            if gitFlowConfiguration.isEnabled {
                pendingGitFlowTopicKind = kind
            } else {
                presentGitFlowSettings()
            }
        case .finish(let kind):
            requestFinishGitFlow(kind)
        case .configure:
            presentGitFlowSettings()
        case .disable:
            disableGitFlow()
        }
    }

    private func presentGitFlowSettings() {
        initiallySelectGitFlowSettings = true
        showingRepositorySettings = true
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
                gitFlowCurrentBranch = result.plan.branchName
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

    func canFinishGitFlow(_ kind: GitFlowTopicKind) -> Bool {
        kind.supportsPhaseTwoFinish
            && GitFlowPlanner().topicKind(
                for: gitFlowCurrentBranch,
                configuration: gitFlowConfiguration
            ) == kind
    }

    func requestFinishGitFlow(_ kind: GitFlowTopicKind) {
        Task {
            let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
            do {
                let plan = try GitFlowPlanner().finishPlan(
                    kind: kind,
                    currentBranch: currentBranch,
                    configuration: gitFlowConfiguration
                )
                await MainActor.run {
                    gitFlowCurrentBranch = currentBranch
                    pendingGitFlowFinishPlan = plan
                }
            } catch {
                await MainActor.run { syncState.showError(error.localizedDescription) }
            }
        }
    }

    func finishGitFlow(_ plan: GitFlowFinishPlan) async -> Bool {
        do {
            let result = try await GitFlowService().finish(plan, in: repositoryURL)
            let mergeMessage = "Finish \(plan.kind.displayName.lowercased()) '\(plan.sourceBranch)'"
            var undoOperations: [GitUndoOperation] = [
                .requireCleanWorkingTree
            ]
            if result.didDeleteSourceBranch {
                undoOperations.append(.requireLocalBranchAbsent(plan.sourceBranch))
            } else {
                undoOperations.append(
                    .requireLocalBranchTip(name: plan.sourceBranch, expectedTip: result.sourceTip)
                )
            }
            undoOperations.append(contentsOf: [
                .checkoutRef(ref: plan.targetBranch),
                .resetHead(
                    target: result.targetTipBeforeMerge,
                    mode: .hard,
                    expectedHead: result.targetTipAfterMerge
                )
            ])
            if result.didDeleteSourceBranch {
                undoOperations.append(
                    .createLocalBranch(name: plan.sourceBranch, startPoint: result.sourceTip, checkout: true)
                )
            } else {
                undoOperations.append(.checkoutRef(ref: plan.sourceBranch))
            }

            var redoOperations: [GitUndoOperation] = [
                .requireCleanWorkingTree,
                .requireLocalBranchTip(name: plan.sourceBranch, expectedTip: result.sourceTip),
                .checkoutRef(ref: plan.targetBranch),
                .requireHead(result.targetTipBeforeMerge),
                .mergeNoFastForward(branch: plan.sourceBranch, message: mergeMessage)
            ]
            if result.didDeleteSourceBranch {
                redoOperations.append(
                    .deleteLocalBranch(name: plan.sourceBranch, force: false, expectedTip: result.sourceTip)
                )
            }

            await MainActor.run {
                undoManager.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Finish \(plan.kind.displayName) \(plan.sourceBranch)",
                        undoOperation: .sequence(undoOperations),
                        redoOperation: .sequence(redoOperations),
                        confirmationMessage: "Undo will move '\(plan.targetBranch)' back to its previous commit. Continue?"
                    )
                )
                gitFlowCurrentBranch = plan.targetBranch
                selectedItem = .branch(plan.targetBranch)
                if let warning = result.deletionWarning {
                    syncState.showError(warning)
                }
            }
            await refreshAfterGitFlowMutation()
            return true
        } catch {
            let mergeInProgress = await GitStatusService.shared.isMergeInProgress(in: repositoryURL)
            await MainActor.run {
                if mergeInProgress {
                    selectedItem = .item(.fileStatus)
                    gitFlowCurrentBranch = plan.targetBranch
                }
                syncState.showError(error.localizedDescription)
            }
            await refreshAfterGitFlowMutation()
            return false
        }
    }

    private func refreshAfterGitFlowMutation() async {
        await GitStatusService.shared.invalidateBranchListCache(in: repositoryURL)
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
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
