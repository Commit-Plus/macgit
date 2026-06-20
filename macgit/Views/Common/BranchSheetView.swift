//
//  BranchSheetView.swift
//  macgit
//

import SwiftUI

enum BranchTab: String, CaseIterable {
    case create = "New Branch"
    case delete = "Delete Branches"
}

struct BranchCommitInfo: Identifiable, Hashable {
    let id = UUID()
    let hash: String
    let message: String

    var display: String {
        "\(hash) \(message)"
    }
}

struct BranchDeleteItem: Identifiable {
    let id = UUID()
    let name: String
    let type: BranchType
    var isSelected: Bool = false
}

enum BranchType: String {
    case local = "Local"
    case remote = "Remote"
}

struct BranchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let onCompleted: () -> Void
    var undoManager: GitUndoManager? = nil

    @State private var selectedTab: BranchTab = .create

    // Create tab state
    @State private var currentBranch: String = ""
    @State private var branchNameInput: String = ""
    @State private var sanitizedName: String = ""
    @State private var useWorkingCopyParent = true
    @State private var selectedCommitHash: String = ""
    @State private var recentCommits: [BranchCommitInfo] = []
    @State private var checkoutNewBranch = true

    // Delete tab state
    @State private var branches: [BranchDeleteItem] = []
    @State private var forceDelete = false

    // Confirmation overlay
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    // Alerts
    @State private var errorMessage: String = ""
    @State private var showingError = false

    private var canCreate: Bool {
        !sanitizedName.isEmpty
    }

    private var selectedBranches: [BranchDeleteItem] {
        branches.filter { $0.isSelected }
    }

    private var canDelete: Bool {
        !selectedBranches.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(selectedTab == .create ? "New Branch" : "Delete Branches")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Picker("", selection: $selectedTab) {
                        ForEach(BranchTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding([.top, .horizontal], 24)

                Divider()
                    .padding(.top, 12)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if selectedTab == .create {
                            createBranchContent
                        } else {
                            deleteBranchesContent
                        }
                    }
                    .padding(24)
                }

                // Buttons
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    if selectedTab == .create {
                        Button("Create Branch") {
                            Task { await createBranch() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                        .disabled(!canCreate)
                    } else {
                        Button("Delete Branches") {
                            showingDeleteConfirmation = true
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .red, fontSize: 13))
                        .disabled(!canDelete)
                    }
                }
                .padding([.horizontal, .bottom], 24)
            }
            .frame(minWidth: 480, idealWidth: 520, maxWidth: 560)
            .frame(minHeight: 400, idealHeight: 460, maxHeight: 600)

            // Custom confirmation overlay
            if showingDeleteConfirmation {
                deleteConfirmationOverlay
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadCreateData()
            await loadDeleteData()
        }
        .onChange(of: selectedTab) { _, _ in
            if selectedTab == .create {
                Task { await loadCreateData() }
            } else {
                Task { await loadDeleteData() }
            }
        }
    }

    // MARK: - Delete Confirmation Overlay

    private var deleteConfirmationOverlay: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Text("Confirm Delete")
                        .font(.headline)

                    Text("Are you sure you want to delete the selected branches?")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(selectedBranches) { branch in
                            Text("• \(branch.name)")
                                .font(.system(size: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Button("Cancel", role: .cancel) {
                            if !isDeleting {
                                showingDeleteConfirmation = false
                            }
                        }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isDeleting)

                        Button(isDeleting ? "Deleting..." : "Delete") {
                            Task { await deleteSelectedBranches() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .red, fontSize: 13))
                        .disabled(isDeleting)
                    }
                }
                .padding(24)
                .frame(minWidth: 320, idealWidth: 360)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
    }

    // MARK: - Create Branch Content

    private var createBranchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current branch
            VStack(alignment: .leading, spacing: 4) {
                Text("Current branch")
                    .font(.system(size: 13))
                Text(currentBranch)
                    .font(.system(size: 13, weight: .medium))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // New branch name
            VStack(alignment: .leading, spacing: 4) {
                Text("New Branch:")
                    .font(.system(size: 13))
                TextField("Enter branch name...", text: $branchNameInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branchNameInput) { _, newValue in
                        sanitizedName = sanitizeBranchName(newValue)
                    }
                if !sanitizedName.isEmpty {
                    Text(sanitizedName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Commit source
            VStack(alignment: .leading, spacing: 8) {
                Text("Commit:")
                    .font(.system(size: 13))

                Picker("", selection: $useWorkingCopyParent) {
                    Text("Working copy parent").tag(true)
                    Text("Specified commit:").tag(false)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))

                if !useWorkingCopyParent {
                    Picker("", selection: $selectedCommitHash) {
                        Text("Select a commit...").tag("")
                        ForEach(recentCommits) { commit in
                            Text(commit.display)
                                .tag(commit.hash)
                                .lineLimit(1)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 280, alignment: .leading)
                    .padding(.leading, 16)
                }
            }

            // Checkout
            Toggle("Checkout new branch", isOn: $checkoutNewBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
        }
    }

    // MARK: - Delete Branches Content

    private var deleteBranchesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select the branches you wish to delete:")
                .font(.system(size: 13))

            // Table header
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 30)
                Text("Branch name")
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 120, alignment: .leading)
                Spacer()
                Text("Type")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 60, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.3))

            // Table rows
            VStack(spacing: 0) {
                ForEach($branches) { $branch in
                    HStack(spacing: 0) {
                        Toggle("", isOn: $branch.isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(width: 30)

                        Text(branch.name)
                            .font(.system(size: 12))
                            .frame(minWidth: 120, alignment: .leading)

                        Spacer()

                        Text(branch.type.rawValue)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .background(.quaternary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Toggle("Force delete regardless of merge status", isOn: $forceDelete)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
        }
    }

    // MARK: - Actions

    private func createBranch() async {
        do {
            let commit = useWorkingCopyParent ? nil : selectedCommitHash
            let support = GitBranchUndoSupport()
            let startPoint = try await support.tip(of: commit ?? "HEAD", in: repositoryURL)
            _ = try await GitStatusService.shared.createBranch(
                name: sanitizedName,
                checkout: checkoutNewBranch,
                commit: commit,
                in: repositoryURL
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Create branch \(sanitizedName)",
                        undoOperation: .deleteLocalBranch(name: sanitizedName, force: true, expectedTip: startPoint),
                        redoOperation: .createLocalBranch(name: sanitizedName, startPoint: startPoint, checkout: checkoutNewBranch)
                    )
                )
                onCompleted()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteSelectedBranches() async {
        await MainActor.run {
            isDeleting = true
        }

        // Pre-check: cannot delete the currently checked-out branch
        let checkedOut = selectedBranches.first { $0.type == .local && $0.name == currentBranch }
        if let checkedOut = checkedOut {
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                errorMessage = "Cannot delete the currently checked out branch '\(checkedOut.name)'. Please switch to another branch first."
                showingError = true
            }
            return
        }

        do {
            for branch in selectedBranches {
                switch branch.type {
                case .local:
                    let support = GitBranchUndoSupport()
                    let tip = try await support.tip(of: branch.name, in: repositoryURL)
                    let upstream = await support.upstream(of: branch.name, in: repositoryURL)
                    _ = try await GitStatusService.shared.deleteBranch(
                        name: branch.name,
                        force: forceDelete,
                        in: repositoryURL
                    )
                    await MainActor.run {
                        var undoOperations: [GitUndoOperation] = [
                            .createLocalBranch(name: branch.name, startPoint: tip, checkout: false)
                        ]
                        if let upstream {
                            undoOperations.append(.setUpstream(branch: branch.name, upstream: upstream))
                        }
                        undoManager?.register(
                            GitUndoEntry(
                                repositoryURL: repositoryURL,
                                label: "Delete branch \(branch.name)",
                                undoOperation: .sequence(undoOperations),
                                redoOperation: .deleteLocalBranch(name: branch.name, force: forceDelete, expectedTip: tip)
                            )
                        )
                    }
                case .remote:
                    let parts = branch.name.split(separator: "/", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let remote = String(parts[0])
                    let name = String(parts[1])
                    _ = try await GitStatusService.shared.deleteRemoteBranch(
                        remote: remote,
                        name: name,
                        in: repositoryURL
                    )
                }
            }
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                // Refresh branch list and keep modal open
                Task { await loadDeleteData() }
            }
        } catch {
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                errorMessage = friendlyErrorMessage(for: error)
                showingError = true
            }
        }
    }

    // MARK: - Data Loading

    private func loadCreateData() async {
        let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let commits = await GitStatusService.shared.recentCommits(limit: 50, in: repositoryURL)

        await MainActor.run {
            currentBranch = branch
            recentCommits = commits.map { BranchCommitInfo(hash: $0.hash, message: $0.message) }
            if !recentCommits.isEmpty && selectedCommitHash.isEmpty {
                selectedCommitHash = recentCommits[0].hash
            }
        }
    }

    private func loadDeleteData() async {
        let locals = await GitStatusService.shared.localBranches(in: repositoryURL)
        let remotesList = await GitStatusService.shared.remotes(in: repositoryURL)

        var items: [BranchDeleteItem] = []

        for name in locals {
            items.append(BranchDeleteItem(name: name, type: .local))
        }

        for remote in remotesList {
            let remoteBranches = await GitStatusService.shared.remoteBranches(remote: remote, in: repositoryURL)
            for branchName in remoteBranches {
                // Skip HEAD symbolic refs
                if branchName == "HEAD" { continue }
                items.append(BranchDeleteItem(name: "\(remote)/\(branchName)", type: .remote))
            }
        }

        await MainActor.run {
            branches = items
        }
    }

    // MARK: - Helpers

    private func sanitizeBranchName(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        let result = input.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_/")
        var sanitized = ""
        for scalar in result.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.append(Character(scalar))
            } else {
                sanitized.append("-")
            }
        }
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
        return sanitized
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("cannot delete branch") && raw.contains("used by worktree") {
            // Try to extract branch name
            if let range = error.localizedDescription.range(of: "'", options: .backwards),
               let startRange = error.localizedDescription.range(of: "'") {
                let branchName = String(error.localizedDescription[startRange.upperBound..<range.lowerBound])
                return "Cannot delete branch '\(branchName)' because it is currently checked out. Please switch to another branch first."
            }
            return "Cannot delete the currently checked out branch. Please switch to another branch first."
        }
        if raw.contains("not fully merged") {
            return "This branch is not fully merged. Enable 'Force delete regardless of merge status' to delete it anyway."
        }
        if raw.contains("remote ref does not exist") {
            return "The remote branch does not exist or has already been deleted."
        }
        return error.localizedDescription
    }
}

#Preview {
    BranchSheetView(repositoryURL: URL(fileURLWithPath: "/tmp")) {}
}
