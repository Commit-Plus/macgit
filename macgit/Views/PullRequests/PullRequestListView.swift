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

struct PullRequestListView: View {
    @ObservedObject var controller: PullRequestController
    let repositoryURL: URL
    var onConnectAccount: () -> Void = {}
    @State private var pendingCommentPullRequest: PullRequestSummary?

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
                    if errorMessage == "Connect Account..." || errorMessage == "Reconnect..." {
                        Button(errorMessage, action: onConnectAccount)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.visibleItems.isEmpty {
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                        .onTapGesture(count: 2) {
                            Task { await controller.loadPullRequestDetail(item) }
                        }
                        .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)

                    paginationFooter
                }
            }
        }
        .overlay {
            if controller.isLoadingDetail {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: detailSheetPresented) {
            if let detail = controller.selectedDetail {
                PullRequestDetailSheet(
                    detail: detail,
                    onOpenPullRequest: { controller.openInBrowser(detail.summary) },
                    onOpenChanges: { controller.openChangesInBrowser(detail) }
                )
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
            await controller.loadPullRequests(repositoryURL: repositoryURL)
        }
        .onChange(of: controller.stateFilter) { _, _ in
            Task { await controller.loadPullRequests(repositoryURL: repositoryURL) }
        }
    }

    private var detailSheetPresented: Binding<Bool> {
        Binding(
            get: { controller.selectedDetail != nil },
            set: { isPresented in
                if !isPresented {
                    controller.clearSelectedDetail()
                }
            }
        )
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
                Task { await controller.loadPullRequests(repositoryURL: repositoryURL) }
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

private struct PullRequestDetailSheet: View {
    let detail: PullRequestDetail
    let onOpenPullRequest: () -> Void
    let onOpenChanges: () -> Void
    @Environment(\.dismiss) private var dismiss

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
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.summary.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Text("#\(detail.summary.number) \(detail.summary.source.ref) -> \(detail.summary.target.ref)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                MarkdownText(detail.body)
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
                        MarkdownText(comment.body)
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
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
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

private struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownBlock.blocks(from: source)) { block in
                switch block.kind {
                case .paragraph(let text):
                    Text(attributedMarkdown(text))
                        .font(.body)
                        .textSelection(.enabled)
                case .checklist(let isChecked, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: isChecked ? "checkmark.square" : "square")
                            .foregroundStyle(isChecked ? .green : .secondary)
                        Text(attributedMarkdown(text))
                            .font(.body)
                            .textSelection(.enabled)
                    }
                case .code(let language, let text):
                    VStack(alignment: .leading, spacing: 6) {
                        if let language, !language.isEmpty {
                            Text(language)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributedMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }
}

private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case paragraph(String)
        case checklist(isChecked: Bool, text: String)
        case code(language: String?, text: String)
    }

    static func blocks(from source: String) -> [MarkdownBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLanguage: String?
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let text = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(MarkdownBlock(kind: .paragraph(text)))
            }
            paragraphLines.removeAll()
        }

        func flushCodeBlock() {
            blocks.append(MarkdownBlock(kind: .code(
                language: codeLanguage,
                text: codeLines.joined(separator: "\n")
            )))
            codeLanguage = nil
            codeLines.removeAll()
        }

        for line in lines {
            if line.hasPrefix("```") {
                if isInCodeBlock {
                    flushCodeBlock()
                    isInCodeBlock = false
                } else {
                    flushParagraph()
                    isInCodeBlock = true
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }

            if isInCodeBlock {
                codeLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                continue
            }

            if let checklist = checklistItem(from: line) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .checklist(
                    isChecked: checklist.isChecked,
                    text: checklist.text
                )))
                continue
            }

            paragraphLines.append(line)
        }

        if isInCodeBlock {
            flushCodeBlock()
        }
        flushParagraph()
        return blocks
    }

    private static func checklistItem(from line: String) -> (isChecked: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes: [(String, Bool)] = [
            ("- [x] ", true),
            ("- [X] ", true),
            ("* [x] ", true),
            ("* [X] ", true),
            ("- [ ] ", false),
            ("* [ ] ", false),
            ("[x] ", true),
            ("[X] ", true),
            ("[ ] ", false),
        ]
        for (prefix, isChecked) in prefixes where trimmed.hasPrefix(prefix) {
            return (isChecked, String(trimmed.dropFirst(prefix.count)))
        }
        return nil
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
