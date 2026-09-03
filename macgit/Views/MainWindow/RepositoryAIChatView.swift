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

struct RepositoryAIChatView: View {
    @ObservedObject var controller: RepositoryAIChatController
    @ObservedObject var providerController: AIProviderController
    let accessDecision: FeatureAccessDecision
    let isSignedIn: Bool
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(controller.conversationTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button("Conversation history", systemImage: "clock.arrow.circlepath") { }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                    .help("Conversation History — Coming Soon")

                Button("New conversation", systemImage: "plus", action: controller.startNewConversation)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(controller.isRunning)
                    .help("New Conversation")
            }

            if controller.isChoosingCommit {
                RepositoryAICommitPickerView(
                    controller: controller,
                    onSelectCommit: explainCommit,
                    onSubmitReference: explainCommitReference
                )
            } else if controller.isChoosingFile {
                RepositoryAIFilePickerView(controller: controller, onSelect: reviewFile)
            } else if controller.messages.isEmpty {
                welcomeContent
            } else {
                transcript
            }

            if !controller.isChoosingCommit && !controller.isChoosingFile {
                composer
            }
        }
        .padding(16)
        .task {
            await providerController.refreshAvailability()
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Repository AI", systemImage: "sparkles")
                    .font(.headline)
                Text("Review local changes or explain a commit using bounded, read-only Git context.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: runReviewChanges) {
                quickActionLabel(
                    title: "Review changes",
                    detail: "Find bugs, regressions, and missing tests",
                    systemImage: "checkmark.bubble"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isRunning)

            Button(action: runExplainCommit) {
                quickActionLabel(
                    title: "Explain commit",
                    detail: "Summarize intent, behavior, and risks",
                    systemImage: "text.magnifyingglass"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isRunning)

            Button(action: runReviewFile) {
                quickActionLabel(
                    title: "Review file",
                    detail: "Inspect a staged or working-tree file diff",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isRunning)

            if !accessDecision.isAllowed {
                Button(accessButtonTitle, systemImage: "lock.open", action: onRequestAccess)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(controller.messages) { message in
                        RepositoryAIMessageView(message: message)
                            .id(message.id)
                    }

                    if controller.isRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reading repository context…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Cancel", systemImage: "xmark", action: controller.cancelActiveRequest)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .onChange(of: controller.messages.count) {
                guard let lastID = controller.messages.last?.id else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about this context", text: $controller.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.primary.opacity(0.075))
                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                }
                .disabled(controller.isRunning)
                .onSubmit(submitDraft)

            Button("Send question", systemImage: "arrow.up", action: submitDraft)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!controller.canSubmit)
                .help("Send")
        }
    }

    private var accessButtonTitle: String {
        isSignedIn ? "Upgrade to use Repository AI" : "Sign in to use Repository AI"
    }

    private func quickActionLabel(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.075))
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func runReviewChanges() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.reviewChanges() }
    }

    private func runExplainCommit() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.prepareCommitExplanation() }
    }

    private func runReviewFile() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.prepareFileReview() }
    }

    private func reviewFile(_ file: RepositoryAIFileReference) {
        Task { await controller.reviewFile(file) }
    }

    private func explainCommit(_ commit: RepositoryAICommitChoice) {
        Task { await controller.explainCommit(commit) }
    }

    private func explainCommitReference() {
        Task { await controller.explainCommitReference() }
    }

    private func submitDraft() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.submitDraft() }
    }
}
