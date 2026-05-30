//
//  RepoPickerView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

struct RepoPickerView: View {
    @ObservedObject private var store = RecentRepositoriesStore.shared
    @State private var showingCloneSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var onRepositoryOpened: (URL) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to MacGit")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Open an existing repository or clone a new one")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button(action: openExistingRepository) {
                    Label("Open Existing Repository", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 220)

                Button(action: { showingCloneSheet = true }) {
                    Label("Clone New Repository", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(width: 220)
            }

            if !store.repositories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    List {
                        ForEach(store.repositories) { repo in
                            Button(action: {
                                store.add(repo.url)
                                onRepositoryOpened(repo.url)
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repo.name)
                                            .font(.body)
                                        Text(repo.url.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(repo.lastOpened, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: store.remove(at:))
                    }
                    .listStyle(.plain)
                    .frame(height: min(CGFloat(store.repositories.count) * 56 + 8, 280))
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(16)
                }
                .frame(maxWidth: 460)
            }

            Spacer()
        }
        .frame(minWidth: 560, minHeight: 480)
        .padding(40)
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

    var onClone: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Clone Repository")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Remote URL")
                    .font(.headline)
                TextField("https://github.com/user/repo.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
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
