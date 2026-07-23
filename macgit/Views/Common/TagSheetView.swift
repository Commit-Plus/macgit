//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

enum TagCommitSource: Hashable {
    case workingCopyParent
    case specified(String)
}

struct TagCreationRequest: Equatable {
    let name: String
    let source: TagCommitSource
    let pushRemote: String?

    var commitReference: String {
        switch source {
        case .workingCopyParent:
            return "HEAD"
        case .specified(let commit):
            return commit
        }
    }
}

enum TagCreationPolicy {
    static func canSubmit(name: String, source: TagCommitSource) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .specified(let commit) = source {
            return !commit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}

struct TagSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onCreate: (TagCreationRequest) async throws -> Void

    @State private var tagName = ""
    @State private var source: TagCommitSource = .workingCopyParent
    @State private var commitOptions: [BranchCommitInfo] = []
    @State private var selectedCommit = ""
    @State private var pushTag = false
    @State private var remotes: [String] = []
    @State private var selectedRemote = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private var canSubmit: Bool {
        TagCreationPolicy.canSubmit(name: tagName, source: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tag Name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit:")
                    .font(.system(size: 13))

                Picker("", selection: $source) {
                    Text("Working copy parent").tag(TagCommitSource.workingCopyParent)
                    Text("Specified commit:").tag(TagCommitSource.specified(selectedCommit))
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedCommit) { _, newValue in
                    if case .specified = source {
                        source = .specified(newValue)
                    }
                }

                if case .specified = source {
                    Picker("", selection: $selectedCommit) {
                        Text("Select a commit...").tag("")
                        ForEach(commitOptions) { commit in
                            Text(commit.display)
                                .tag(commit.hash)
                                .lineLimit(1)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 300, alignment: .leading)
                    .padding(.leading, 20)
                }
            }

            HStack(spacing: 8) {
                Toggle("Push tag:", isOn: $pushTag)
                    .toggleStyle(.checkbox)
                    .onChange(of: pushTag) { _, isEnabled in
                        if isEnabled, selectedRemote.isEmpty {
                            selectedRemote = remotes.first ?? ""
                        }
                    }

                if pushTag {
                    Picker("", selection: $selectedRemote) {
                        if remotes.isEmpty {
                            Text("No remotes configured").tag("")
                        } else {
                            ForEach(remotes, id: \.self) { remote in
                                Text(remote).tag(remote)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(remotes.isEmpty)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    createTag()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || (pushTag && selectedRemote.isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
        .task {
            await loadData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadData() async {
        async let commits = GitStatusService.shared.recentCommits(limit: 50, in: repositoryURL)
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        let (recent, remoteNames) = await (commits, loadedRemotes)

        await MainActor.run {
            commitOptions = recent.map { BranchCommitInfo(hash: $0.hash, message: $0.message) }
            selectedCommit = commitOptions.first?.hash ?? ""
            remotes = remoteNames
            selectedRemote = remoteNames.first ?? ""
        }
    }

    private func createTag() {
        let request = TagCreationRequest(
            name: tagName.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            pushRemote: pushTag ? selectedRemote : nil
        )

        onRunRepositoryOperation("Creating tag \(request.name)...") {
            do {
                try await onCreate(request)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
