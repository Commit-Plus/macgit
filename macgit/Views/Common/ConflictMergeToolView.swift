//
//  ConflictMergeToolView.swift
//  macgit
//

import SwiftUI

struct ConflictMergeToolView: View {
    let allConflictFiles: [StatusFile]
    let repositoryURL: URL
    let onResolved: () -> Void
    let onClose: () -> Void

    @State private var selectedFile: StatusFile
    @State private var document: ConflictResolutionDocument?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedConflictIndex = 0
    @State private var hasUnsavedChanges = false
    @State private var scrollController = SyncedScrollController()

    init(allConflictFiles: [StatusFile], repositoryURL: URL, onResolved: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.allConflictFiles = allConflictFiles
        self.repositoryURL = repositoryURL
        self.onResolved = onResolved
        self.onClose = onClose
        self._selectedFile = State(initialValue: allConflictFiles.first!)
    }

    var body: some View {
        ZStack {
            rootView
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("")
        .toolbar { toolbarContent }
        .task {
            await loadDocument(for: selectedFile)
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onChange(of: selectedFile) { _, newFile in
            if hasUnsavedChanges {
                // In a real app, show confirmation here. For now, just proceed.
            }
            Task {
                await loadDocument(for: newFile)
            }
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
        List(selection: $selectedFile) {
            ForEach(allConflictFiles) { file in
                Label(file.displayName, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.purple)
                    .tag(file)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
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

            if isLoading {
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
        let resultData = PanelData(rows: panels.resultRows)

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
            panelView(
                title: "Result",
                scrollID: "result",
                selectionSide: nil,
                data: resultData,
                highlightColor: Color(nsColor: .systemPurple).opacity(0.7)
            )
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
            if let document = document {
                HStack(spacing: 0) {
                    Button {
                        navigateToPreviousConflict(in: document)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 22)
                    }
                    .disabled(selectedConflictIndex == 0)
                    .accessibilityLabel("Previous conflict")

                    Divider()
                        .frame(height: 12)

                    Button {
                        navigateToNextConflict(in: document)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 22)
                    }
                    .disabled(selectedConflictIndex >= document.conflictCount - 1)
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
            }
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolve Conflicts")
                        .font(.headline.weight(.semibold))
                    Text(selectedFile.path)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let document = document {
                    let conflictCount = document.conflictCount
                    let remaining = conflictCount - resolvedCount(in: document)
                    Text("Conflict \(selectedConflictIndex + 1) of \(conflictCount) — \(remaining) remaining")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    await saveAndAdvance()
                }
            } label: {
                Text(isSaving ? "Resolving…" : "Merge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
    }

    // MARK: - Helpers

    private func headerSelectionControl(for side: ConflictPaneSelectionSide) -> some View {
        let selected = allConflictsSelected(side)

        return Button(
            "Select all \(side.title) conflict blocks",
            systemImage: selected ? "checkmark.square.fill" : "square"
        ) {
            selectAllConflicts(side)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .secondary)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func resolvedCount(in document: ConflictResolutionDocument) -> Int {
        document.sections.filter { $0.isConflict && $0.resolution != .manual }.count
    }

    private func navigateToPreviousConflict(in document: ConflictResolutionDocument) {
        let conflictIndices = document.sections.indices.filter { document.sections[$0].isConflict }
        guard let currentIndex = conflictIndices.firstIndex(of: selectedConflictIndex) else { return }
        let prevIndex = max(0, currentIndex - 1)
        selectedConflictIndex = conflictIndices[prevIndex]
    }

    private func navigateToNextConflict(in document: ConflictResolutionDocument) {
        let conflictIndices = document.sections.indices.filter { document.sections[$0].isConflict }
        guard let currentIndex = conflictIndices.firstIndex(of: selectedConflictIndex) else { return }
        let nextIndex = min(conflictIndices.count - 1, currentIndex + 1)
        selectedConflictIndex = conflictIndices[nextIndex]
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

        selectedConflictIndex = sectionIndex
        hasUnsavedChanges = true
        self.document = document
    }

    private func allConflictsSelected(_ side: ConflictPaneSelectionSide) -> Bool {
        document?.allConflictsUse(side.resolution) ?? false
    }

    private func selectAllConflicts(_ side: ConflictPaneSelectionSide) {
        guard var document else { return }

        document.selectAllConflicts(side.resolution)
        selectedConflictIndex = document.sections.firstIndex { $0.isConflict } ?? selectedConflictIndex
        hasUnsavedChanges = true
        self.document = document
    }

    private func loadDocument(for file: StatusFile) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedDocument = try await GitStatusService.shared.conflictDocument(for: file, in: repositoryURL)
            await MainActor.run {
                document = loadedDocument
                selectedConflictIndex = 0
                hasUnsavedChanges = false
                scrollController.scrollToTop()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func saveAndAdvance() async {
        guard let document = document else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await GitStatusService.shared.resolveConflict(file: selectedFile, in: repositoryURL, with: document)
            await MainActor.run {
                hasUnsavedChanges = false
                if let currentIndex = allConflictFiles.firstIndex(of: selectedFile),
                   currentIndex + 1 < allConflictFiles.count {
                    selectedFile = allConflictFiles[currentIndex + 1]
                } else {
                    onClose()
                    onResolved()
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
