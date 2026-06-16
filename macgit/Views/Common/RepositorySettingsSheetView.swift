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

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.top, 12)

            ScrollView {
                if let draft {
                    VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default remote")
                    .font(.system(size: 13))

                Picker("", selection: binding(\.selectedRemoteName)) {
                    ForEach(remoteOptions(for: draft), id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }
                .pickerStyle(.menu)
                .disabled(remoteOptions(for: draft).isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default pull branch")
                    .font(.system(size: 13))

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
            .padding(12)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Button("Open Remote URL") {
                    guard !draft.selectedRemoteName.isEmpty else { return }
                    onOpenRemoteURL(draft.selectedRemoteName)
                }
                .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
                .disabled(draft.selectedRemoteName.isEmpty)

                Spacer()
            }
        }
    }

    private var pullFetchTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .font(.system(size: 13, weight: .semibold))

                Picker("Pull strategy", selection: binding(\.pullStrategy)) {
                    Text("Merge").tag(PullStrategy.merge)
                    Text("Rebase").tag(PullStrategy.rebase)
                }
                .pickerStyle(.menu)

                Toggle("Auto fetch", isOn: binding(\.autoFetchEnabled))
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)

                Toggle("Refresh when app becomes active", isOn: binding(\.refreshOnAppActive))
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)
            }
            .padding(12)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var safetyFilesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Confirm detached HEAD checkout", isOn: binding(\.confirmDetachedHeadCheckout))
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)

                Toggle("Confirm destructive stash actions", isOn: binding(\.confirmDestructiveStashActions))
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)
            }
            .padding(12)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button("Open .gitignore", action: onOpenGitIgnore)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Button("Open .git/config", action: onOpenGitConfig)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Spacer()
            }
        }
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

        await MainActor.run {
            remotes = loadedRemotesValue
            branches = loadedBranchesValue
            draft = RepositorySettingsDraft(
                settings: initialSettings,
                remotes: loadedRemotesValue,
                branches: loadedBranchesValue,
                currentBranch: currentBranch
            )
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

