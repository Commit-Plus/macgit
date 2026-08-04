//
//  ConflictMergeToolView.swift
//  macgit
//

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

struct ConflictMergeToolView: View {
    @State private var allConflictFiles: [StatusFile]
    let repositoryURL: URL
    let onResolved: () -> Void
    let onClose: () -> Void

    @State private var selectedFile: StatusFile
    @State private var document: ConflictResolutionDocument?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedConflictSectionIndex: Int?
    @State private var hasUnsavedChanges = false
    @State private var resultText = ""
    @State private var scrollController = SyncedScrollController()
    @State private var showingUnresolvedConflictsAlert = false
    @State private var resolvedFiles: [StatusFile] = []
    @State private var mergeMessage = ""
    @State private var isMergeInProgress = false
    @State private var isPerformingMergeAction = false
    @State private var showingAbortConfirmation = false
    @ObservedObject private var integrationSettings = IntegrationSettingsStore.shared

    init(
        allConflictFiles: [StatusFile],
        selectedFile: StatusFile,
        repositoryURL: URL,
        onResolved: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._allConflictFiles = State(initialValue: allConflictFiles)
        self.repositoryURL = repositoryURL
        self.onResolved = onResolved
        self.onClose = onClose
        self._selectedFile = State(initialValue: selectedFile)
    }

    var body: some View {
        ZStack {
            rootView
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("")
        .toolbar { toolbarContent }
        .task(id: selectedFile.id) {
            await loadDocument(for: selectedFile)
        }
        .task {
            await loadMergeContext()
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .alert("Unresolved Conflicts", isPresented: $showingUnresolvedConflictsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There are still conflict blocks that need to be resolved before merging.")
        }
        .confirmationDialog(
            "Abort Merge?",
            isPresented: $showingAbortConfirmation,
            titleVisibility: .visible
        ) {
            Button("Abort Merge", role: .destructive) {
                Task { await abortMerge() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the repository to its state before the merge started.")
        }
    }

    // MARK: - Root

    @ViewBuilder
    private var rootView: some View {
        NavigationSplitView {
            sidebarPane
        } detail: {
            detailPane
        }
    }

    // MARK: - Sidebar

    private var sidebarPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Conflicted Files (\(allConflictFiles.count))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                List(selection: $selectedFile) {
                    if allConflictFiles.isEmpty {
                        Label("No conflicted files", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allConflictFiles) { file in
                            Label(file.displayName, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(file.path)
                                .tag(file)
                        }
                    }
                }
                .listStyle(.sidebar)
                .disabled(isSaving || isPerformingMergeAction)
            }
            .frame(minHeight: 0, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text("Resolved Files (\(resolvedFiles.count))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                List {
                    if resolvedFiles.isEmpty {
                        Text("Files you resolve appear here")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(resolvedFiles) { file in
                            Label(file.displayName, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .help(file.path)
                        }
                    }
                }
                .listStyle(.sidebar)
                .disabled(isSaving || isPerformingMergeAction)
            }
            .frame(minHeight: 0, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Message")
                    .font(.headline)

                TextEditor(text: $mergeMessage)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .frame(minHeight: 100, idealHeight: 120, maxHeight: 160)
                    .disabled(isPerformingMergeAction)
                    .accessibilityLabel("Merge commit message")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            Color(nsColor: .controlBackgroundColor)
                .frame(height: 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }

            if allConflictFiles.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    message: "All conflicts resolved",
                    detail: isMergeInProgress
                        ? "Review the commit message, then commit the merge."
                        : "All files have been successfully resolved. You can close this window."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView("Loading conflict details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = document {
                threePanelView(document: document)
            } else {
                EmptyStateView(
                    icon: "arrow.triangle.merge",
                    message: "No text conflicts found",
                    detail: "This file could not be loaded into the merge tool."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Three Panel View

    private func threePanelView(document: ConflictResolutionDocument) -> some View {
        let panels = ConflictPanelAlignment(document: document)
        let incomingData = PanelData(rows: panels.incomingRows)
        let currentData = PanelData(rows: panels.currentRows)

        return VStack(spacing: 0) {
            // Top row: Incoming | Current
            HStack(alignment: .top, spacing: 0) {
                panelView(
                    title: "Incoming",
                    scrollID: "incoming",
                    selectionSide: .incoming,
                    data: incomingData,
                    highlightColor: Color(nsColor: .systemGreen).opacity(0.7)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                panelView(
                    title: "Current",
                    scrollID: "current",
                    selectionSide: .current,
                    data: currentData,
                    highlightColor: Color(nsColor: .systemBlue).opacity(0.7)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom row: Result
            ConflictResultEditorView(
                text: $resultText,
                fileExtension: selectedFile.fileExtension,
                baselineText: document.currentContent,
                isDisabled: isSaving || isPerformingMergeAction,
                scrollController: scrollController
            )
                .onChange(of: resultText) { _, newValue in
                    updateManualResult(newValue)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func panelView(
        title: String,
        scrollID: String,
        selectionSide: ConflictPaneSelectionSide?,
        data: PanelData,
        highlightColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                if let selectionSide {
                    headerSelectionControl(for: selectionSide)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.04))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator.opacity(0.5))
                    .frame(height: 0.5)
            }

            // Content
            SyncedScrollView(id: scrollID, controller: scrollController) {
                ConflictCodeView(
                    rows: data.rows,
                    fileExtension: selectedFile.fileExtension,
                    highlightColor: highlightColor,
                    selectionSide: selectionSide,
                    isSelected: { sectionIndex in
                        guard let selectionSide else { return false }
                        return isConflictSideSelected(selectionSide, sectionIndex: sectionIndex)
                    },
                    onSelectionChanged: { sectionIndex, isSelected in
                        guard let selectionSide else { return }
                        setConflictSide(selectionSide, selected: isSelected, sectionIndex: sectionIndex)
                    },
                    onResolveConflict: { sectionIndex, resolution in
                        resolveConflict(sectionIndex: sectionIndex, using: resolution)
                    },
                    onResolveAll: { resolution in
                        resolveAllConflicts(using: resolution)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Panel Data

    private struct PanelData {
        let rows: [ConflictCodeLine]
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if let document = document, !allConflictFiles.isEmpty {
                let navigation = navigationState(for: document)
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Button {
                            navigateToConflict(navigation.previousSectionIndex, in: document)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 22)
                        }
                        .disabled(!navigation.canNavigatePrevious)
                        .accessibilityLabel("Previous conflict")

                        Divider()
                            .frame(height: 12)

                        Button {
                            navigateToConflict(navigation.nextSectionIndex, in: document)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 22)
                        }
                        .disabled(!navigation.canNavigateNext)
                        .accessibilityLabel("Next conflict")
                    }
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )

                    Button("External Tool", systemImage: "arrow.up.forward.app") {
                        Task { await openInExternalTool() }
                    }
                    .disabled(
                        integrationSettings.selectedApplication(for: .merge) == nil
                            || isSaving
                            || isPerformingMergeAction
                    )
                    .help("Open in External Tool")
                }
            }
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 16) {
                if allConflictFiles.isEmpty {
                    Text("All files resolved")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(shortenedFilePath(selectedFile.path))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedFile.path)
                        .accessibilityLabel(selectedFile.path)
                }

                if let document = document, !allConflictFiles.isEmpty {
                    let navigation = navigationState(for: document)
                    Text(conflictStatusText(navigation: navigation))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Abort Merge", role: .destructive) {
                showingAbortConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(!isMergeInProgress || isSaving || isPerformingMergeAction)
        }

        ToolbarSpacer(.fixed, placement: .confirmationAction)

        ToolbarItem(placement: .confirmationAction) {
            if allConflictFiles.isEmpty {
                Button(isMergeInProgress ? "Commit Merge" : "Close") {
                    if isMergeInProgress {
                        Task { await commitMerge() }
                    } else {
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    isPerformingMergeAction
                        || (isMergeInProgress && mergeMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            } else {
                Button {
                    if hasUnresolvedConflicts {
                        showingUnresolvedConflictsAlert = true
                    } else {
                        Task {
                            await saveAndAdvance()
                        }
                    }
                } label: {
                    Text(isSaving ? "Resolving…" : "Merge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hasUnresolvedConflicts ? Color.primary : Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(hasUnresolvedConflicts ? Color.clear : Color.accentColor)
                        )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .disabled(isSaving || isPerformingMergeAction)
            }
        }
    }

    // MARK: - Helpers

    private func headerSelectionControl(for side: ConflictPaneSelectionSide) -> some View {
        let selected = allConflictsSelected(side)

        return Button(
            selected
                ? "Clear all \(side.title) conflict blocks"
                : "Select all \(side.title) conflict blocks",
            systemImage: selected ? "checkmark.square.fill" : "square"
        ) {
            toggleAllConflicts(side)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .secondary)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func navigationState(for document: ConflictResolutionDocument) -> ConflictNavigationState {
        ConflictNavigationState(document: document, currentSectionIndex: selectedConflictSectionIndex)
    }

    private func conflictStatusText(navigation: ConflictNavigationState) -> String {
        guard let currentOrdinal = navigation.currentOrdinal else {
            return "All conflicts resolved"
        }

        return "Unresolved \(currentOrdinal) of \(navigation.remainingCount)"
    }

    private func shortenedFilePath(_ path: String, maxLength: Int = 44) -> String {
        guard path.count > maxLength else { return path }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = components.first, let last = components.last, components.count > 2 else {
            return middleTruncated(path, maxLength: maxLength)
        }

        let shortened = "\(first)/.../\(last)"
        return middleTruncated(shortened, maxLength: maxLength)
    }

    private func middleTruncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 3 else { return text }

        let visibleCharacterCount = maxLength - 3
        let prefixCount = visibleCharacterCount / 2
        let suffixCount = visibleCharacterCount - prefixCount
        return "\(text.prefix(prefixCount))...\(text.suffix(suffixCount))"
    }

    private func navigateToConflict(_ sectionIndex: Int?, in document: ConflictResolutionDocument) {
        guard let sectionIndex else { return }
        selectedConflictSectionIndex = sectionIndex
        scrollToConflict(sectionIndex, in: document)
    }

    private func isConflictSideSelected(
        _ side: ConflictPaneSelectionSide,
        sectionIndex: Int
    ) -> Bool {
        guard let document,
              document.sections.indices.contains(sectionIndex),
              document.sections[sectionIndex].isConflict else {
            return false
        }

        let section = document.sections[sectionIndex]
        switch side {
        case .incoming:
            return section.isIncomingSelected
        case .current:
            return section.isCurrentSelected
        }
    }

    private func setConflictSide(
        _ side: ConflictPaneSelectionSide,
        selected: Bool,
        sectionIndex: Int
    ) {
        guard var document, document.sections.indices.contains(sectionIndex) else {
            return
        }

        switch side {
        case .incoming:
            document.sections[sectionIndex].setIncomingSelected(selected)
        case .current:
            document.sections[sectionIndex].setCurrentSelected(selected)
        }

        document.manualResolvedText = nil
        hasUnsavedChanges = true
        self.document = document
        resultText = document.resolvedText
        focusCurrentConflict(in: document, preferredSectionIndex: sectionIndex, scroll: false)
    }

    private func resolveConflict(
        sectionIndex: Int,
        using resolution: ConflictSectionResolution
    ) {
        guard var document,
              document.sections.indices.contains(sectionIndex),
              document.sections[sectionIndex].isConflict else {
            return
        }

        document.sections[sectionIndex].manualResult = ""
        document.sections[sectionIndex].resolution = resolution
        document.manualResolvedText = nil
        hasUnsavedChanges = true
        self.document = document
        resultText = document.resolvedText
        focusCurrentConflict(in: document, preferredSectionIndex: sectionIndex, scroll: false)
    }

    private func resolveAllConflicts(using resolution: ConflictSectionResolution) {
        guard var document else { return }

        document.selectAllConflicts(resolution)
        hasUnsavedChanges = true
        self.document = document
        resultText = document.resolvedText
        focusCurrentConflict(in: document, preferredSectionIndex: selectedConflictSectionIndex, scroll: false)
    }

    private func allConflictsSelected(_ side: ConflictPaneSelectionSide) -> Bool {
        document?.allConflictsSelect(side.resolution) ?? false
    }

    private func toggleAllConflicts(_ side: ConflictPaneSelectionSide) {
        guard var document else { return }

        let shouldSelect = !document.allConflictsSelect(side.resolution)
        document.setAllConflictsSelected(shouldSelect, for: side.resolution)
        hasUnsavedChanges = true
        self.document = document
        resultText = document.resolvedText
        focusCurrentConflict(in: document, preferredSectionIndex: selectedConflictSectionIndex, scroll: false)
    }

    private func updateManualResult(_ text: String) {
        guard var document, text != document.resolvedText else { return }

        document.manualResolvedText = text
        self.document = document
        hasUnsavedChanges = true
        focusCurrentConflict(in: document, preferredSectionIndex: nil, scroll: false)
    }

    private func focusCurrentConflict(
        in document: ConflictResolutionDocument,
        preferredSectionIndex: Int?,
        scroll: Bool
    ) {
        let navigation = ConflictNavigationState(
            document: document,
            currentSectionIndex: preferredSectionIndex
        )
        selectedConflictSectionIndex = navigation.currentSectionIndex

        guard scroll else { return }

        if let currentSectionIndex = navigation.currentSectionIndex {
            scrollToConflict(currentSectionIndex, in: document)
        } else {
            scrollController.scrollToTop()
        }
    }

    private func scrollToConflict(_ sectionIndex: Int, in document: ConflictResolutionDocument) {
        let panels = ConflictPanelAlignment(document: document)
        guard let rowIndex = panels.rowIndex(forConflictSectionIndex: sectionIndex) else { return }
        let offset = ConflictCodeView.verticalPadding + CGFloat(rowIndex) * ConflictCodeView.rowHeight()

        DispatchQueue.main.async {
            scrollController.scrollToVerticalOffset(offset)
        }
    }

    private var hasUnresolvedConflicts: Bool {
        guard let document = document else { return false }
        guard document.manualResolvedText == nil else { return false }
        return document.sections.contains { section in
            section.isConflict && !section.isIncomingSelected && !section.isCurrentSelected
        }
    }

    private func loadDocument(for file: StatusFile) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedDocument = try await GitStatusService.shared.conflictDocument(for: file, in: repositoryURL)
            await MainActor.run {
                document = loadedDocument
                resultText = loadedDocument.resolvedText
                hasUnsavedChanges = false
                focusCurrentConflict(in: loadedDocument, preferredSectionIndex: nil, scroll: true)
            }
        } catch is CancellationError {
            // Task was cancelled, likely because user switched files. Ignore.
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func loadMergeContext() async {
        async let mergeInProgress = GitStatusService.shared.isMergeInProgress(in: repositoryURL)
        async let message = GitStatusService.shared.mergeCommitMessage(in: repositoryURL)
        let (loadedMergeInProgress, loadedMessage) = await (mergeInProgress, message)
        isMergeInProgress = loadedMergeInProgress
        if mergeMessage.isEmpty {
            mergeMessage = loadedMessage.isEmpty && loadedMergeInProgress
                ? "Merge changes"
                : loadedMessage
        }
    }

    private func openInExternalTool() async {
        guard !allConflictFiles.isEmpty else { return }
        isPerformingMergeAction = true
        defer { isPerformingMergeAction = false }

        do {
            try await integrationSettings.openExternalMerge(
                for: selectedFile,
                in: repositoryURL
            )
            let updatedDocument = try await GitStatusService.shared.conflictDocument(
                for: selectedFile,
                in: repositoryURL
            )
            let stillHasConflicts = updatedDocument.sections.contains(where: \.isConflict)
            if stillHasConflicts {
                document = updatedDocument
                resultText = updatedDocument.resolvedText
                hasUnsavedChanges = false
                focusCurrentConflict(in: updatedDocument, preferredSectionIndex: nil, scroll: true)
            } else {
                try await GitStatusService.shared.resolveConflict(
                    file: selectedFile,
                    in: repositoryURL,
                    with: updatedDocument
                )
                markSelectedFileResolved()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func abortMerge() async {
        isPerformingMergeAction = true
        defer { isPerformingMergeAction = false }

        do {
            try await GitStatusService.shared.abortMerge(in: repositoryURL)
            onResolved()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func commitMerge() async {
        isPerformingMergeAction = true
        defer { isPerformingMergeAction = false }

        do {
            try await GitStatusService.shared.commit(message: mergeMessage, in: repositoryURL)
            onResolved()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func markSelectedFileResolved() {
        let resolvedFile = selectedFile
        let currentIndex = allConflictFiles.firstIndex(of: resolvedFile)
        allConflictFiles.removeAll { $0 == resolvedFile }
        if !resolvedFiles.contains(resolvedFile) {
            resolvedFiles.append(resolvedFile)
            resolvedFiles.sort { $0.path < $1.path }
        }
        hasUnsavedChanges = false
        onResolved()

        if allConflictFiles.isEmpty {
            document = nil
            resultText = ""
            selectedConflictSectionIndex = nil
        } else if let currentIndex {
            selectedFile = allConflictFiles[min(currentIndex, allConflictFiles.count - 1)]
        } else if let firstFile = allConflictFiles.first {
            selectedFile = firstFile
        }
    }

    private func saveAndAdvance() async {
        guard let document = document else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await GitStatusService.shared.resolveConflict(
                file: selectedFile,
                in: repositoryURL,
                with: document
            )
            await MainActor.run {
                markSelectedFileResolved()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
