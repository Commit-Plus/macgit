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

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension SidebarView {
    var dropActions: SidebarDropActions {
        SidebarDropActions(
            activePayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
            canAccept: canAcceptDrop,
            handlePayload: { payload, target, optionKeyPressed in
                activeBranchDragPayload = nil
                GitDragPayloadStore.clear(ifMatching: payload)
                handleDrop([payload], target: target, optionKeyPressed: optionKeyPressed)
            },
            handleProviders: { providers, target, optionKeyPressed in
                activeBranchDragPayload = nil
                GitDragPayloadStore.clear()
                return handleDrop(
                    providers,
                    target: target,
                    optionKeyPressed: optionKeyPressed
                )
            },
            clearPayload: { payload in
                activeBranchDragPayload = nil
                if let payload {
                    GitDragPayloadStore.clear(ifMatching: payload)
                } else {
                    GitDragPayloadStore.clear()
                }
                clearDropHover()
            }
        )
    }

    func updateBranchesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .branchesHeader
            activeDropLabel = draggedRemoteBranch == nil ? "Create Branch" : "Check Out"
        } else if activeDropTarget == .branchesHeader {
            clearDropHover()
        }
    }

    func updateTagsHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .tagsHeader
            activeDropLabel = "Create Tag"
        } else if activeDropTarget == .tagsHeader {
            clearDropHover()
        }
    }

    func updateTagDropTarget(_ tag: String, isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .tag(name: tag)
            activeDropLabel = "Move Tag"
        } else if activeDropTarget == .tag(name: tag) {
            clearDropHover()
        }
    }

    func updateRemotesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .remotesHeader
            activeDropLabel = "Push Branch"
        } else if activeDropTarget == .remotesHeader {
            clearDropHover()
        }
    }

    func updateStashesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .stashesHeader
            let fileCount = currentFileDragCount()
            activeDropLabel = fileCount > 1 ? "Stash \(fileCount) files" : "Stash"
        } else if activeDropTarget == .stashesHeader {
            clearDropHover()
        }
    }

    func currentFileDragCount() -> Int {
        if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
           !payload.files.isEmpty {
            return payload.files.count
        }
        return 0
    }

    func updateCurrentBranchDropTarget(isTargeted: Bool) {
        isCurrentBranchDropTargeted = isTargeted
    }

    func makeBranchItemProvider(branchName: String) -> NSItemProvider {
        let payload = makeBranchPayload(branchName: branchName)

        let provider = NSItemProvider()
        if let data = try? GitDragPayload.encodeTransferData(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
                visibility: .all
            ) { completionHandler in
                completionHandler(data, nil)
                return nil
            }
        }
        provider.register(payload)
        provider.suggestedName = branchName
        return provider
    }

    func makeBranchPayload(branchName: String) -> GitDragPayload {
        let payload = GitDragPayload.branch(
            branchName,
            repositoryURL: repositoryURL
        )
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    func makeRemoteBranchPayload(remoteBranch: String) -> GitDragPayload {
        let payload = GitDragPayload.remoteBranch(remoteBranch, repositoryURL: repositoryURL)
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    func makeStashPayload(ref: String) -> GitDragPayload {
        let payload = GitDragPayload.stash(ref, repositoryURL: repositoryURL)
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    var draggedRemoteBranch: String? {
        let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload()
        return payload?.remoteBranch
    }

    func finishBranchDrag(_ payload: GitDragPayload) {
        activeBranchDragPayload = nil
        GitDragPayloadStore.clear(ifMatching: payload)
    }

    func finishRemoteBranchDrag(_ remoteBranch: String) {
        guard let payload = activeBranchDragPayload,
              payload.remoteBranch == remoteBranch
        else {
            return
        }
        activeBranchDragPayload = nil
        GitDragPayloadStore.clear(ifMatching: payload)
        clearDropHover()
    }

    func clearDropHover() {
        activeDropTarget = nil
        activeDropLabel = nil
    }

    func canAcceptDrop(
        _ payload: GitDragPayload,
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) -> Bool {
        if case .accept = GitDragDropPolicy.decision(
            for: payload,
            target: target,
            receivingRepositoryURL: repositoryURL,
            optionKeyPressed: optionKeyPressed
        ) {
            return true
        }

        return false
    }

    func handleDrop(
        _ items: [GitDragPayload],
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) {
        defer { clearDropHover() }

        guard let payload = items.first else { return }

        switch GitDragDropPolicy.decision(
            for: payload,
            target: target,
            receivingRepositoryURL: repositoryURL,
            optionKeyPressed: optionKeyPressed
        ) {
        case .accept(let request):
            if case .checkoutRemoteBranch = request {
                expandBranchesSection()
            }
            onRequestDragDrop(request)
        case .reject(let reason):
            guard payload.remoteBranch == nil else { return }
            errorMessage = reason
            showingError = true
        }
    }

    func handleDrop(
        _ providers: [NSItemProvider],
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) -> Bool {
        guard let provider = providers.first else { return false }

        GitDragPayloadItemProviderLoader.load(from: provider) { result in
            Task { @MainActor in
                switch result {
                case .success(let payload):
                    handleDrop(
                        [payload],
                        target: target,
                        optionKeyPressed: optionKeyPressed
                    )
                case .failure(let error):
                    clearDropHover()
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }

        return true
    }

    func currentBranchDropLabel() -> String {
        let activePayload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload()
        if case .commits = activePayload?.content {
            return "Cherry-pick"
        }
        if case .branch = activePayload?.content {
            return NSEvent.modifierFlags.contains(.option) ? "Rebase" : "Merge"
        }

        if NSEvent.modifierFlags.contains(.option) {
            return "Rebase or Cherry-pick"
        }
        return "Merge or Cherry-pick"
    }

    func makeStashItemProvider(ref: String) -> NSItemProvider {
        let payload = makeStashPayload(ref: ref)

        let provider = NSItemProvider()
        if let data = try? GitDragPayload.encodeTransferData(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
                visibility: .all
            ) { completionHandler in
                completionHandler(data, nil)
                return nil
            }
        }
        provider.register(payload)
        provider.suggestedName = ref
        return provider
    }
}
