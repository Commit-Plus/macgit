//
//  PushSheetView.swift
//  macgit
//

import SwiftUI

struct BranchPushInfo: Identifiable {
    let id = UUID()
    let local: String
    var remote: String
    var isSelected: Bool
    var isTracked: Bool
}

struct PushSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let onPush: (GitStatusService.PushOptions) -> Void

    @State private var remotes: [String] = []
    @State private var selectedRemote: String = ""
    @State private var remoteURL: String = ""

    @State private var branches: [BranchPushInfo] = []
    @State private var selectAll: Bool = false
    @State private var pushTags: Bool = false

    @State private var isLoading = false

    private var selectedBranches: [BranchPushInfo] {
        branches.filter { $0.isSelected }
    }

    private var canPush: Bool {
        !selectedBranches.isEmpty && !selectedRemote.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Remote repository
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push to repository:")
                            .font(.system(size: 13))
                        HStack(spacing: 8) {
                            Picker("", selection: $selectedRemote) {
                                ForEach(remotes, id: \.self) { remote in
                                    Text(remote).tag(remote)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedRemote) { _, newValue in
                                Task { await loadRemoteURL(remote: newValue) }
                            }

                            if !remoteURL.isEmpty {
                                Text(remoteURL)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Branches to push
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Branches to push")
                            .font(.system(size: 13, weight: .semibold))

                        // Header row
                        HStack(spacing: 0) {
                            Text("Push")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 40, alignment: .leading)
                            Text("Local branch")
                                .font(.system(size: 11, weight: .medium))
                                .frame(minWidth: 120, alignment: .leading)
                            Spacer()
                            Text("Remote branch")
                                .font(.system(size: 11, weight: .medium))
                                .frame(minWidth: 100, alignment: .leading)
                            Text("Track?")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 50, alignment: .center)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.3))

                        // Branch rows
                        ForEach($branches) { $branch in
                            HStack(spacing: 0) {
                                Toggle("", isOn: Binding(
                                    get: { branch.isSelected },
                                    set: { newValue in
                                        branch.isSelected = newValue
                                        if newValue && branch.remote.isEmpty {
                                            branch.remote = branch.local
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .frame(width: 40, alignment: .leading)

                                Text(branch.local)
                                    .font(.system(size: 12))
                                    .frame(minWidth: 120, alignment: .leading)

                                Spacer()

                                if !branch.remote.isEmpty {
                                    Text(branch.remote)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 100, alignment: .leading)
                                } else {
                                    Text("—")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .frame(minWidth: 100, alignment: .leading)
                                }

                                if branch.isTracked {
                                    Button(action: {}) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 50)
                                    .disabled(true)
                                } else {
                                    Button(action: {
                                        Task { await setUpstream(for: branch.local) }
                                    }) {
                                        Image(systemName: "arrow.up.arrow.down.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 50)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(branch.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                        }

                        // Select All
                        HStack {
                            Toggle("Select All", isOn: Binding(
                                get: { selectAll },
                                set: { newValue in
                                    selectAll = newValue
                                    for index in branches.indices {
                                        branches[index].isSelected = newValue
                                        if newValue && branches[index].remote.isEmpty {
                                            branches[index].remote = branches[index].local
                                        }
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // Push all tags
                    Toggle("Push all tags", isOn: $pushTags)
                        .font(.system(size: 12))
                        .toggleStyle(.checkbox)
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

                Button("OK") {
                    dismiss()
                    let mappings = selectedBranches.reduce(into: [:]) { result, branch in
                        result[branch.local] = branch.remote
                    }
                    let options = GitStatusService.PushOptions(
                        remote: selectedRemote,
                        branches: selectedBranches.map(\.local),
                        branchMappings: mappings,
                        pushTags: pushTags
                    )
                    onPush(options)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canPush)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 600)
        .frame(minHeight: 380, idealHeight: 420)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let currentRemotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let currentBranches = await GitStatusService.shared.localBranches(in: repositoryURL)
        let currentRemote = currentRemotes.first ?? ""
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""

        await MainActor.run {
            remotes = currentRemotes
            selectedRemote = currentRemote
        }

        if !currentRemote.isEmpty {
            await loadRemoteURL(remote: currentRemote)
        }

        var branchInfos: [BranchPushInfo] = []
        for branch in currentBranches {
            let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL)
            let isTracked = upstream != nil
            let remoteName = upstream?.components(separatedBy: "/").dropFirst().joined(separator: "/") ?? branch
            // Auto-select only if this is the current branch AND it is already tracked on remote
            let shouldSelect = (branch == currentBranch) && isTracked
            branchInfos.append(BranchPushInfo(
                local: branch,
                remote: isTracked ? remoteName : "",
                isSelected: shouldSelect,
                isTracked: isTracked
            ))
        }

        await MainActor.run {
            branches = branchInfos
        }
    }

    private func loadRemoteURL(remote: String) async {
        let url = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        await MainActor.run {
            remoteURL = url
        }
    }

    private func setUpstream(for branch: String) async {
        do {
            try await GitStatusService.shared.setUpstream(remote: selectedRemote, branch: branch, in: repositoryURL)
            await loadData()
        } catch {
            // Silently ignore upstream set failures
        }
    }
}

#Preview {
    PushSheetView(repositoryURL: URL(fileURLWithPath: "/tmp")) { _ in }
}
