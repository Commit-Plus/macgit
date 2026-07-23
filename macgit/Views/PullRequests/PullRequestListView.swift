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

import MarkdownUI
import SwiftUI

struct PullRequestListView: View {
    @ObservedObject var controller: PullRequestController
    let repositoryURL: URL
    var accountConnectionErrorMessage: String? = nil
    var onReconnectAccount: () -> Void = {}
    @State private var pendingCommentPullRequest: PullRequestSummary?
    @State private var selectedPullRequestID: Int?

    var body: some View {
        VStack(spacing: 0) {
            header

            if controller.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = controller.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.headline)
                    if controller.needsAccountConnectionAction {
                        Text("Pull requests require an OAuth account over HTTPS. SSH keys are only used for Git fetch and push.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 440)

                        HStack(spacing: 10) {
                            Button(controller.accountConnectionActionTitle, action: onReconnectAccount)
                            Button("Reload", systemImage: "arrow.clockwise") {
                                Task { await controller.loadPullRequests(repositoryURL: repositoryURL, forceRefresh: true) }
                            }
                            .disabled(controller.isLoading)
                        }
                        if let accountConnectionErrorMessage {
                            Text(accountConnectionErrorMessage)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.visibleItems.isEmpty {
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedPullRequestID != nil {
                PersistentHSplit(
                    autosaveName: "PullRequestMainSplit",
                    left: {
                        pullRequestListPanel
                    },
                    right: {
                        detailPanel
                            .frame(minWidth: 420, idealWidth: 600, maxWidth: .infinity)
                    }
                )
            } else {
                pullRequestListPanel
            }
        }
        .sheet(item: $pendingCommentPullRequest) { pullRequest in
            PullRequestCommentSheet(
                pullRequest: pullRequest,
                isSubmitting: controller.isPerformingAction,
                onCancel: { pendingCommentPullRequest = nil },
                onSubmit: { body in
                    Task {
                        await controller.comment(on: pullRequest, body: body)
                        if controller.detailErrorMessage == nil {
                            pendingCommentPullRequest = nil
                        }
                    }
                }
            )
        }
        .alert("Pull Request", isPresented: detailErrorPresented) {
            Button("OK", role: .cancel) {
                controller.detailErrorMessage = nil
            }
        } message: {
            Text(controller.detailErrorMessage ?? "Could not load pull request details.")
        }
        .task(id: repositoryURL) {
            closeDetail()
            await controller.loadPullRequests(repositoryURL: repositoryURL)
        }
        .onChange(of: controller.stateFilter) { _, _ in
            closeDetail()
            Task { await controller.loadPullRequests(repositoryURL: repositoryURL) }
        }
    }

    private var pullRequestListPanel: some View {
        VStack(spacing: 0) {
            List(controller.visibleItems) { item in
                PullRequestRow(
                    summary: item,
                    isBusy: controller.isPerformingAction,
                    onOpen: { controller.openInBrowser(item) },
                    onCheckout: {
                        Task { await controller.checkout(item) }
                    },
                    onComment: {
                        pendingCommentPullRequest = item
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPullRequestID = item.id
                    controller.clearSelectedDetail()
                    Task { await controller.loadPullRequestDetail(item) }
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.plain)

            paginationFooter
        }
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if controller.isLoadingDetail,
           controller.selectedDetail?.id != selectedPullRequestID {
            ProgressView("Loading pull request…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = controller.selectedDetail,
                  detail.id == selectedPullRequestID {
            PullRequestDetailPane(
                detail: detail,
                onClose: closeDetail,
                onOpenPullRequest: { controller.openInBrowser(detail.summary) },
                onOpenChanges: { controller.openChangesInBrowser(detail) }
            )
        } else {
            ProgressView("Loading pull request…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closeDetail() {
        selectedPullRequestID = nil
        controller.clearSelectedDetail()
    }

    private var detailErrorPresented: Binding<Bool> {
        Binding(
            get: { controller.detailErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    controller.detailErrorMessage = nil
                }
            }
        )
    }

    private var header: some View {
        HStack {
            Text("Pull Requests")
                .font(.headline)
            Spacer()
            Picker("Filter", selection: $controller.stateFilter) {
                ForEach(PullRequestListFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            Toggle("Created by me", isOn: $controller.createdByMeOnly)
                .disabled(controller.selectedProviderAccountUsername == nil)
            Button("Create Pull Request") {
                Task { await controller.presentCreatePullRequest() }
            }
            .disabled(controller.isLoading || controller.errorMessage != nil)
            Button("Refresh pull requests", systemImage: "arrow.clockwise") {
                Task { await controller.loadPullRequests(repositoryURL: repositoryURL, forceRefresh: true) }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading)
            .help("Refresh pull requests")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var paginationFooter: some View {
        HStack(spacing: 10) {
            Button("Previous page", systemImage: "chevron.left") {
                Task { await controller.loadPreviousPage(repositoryURL: repositoryURL) }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading || !controller.hasPreviousPage)
            .help("Previous page")

            Text("Page \(controller.currentPage)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 54)

            Button("Next page", systemImage: "chevron.right") {
                Task { await controller.loadNextPage(repositoryURL: repositoryURL) }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading || !controller.hasNextPage)
            .help("Next page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var emptyStateMessage: String {
        switch controller.stateFilter {
        case .all:
            "No pull requests"
        case .open:
            "No open pull requests"
        case .closed:
            "No closed pull requests"
        }
    }
}

private struct PullRequestRow: View {
    let summary: PullRequestSummary
    let isBusy: Bool
    let onOpen: () -> Void
    let onCheckout: () -> Void
    let onComment: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(summary.number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Image(systemName: pullRequestIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pullRequestTint)
                .frame(width: 18, height: 22)
                .help(pullRequestHelp)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Image(systemName: combinedStatusIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(combinedStatusTint)
                        .help(combinedStatusHelp)
                }

                Text("\(summary.source.ref) -> \(summary.target.ref)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text("#\(summary.number) opened \(relativeString(for: summary.createdAt)) by \(summary.author.username)")
                    Text("updated \(relativeString(for: summary.updatedAt))")
                    if let mergedAt = summary.mergedAt {
                        Text("merged \(relativeString(for: mergedAt))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Checkout Pull Request", action: onCheckout)
                Button("Add Comment", action: onComment)
                Button("Open in Browser", action: onOpen)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .disabled(isBusy)

            Button("Open in browser", systemImage: "safari", action: onOpen)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Open in browser")
        }
        .padding(.vertical, 8)
    }

    private var pullRequestIcon: String {
        switch summary.state {
        case .open, .draft:
            "arrow.triangle.pull"
        case .closed:
            "xmark.circle"
        case .merged:
            "arrow.triangle.merge"
        }
    }

    private var pullRequestTint: Color {
        switch summary.state {
        case .open:
            .green
        case .draft:
            .orange
        case .closed:
            .red
        case .merged:
            .purple
        }
    }

    private var pullRequestHelp: String {
        switch summary.state {
        case .open:
            "Open pull request"
        case .draft:
            "Draft pull request"
        case .closed:
            "Closed pull request"
        case .merged:
            "Merged pull request"
        }
    }

    private var combinedStatusIcon: String {
        if summary.checkState == .success && summary.mergeReadiness == .ready {
            return "checkmark"
        }
        if summary.checkState == .failure || summary.checkState == .error || summary.mergeReadiness == .blocked {
            return "xmark"
        }
        switch summary.checkState {
        case .pending:
            return "clock"
        case .unknown, .noChecks, .success:
            return "questionmark"
        case .failure, .error:
            return "xmark"
        }
    }

    private var combinedStatusTint: Color {
        if summary.checkState == .success && summary.mergeReadiness == .ready {
            return .green
        }
        if summary.checkState == .failure || summary.checkState == .error || summary.mergeReadiness == .blocked {
            return .red
        }
        switch summary.checkState {
        case .pending:
            return .orange
        case .unknown, .noChecks, .success:
            return .secondary
        case .failure, .error:
            return .red
        }
    }

    private var combinedStatusHelp: String {
        "Checks: \(summary.checkState.rawValue). Merge: \(summary.mergeReadiness.rawValue)."
    }

    private func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct PullRequestDetailPane: View {
    let detail: PullRequestDetail
    let onClose: () -> Void
    let onOpenPullRequest: () -> Void
    let onOpenChanges: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadata
                    description
                    assignees
                    comments
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.summary.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text("#\(detail.summary.number) \(detail.summary.source.ref) -> \(detail.summary.target.ref)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Close detail", systemImage: "xmark", action: onClose)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Close pull request detail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            Label(detail.summary.author.username, systemImage: "person")
            Label(detail.summary.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            if detail.body.isEmpty {
                Text("No description")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Markdown(detail.body)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
            }
        }
    }

    private var assignees: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assignees")
                .font(.headline)
            if detail.assignees.isEmpty {
                Text("No assignees")
                    .foregroundStyle(.secondary)
            } else {
                FlowRow(items: detail.assignees.map(\.username)) { username in
                    Label(username, systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.headline)
            if detail.comments.isEmpty {
                Text("No comments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(comment.author.username)
                                .font(.subheadline.weight(.semibold))
                            Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Markdown(comment.body)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open PR", systemImage: "safari", action: onOpenPullRequest)
            Button("Open Changes", systemImage: "doc.text.magnifyingglass", action: onOpenChanges)
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
}

private struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        HStack {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
