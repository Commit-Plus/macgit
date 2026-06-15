//
//  RepoPickerView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

func determineRepoIconName(from remoteURLString: String) -> String {
    let lower = remoteURLString.lowercased()
    if lower.contains("github.com") || lower.contains("github") {
        return "github"
    } else if lower.contains("gitlab.com") || lower.contains("gitlab") {
        return "gitlab"
    } else if lower.contains("bitbucket.org") || lower.contains("bitbucket") {
        return "bitbucket"
    } else {
        return "code-branch"
    }
}

struct RepoPickerRowState {
    var currentBranch: String?
    var isMissing: Bool
    var isLoading: Bool
}

enum RepoPickerSortOption: String, CaseIterable, Identifiable {
    case lastOpened = "Last Opened"
    case name = "Name"

    var id: String { rawValue }
}

enum RepoPickerFilterType: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case bitbucket = "Bitbucket"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .github: return "github"
        case .gitlab: return "gitlab"
        case .bitbucket: return "bitbucket"
        }
    }
}

struct RepoPickerView: View {
    @ObservedObject private var store = RecentRepositoriesStore.shared
    @State private var showingCloneSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText = ""
    @State private var sortOption: RepoPickerSortOption = .lastOpened
    @State private var selectedFilterTypes: Set<RepoPickerFilterType> = []
    @State private var repoIcons: [URL: String] = [:]
    @State private var rowStates: [URL: RepoPickerRowState] = [:]

    var showCloneSheetInitially: Bool
    var onRepositoryOpened: (URL) -> Void

    init(showCloneSheetInitially: Bool = false, onRepositoryOpened: @escaping (URL) -> Void) {
        self.showCloneSheetInitially = showCloneSheetInitially
        self.onRepositoryOpened = onRepositoryOpened
    }

    private var visibleRepositories: [RecentRepository] {
        Self.visibleRepositories(
            from: store.repositories,
            searchText: searchText,
            sortOption: sortOption,
            selectedFilterTypes: selectedFilterTypes,
            repoIcons: repoIcons,
            rowStates: rowStates
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            headerSection
            controlBar
            recentRepositoriesSection
            Spacer(minLength: 0)
        }
        .frame(minWidth: 500, maxWidth: 700, minHeight: 520, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .task(id: showCloneSheetInitially) {
            if showCloneSheetInitially {
                showingCloneSheet = true
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .sheet(isPresented: $showingCloneSheet) {
            CloneSheetView(onClone: { url in
                store.add(url)
                onRepositoryOpened(url)
            })
        }
    }

    static func visibleRepositories(
        from repositories: [RecentRepository],
        searchText: String,
        sortOption: RepoPickerSortOption,
        selectedFilterTypes: Set<RepoPickerFilterType>,
        repoIcons: [URL: String],
        rowStates: [URL: RepoPickerRowState]
    ) -> [RecentRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = repositories.filter { repo in
            if !query.isEmpty {
                let haystack = [
                    repo.name,
                    repo.url.path,
                    rowStates[repo.url]?.currentBranch ?? ""
                ]
                    .joined(separator: " ")
                    .lowercased()

                guard haystack.contains(query) else { return false }
            }

            if !selectedFilterTypes.isEmpty {
                let iconName = repoIcons[repo.url] ?? "code-branch"
                let type = RepoPickerFilterType.allCases.first { $0.iconName == iconName }
                guard let type = type, selectedFilterTypes.contains(type) else { return false }
            }

            return true
        }

        switch sortOption {
        case .lastOpened:
            return filtered.sorted { $0.lastOpened > $1.lastOpened }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Commit+")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Open an existing repository or clone a new one")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button(action: openExistingRepository) {
                    Label("Open Repository", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 200)

                Button(action: { showingCloneSheet = true }) {
                    Label("Clone Repository", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(width: 200)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            TextField("Filter repositories", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .disabled(store.repositories.isEmpty)

            Menu {
                Section("Sort") {
                    Picker("", selection: $sortOption) {
                        ForEach(RepoPickerSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Filter by Type") {
                    ForEach(RepoPickerFilterType.allCases) { type in
                        Toggle(isOn: Binding(
                            get: { selectedFilterTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    selectedFilterTypes.insert(type)
                                } else {
                                    selectedFilterTypes.remove(type)
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(nsImage: menuIconImage(for: type.iconName))
                                Text(type.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(store.repositories.isEmpty)
        }
    }

    private var recentRepositoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Repositories")
                .font(.headline)

            if store.repositories.isEmpty {
                ContentUnavailableView(
                    "No Recent Repositories",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Open or clone a repository to start building your recent list.")
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
            } else if visibleRepositories.isEmpty {
                ContentUnavailableView(
                    "No Repositories Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or clear the filter.")
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleRepositories.enumerated()), id: \.element.id) { index, repo in
                            repoRow(repo)

                            if index < visibleRepositories.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func repoRow(_ repo: RecentRepository) -> some View {
        Button(action: {
            store.add(repo.url)
            onRepositoryOpened(repo.url)
        }) {
            repoRowContent(repo)
        }
        .buttonStyle(.plain)
        .task(id: repo.url) {
            await loadRowPresentation(for: repo)
        }
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                store.remove(repo)
            }
        }
    }

    private func repoRowContent(_ repo: RecentRepository) -> some View {
        HStack(spacing: 12) {
            Image(repoIcons[repo.url] ?? "code-branch")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .frame(width: 34, height: 34)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.body.weight(.medium))
                Text(repo.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                rowStatusView(for: repo)
                Text(timeAgoString(from: repo.lastOpened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowStatusView(for repo: RecentRepository) -> some View {
        let rowState = rowStates[repo.url]

        if rowState?.isLoading == true {
            ProgressView()
                .controlSize(.small)
        } else if rowState?.isMissing == true {
            Text("Repository moved or deleted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange, in: Capsule())
        } else if let branch = rowState?.currentBranch, !branch.isEmpty {
            Text(branch)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }

    private func loadRowPresentation(for repo: RecentRepository) async {
        await MainActor.run {
            rowStates[repo.url] = RepoPickerRowState(
                currentBranch: rowStates[repo.url]?.currentBranch,
                isMissing: false,
                isLoading: true
            )
        }

        let repoPath = repo.url.path
        let gitMetadataPath = repo.url.appendingPathComponent(".git").path
        let exists = FileManager.default.fileExists(atPath: repoPath)
        let hasGitMetadata = FileManager.default.fileExists(atPath: gitMetadataPath)

        guard exists && hasGitMetadata else {
            await MainActor.run {
                repoIcons[repo.url] = "code-branch"
                rowStates[repo.url] = RepoPickerRowState(currentBranch: nil, isMissing: true, isLoading: false)
            }
            return
        }

        async let branch = GitStatusService.shared.currentBranch(in: repo.url)
        async let remoteURLString = GitStatusService.shared.remoteURL(remote: "origin", in: repo.url)
        let (currentBranch, remoteURL) = await (branch, remoteURLString)

        await MainActor.run {
            repoIcons[repo.url] = remoteURL.isEmpty ? "code-branch" : determineRepoIconName(from: remoteURL)
            rowStates[repo.url] = RepoPickerRowState(
                currentBranch: currentBranch,
                isMissing: false,
                isLoading: false
            )
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * minute
        let day: TimeInterval = 24 * hour

        if interval < minute {
            return "just now"
        } else if interval < hour {
            let minutes = Int(interval / minute)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < day {
            let hours = Int(interval / hour)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private func menuIconImage(for iconName: String) -> NSImage {
        guard let original = NSImage(named: NSImage.Name(iconName)) else {
            return NSImage()
        }
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            original.draw(in: rect, from: NSRect(origin: .zero, size: original.size), operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private func openExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository folder"
        panel.prompt = "Open"

        panel.beginSheetModal(for: NSApp.keyWindow!) { result in
            if result == .OK, let url = panel.url {
                let gitPath = url.appendingPathComponent(".git").path
                if FileManager.default.fileExists(atPath: gitPath) {
                    store.add(url)
                    onRepositoryOpened(url)
                } else {
                    errorMessage = "The selected folder does not contain a .git directory."
                    showingError = true
                }
            }
        }
    }
}

struct CloneSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var remoteURL = ""
    @State private var destinationPath = ""
    @State private var showingDestinationPicker = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var repoIconName: String = "code-branch"

    var onClone: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Clone Repository")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Remote URL")
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(repoIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                    TextField("https://github.com/user/repo.git", text: $remoteURL)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 400)
                .onChange(of: remoteURL) { _, newValue in
                    repoIconName = determineRepoIconName(from: newValue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.headline)
                HStack {
                    Text(destinationPath.isEmpty ? "Choose a folder…" : destinationPath)
                        .foregroundStyle(destinationPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") {
                        showingDestinationPicker = true
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .frame(width: 400)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Clone") {
                    performClone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(remoteURL.isEmpty || destinationPath.isEmpty)
            }
        }
        .padding(30)
        .frame(minWidth: 480)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onChange(of: showingDestinationPicker) { _, newValue in
            if newValue {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Select a destination folder"
                panel.prompt = "Select"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    panel.beginSheetModal(for: NSApp.keyWindow!) { result in
                        showingDestinationPicker = false
                        if result == .OK, let url = panel.url {
                            destinationPath = url.path
                        }
                    }
                }
            }
        }
    }

    private func performClone() {
        guard let url = URL(string: remoteURL), url.scheme != nil else {
            errorMessage = "Please enter a valid remote URL."
            showingError = true
            return
        }

        let destURL = URL(fileURLWithPath: destinationPath)
        let repoName = url.deletingPathExtension().lastPathComponent
        let finalURL = destURL.appendingPathComponent(repoName)

        if FileManager.default.fileExists(atPath: finalURL.path) {
            errorMessage = "A folder named \"\(repoName)\" already exists at the destination."
            showingError = true
            return
        }

        // For now, accept the UI flow. Actual git clone via Process can be added later.
        onClone(finalURL)
        dismiss()
    }
}
