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

private enum SubtreeSheetMode: String, CaseIterable, Identifiable {
    case linkExisting = "Link Existing"
    case addNew = "Add New"

    var id: String { rawValue }
}

struct AddLinkSubtreeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let onLink: (SubtreeLinkRequest) async throws -> GitSubtreeEntry
    let onCompleted: (GitSubtreeEntry) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var mode: SubtreeSheetMode = .linkExisting
    @State private var name = ""
    @State private var path = ""
    @State private var repository = ""
    @State private var branch = "main"
    @State private var squash = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canLink: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && mode == .linkExisting
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add/Link Subtree")
                    .font(.title2)
                    .fontWeight(.semibold)

                Picker("Mode", selection: $mode) {
                    ForEach(SubtreeSheetMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .addNew {
                    Text("Available in Phase 5")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                fieldRow(title: "Name") {
                    TextField("SharedKit", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Local folder") {
                    TextField("Packages/SharedKit", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Repository URL") {
                    TextField("https://github.com/user/repo.git", text: $repository)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Branch") {
                    TextField("main", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                Toggle("Squashed", isOn: $squash)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 540, alignment: .leading)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isLoading)

                Button(isLoading ? "Linking..." : "Link Subtree") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canLink)
                .help(mode == .addNew ? "Available in Phase 5" : "")
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 640)
        .frame(minHeight: 360, idealHeight: 440)
    }

    private func fieldRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 132, alignment: .trailing)
            content()
        }
    }

    private func submit() {
        guard canLink else { return }

        let request = SubtreeLinkRequest(
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: squash
        )
        isLoading = true
        errorMessage = nil
        onRunRepositoryOperation("Linking subtree \(path)...") {
            do {
                let entry = try await onLink(request)
                await MainActor.run {
                    onCompleted(entry)
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

