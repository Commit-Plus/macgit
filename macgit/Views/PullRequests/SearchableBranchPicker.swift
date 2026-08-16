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

struct SearchableBranchPicker: View {
    let title: String
    @Binding var selection: String?
    let placeholder: String
    let noneTitle: String
    let allowsNone: Bool
    let loadBranches: (String) async -> [String]

    @State private var isPresented = false
    @State private var searchText = ""
    @State private var branches: [String] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isPresented = true
            } label: {
                HStack(spacing: 6) {
                    Text(selection ?? noneTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isPresented) {
                pickerPopover
                    .frame(minWidth: 260, idealWidth: 280, minHeight: 320, idealHeight: 380)
            }
        }
    }

    private var pickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }
            .onAppear {
                isSearchFieldFocused = true
            }

            if isLoading && branches.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if branches.isEmpty {
                Spacer()
                Text("No branches found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    if allowsNone {
                        Button {
                            selection = nil
                            isPresented = false
                        } label: {
                            HStack {
                                Text(noneTitle)
                                Spacer()
                                if selection == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(branches, id: \.self) { branch in
                        Button {
                            selection = branch
                            isPresented = false
                        } label: {
                            HStack {
                                Text(branch)
                                Spacer()
                                if selection == branch {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            searchTask?.cancel()
            searchTask = Task {
                await load()
            }
        }
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = await loadBranches(query)
        guard !Task.isCancelled else { return }
        branches = results
        isLoading = false
    }
}
