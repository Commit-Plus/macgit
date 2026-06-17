//
//  ConflictMergeToolView.swift
//  macgit
//

import SwiftUI

struct ConflictMergeToolView: View {
    @Environment(\.dismiss) private var dismiss

    let allConflictFiles: [StatusFile]
    let repositoryURL: URL
    let onResolved: () -> Void

    @State private var selectedFile: StatusFile
    @State private var document: ConflictResolutionDocument?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedConflictIndex = 0
    @State private var hasUnsavedChanges = false
    @State private var showingCloseConfirmation = false
    @State private var sidebarCollapsed = false

    init(allConflictFiles: [StatusFile], repositoryURL: URL, onResolved: @escaping () -> Void) {
        self.allConflictFiles = allConflictFiles
        self.repositoryURL = repositoryURL
        self.onResolved = onResolved
        self._selectedFile = State(initialValue: allConflictFiles.first!)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            fileSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            mainContent
        }
        .frame(minWidth: 1200, idealWidth: 1400, maxWidth: .infinity)
        .frame(minHeight: 800, idealHeight: 900, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    // Close button (traffic light style)
                    Button(action: { requestClose() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Close")

                    // Sidebar toggle
                    Button(action: { sidebarCollapsed.toggle() }) {
                        Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")
                }
            }
        }
        .task {
            await loadDocument(for: selectedFile)
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .alert("Unsaved Changes", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have unsaved conflict resolutions. Are you sure you want to close and discard your changes?")
        }
        .onChange(of: selectedFile) { _, newFile in
            if hasUnsavedChanges {
                // In a real app, show confirmation here. For now, just proceed.
            }
            Task {
                await loadDocument(for: newFile)
            }
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarCollapsed ? .detailOnly : .all },
            set: { newValue in
                sidebarCollapsed = (newValue == .detailOnly)
            }
        )
    }

    private func requestClose() {
        if hasUnsavedChanges {
            showingCloseConfirmation = true
        } else {
            dismiss()
        }
    }

    // MARK: - Sidebar

    private var fileSidebar: some View {
        List(selection: $selectedFile) {
            Section("CONFLICT FILES") {
                ForEach(allConflictFiles) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.purple)
                            .font(.system(size: 14, weight: .medium))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.displayName)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Text(file.directory)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .tag(file)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if isLoading {
                ProgressView("Loading conflict details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = document {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                            if section.isConflict {
                                conflictBlockView(section: section, sectionIndex: index, document: document)
                            } else {
                                contextBlockView(text: section.contextText)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Resolve Conflicts")
                    .font(.headline.weight(.semibold))
                Text(selectedFile.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let document = document {
                let conflictCount = document.conflictCount
                let remaining = conflictCount - resolvedCount(in: document)
                Text("Conflict \(selectedConflictIndex + 1) of \(conflictCount) — \(remaining) remaining")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Previous") {
                        navigateToPreviousConflict(in: document)
                    }
                    .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 11))
                    .disabled(selectedConflictIndex == 0)

                    Button("Next") {
                        navigateToNextConflict(in: document)
                    }
                    .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 11))
                    .disabled(selectedConflictIndex >= conflictCount - 1)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isSaving ? "Resolving…" : "Complete / Merge") {
                    Task {
                        await saveAndAdvance()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Conflict Block

    private func conflictBlockView(section: ConflictResolutionSection, sectionIndex: Int, document: ConflictResolutionDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 16) {
                    Toggle("Current", isOn: Binding(
                        get: { section.resolution == .current || section.resolution == .both },
                        set: { isOn in
                            applyCheckbox(isCurrent: true, isOn: isOn, to: sectionIndex)
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Toggle("Incoming", isOn: Binding(
                        get: { section.resolution == .incoming || section.resolution == .both },
                        set: { isOn in
                            applyCheckbox(isCurrent: false, isOn: isOn, to: sectionIndex)
                        }
                    ))
                    .toggleStyle(.checkbox)
                }

                Spacer()

                Text("Conflict Block")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.purple.opacity(0.04))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator.opacity(0.5))
                    .frame(height: 0.5)
            }

            // Panes
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    codePane(title: "Current", text: section.currentText, isReadOnly: true)
                    Divider()
                    codePane(title: "Incoming", text: section.incomingText, isReadOnly: true)
                }
                .frame(minHeight: 120)

                Divider()

                resultPane(section: section, sectionIndex: sectionIndex)
                    .frame(minHeight: 120)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .id(section.id)
    }

    // MARK: - Context Block

    private func contextBlockView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CodeBlockView(text: text, fileExtension: selectedFile.fileExtension)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Code Pane

    private func codePane(title: String, text: String, isReadOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
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

            ScrollView(.horizontal) {
                CodeBlockView(text: text, fileExtension: selectedFile.fileExtension)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result Pane

    private func resultPane(section: ConflictResolutionSection, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Result")
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

            ScrollView(.horizontal) {
                CodeEditorView(
                    text: resultBinding(for: sectionIndex),
                    fileExtension: selectedFile.fileExtension
                )
                .frame(minHeight: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private func applyCheckbox(isCurrent: Bool, isOn: Bool, to sectionIndex: Int) {
        guard var document = document else { return }
        let section = document.sections[sectionIndex]
        let currentOn = isCurrent ? isOn : (section.resolution == .current || section.resolution == .both)
        let incomingOn = !isCurrent ? isOn : (section.resolution == .incoming || section.resolution == .both)

        if currentOn && incomingOn {
            document.sections[sectionIndex].resolution = .both
            document.sections[sectionIndex].manualResult = ""
        } else if currentOn {
            document.sections[sectionIndex].resolution = .current
            document.sections[sectionIndex].manualResult = ""
        } else if incomingOn {
            document.sections[sectionIndex].resolution = .incoming
            document.sections[sectionIndex].manualResult = ""
        } else {
            document.sections[sectionIndex].resolution = .manual
            document.sections[sectionIndex].manualResult = ""
        }

        self.document = document
        hasUnsavedChanges = true
    }

    private func resultBinding(for sectionIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard let document = document else { return "" }
                return document.sections[sectionIndex].editorText
            },
            set: { newValue in
                guard var document = document else { return }
                document.sections[sectionIndex].resolution = .manual
                document.sections[sectionIndex].manualResult = newValue
                self.document = document
                hasUnsavedChanges = true
            }
        )
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

    private func loadDocument(for file: StatusFile) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedDocument = try await GitStatusService.shared.conflictDocument(for: file, in: repositoryURL)
            await MainActor.run {
                document = loadedDocument
                selectedConflictIndex = 0
                hasUnsavedChanges = false
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
                // Move to next file if available
                if let currentIndex = allConflictFiles.firstIndex(of: selectedFile),
                   currentIndex + 1 < allConflictFiles.count {
                    selectedFile = allConflictFiles[currentIndex + 1]
                } else {
                    dismiss()
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
