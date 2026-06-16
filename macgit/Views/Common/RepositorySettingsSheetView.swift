//
//  RepositorySettingsSheetView.swift
//  macgit
//

import SwiftUI

private enum RepositorySettingsTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case pullFetch = "Pull & Fetch"
    case safetyFiles = "Safety & Files"

    var id: String { rawValue }
}

struct RemoteInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: String
}

struct RepositorySettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let initialSettings: RepoSettings
    let onSave: (RepoSettings) -> Void
    let onOpenGitIgnore: () -> Void
    let onOpenGitConfig: () -> Void
    let onOpenRemoteURL: (String) -> Void

    @State private var selectedTab: RepositorySettingsTab = .remote
    @State private var draft: RepositorySettingsDraft?
    @State private var remotes: [String] = []
    @State private var branches: [String] = []
    @State private var remoteURLs: [String: String] = [:]
    @State private var selectedRemoteName: String = ""
    @State private var showingRemoteEditSheet = false
    @State private var remoteEditMode: RemoteEditMode = .add
    private let settingsContentWidth: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.top, 12)

            ScrollView {
                if let draft {
                    VStack(alignment: .center, spacing: 16) {
                        switch selectedTab {
                        case .remote:
                            remoteTab(draft)
                        case .pullFetch:
                            pullFetchTab
                        case .safetyFiles:
                            safetyFilesTab
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: settingsContentWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(24)
                }
            }

            footer
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 600)
        .frame(minHeight: 420, idealHeight: 480)
        .task {
            await loadOptions()
        }
        .sheet(isPresented: $showingRemoteEditSheet) {
            RemoteEditSheetView(
                repositoryURL: repositoryURL,
                mode: remoteEditMode
            ) { name, url in
                Task {
                    await handleRemoteSave(name: name, url: url)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Repository Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(RepositorySettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding([.top, .horizontal], 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                guard let draft else { return }
                onSave(draft.resolvedSettings)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
        }
        .padding([.horizontal, .bottom], 24)
    }

    @ViewBuilder
    private func remoteTab(_ draft: RepositorySettingsDraft) -> some View {
        VStack(alignment: .center, spacing: 16) {
            // Remote table
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote repository paths:")
                    .font(.system(size: 13))

                remoteTable
            }

            // Default remote picker
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Default remote")
                    .font(.system(size: 13))
                    .frame(width: 130, alignment: .trailing)

                Picker("", selection: binding(\.selectedRemoteName)) {
                    ForEach(remoteOptions(for: draft), id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }
                .pickerStyle(.menu)
                .disabled(remoteOptions(for: draft).isEmpty)

                Spacer()
            }

            // Default pull branch
            HStack(alignment: .top, spacing: 12) {
                Text("Default pull branch")
                    .font(.system(size: 13))
                    .frame(width: 130, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: binding(\.selectedBranchMode)) {
                        Text("Detected Branch").tag(SelectedBranchMode.detected)
                        Text("Manual Entry").tag(SelectedBranchMode.manual)
                    }
                    .pickerStyle(.segmented)

                    if draft.selectedBranchMode == .detected {
                        Picker("", selection: binding(\.selectedDetectedBranch)) {
                            Text("Select a branch").tag("")
                            ForEach(branchOptions(for: draft), id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("release/hotfix", text: binding(\.manualBranchName))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()

                Button("Open Remote URL") {
                    guard !draft.selectedRemoteName.isEmpty else { return }
                    onOpenRemoteURL(draft.selectedRemoteName)
                }
                .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
                .disabled(draft.selectedRemoteName.isEmpty)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remoteTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Name")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 100, alignment: .leading)
                        .padding(.horizontal, 8)

                    Divider()

                    Text("Path")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)

                    Spacer()
                }
                .frame(height: 28)
                .background(.quaternary.opacity(0.2))

                Divider()

                // Rows
                ForEach(remotes.map { RemoteInfo(name: $0, url: remoteURLs[$0] ?? "") }) { remote in
                    HStack(spacing: 0) {
                        Text(remote.name)
                            .font(.system(size: 12))
                            .frame(width: 100, alignment: .leading)
                            .padding(.horizontal, 8)

                        Divider()

                        Text(remote.url)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .frame(height: 28)
                    .background(selectedRemoteName == remote.name ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRemoteName = remote.name
                    }

                    Divider()
                }
            }
            .background(.quaternary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.quaternary.opacity(0.4), lineWidth: 1)
            )

            // Add / Edit / Remove buttons
            HStack(spacing: 8) {
            Button("Add") {
                remoteEditMode = .add
                showingRemoteEditSheet = true
            }
            .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

            Button("Edit") {
                guard let url = remoteURLs[selectedRemoteName], !selectedRemoteName.isEmpty else { return }
                remoteEditMode = .edit(name: selectedRemoteName, url: url)
                showingRemoteEditSheet = true
            }
            .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
            .disabled(selectedRemoteName.isEmpty)

            Button("Remove") {
                Task {
                    await removeRemote(name: selectedRemoteName)
                }
            }
            .buttonStyle(GlassButtonStyle(tint: .red, fontSize: 11))
            .disabled(selectedRemoteName.isEmpty)

            Spacer()
        }
    }
    }

    private var pullFetchTab: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Pull strategy")
                        .font(.system(size: 13))
                        .frame(width: 130, alignment: .trailing)

                    Picker("", selection: binding(\.pullStrategy)) {
                        Text("Merge").tag(PullStrategy.merge)
                        Text("Rebase").tag(PullStrategy.rebase)
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                Toggle("Auto fetch", isOn: binding(\.autoFetchEnabled))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                Toggle("Refresh when app becomes active", isOn: binding(\.refreshOnAppActive))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var safetyFilesTab: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Confirm detached HEAD checkout", isOn: binding(\.confirmDetachedHeadCheckout))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                Toggle("Confirm destructive stash actions", isOn: binding(\.confirmDestructiveStashActions))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Spacer()

                Button("Open .gitignore", action: onOpenGitIgnore)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Button("Open .git/config", action: onOpenGitConfig)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadOptions() async {
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        async let loadedBranches = GitStatusService.shared.localBranches(in: repositoryURL)
        async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)

        let (loadedRemotesValue, loadedBranchesValue, currentBranch) = await (
            loadedRemotes,
            loadedBranches,
            loadedCurrentBranch
        )

        // Load remote URLs
        var urls: [String: String] = [:]
        for remote in loadedRemotesValue {
            if let url = try? await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL) {
                urls[remote] = url
            }
        }

        await MainActor.run {
            remotes = loadedRemotesValue
            branches = loadedBranchesValue
            remoteURLs = urls
            selectedRemoteName = loadedRemotesValue.first ?? ""
            draft = RepositorySettingsDraft(
                settings: initialSettings,
                remotes: loadedRemotesValue,
                branches: loadedBranchesValue,
                currentBranch: currentBranch
            )
        }
    }

    private func handleRemoteSave(name: String, url: String) async {
        switch remoteEditMode {
        case .add:
            do {
                try await GitStatusService.shared.addRemote(name: name, url: url, in: repositoryURL)
                await loadOptions()
                await MainActor.run {
                    selectedRemoteName = name
                }
            } catch {
                // Silently handle for now — could show an alert in future
            }
        case .edit(let oldName, _):
            do {
                try await GitStatusService.shared.setRemoteURL(name: oldName, url: url, in: repositoryURL)
                await loadOptions()
            } catch {
                // Silently handle for now
            }
        }
    }

    private func removeRemote(name: String) async {
        guard !name.isEmpty else { return }
        do {
            try await GitStatusService.shared.removeRemote(name: name, in: repositoryURL)
            await loadOptions()
        } catch {
            // Silently handle for now
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RepositorySettingsDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { newValue in
                draft![keyPath: keyPath] = newValue
            }
        )
    }

    private func remoteOptions(for draft: RepositorySettingsDraft) -> [String] {
        let candidates = remotes.isEmpty ? draft.remotes : remotes
        if draft.selectedRemoteName.isEmpty || candidates.contains(draft.selectedRemoteName) {
            return candidates
        }
        return [draft.selectedRemoteName] + candidates
    }

    private func branchOptions(for draft: RepositorySettingsDraft) -> [String] {
        let candidates = branches.isEmpty ? draft.branches : branches
        if draft.selectedDetectedBranch.isEmpty || candidates.contains(draft.selectedDetectedBranch) {
            return candidates
        }
        return [draft.selectedDetectedBranch] + candidates
    }
}
