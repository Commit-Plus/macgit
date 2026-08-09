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

struct CreateGitFlowDevelopBranchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let startingPoint: String
    let onCreate: @MainActor (GitFlowDevelopBranchRequest) async throws -> String
    let onCreated: (String) -> Void

    @State private var branchName: String
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(
        suggestedName: String,
        startingPoint: String,
        onCreate: @escaping @MainActor (GitFlowDevelopBranchRequest) async throws -> String,
        onCreated: @escaping (String) -> Void
    ) {
        self.startingPoint = startingPoint
        self.onCreate = onCreate
        self.onCreated = onCreated
        _branchName = State(initialValue: suggestedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Develop Branch")
                .font(.title2)
                .bold()

            LabeledContent("Branch name") {
                TextField("develop", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
            }

            LabeledContent("Starting point") {
                Text(startingPoint)
                    .bold()
            }

            Text("The branch will be created locally without changing your current branch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)

                Button("Create Branch", action: createBranch)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                    .disabled(trimmedBranchName.isEmpty || startingPoint.isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 500)
        .disabled(isCreating)
    }

    private var trimmedBranchName: String {
        branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createBranch() {
        errorMessage = nil
        isCreating = true
        let request = GitFlowDevelopBranchRequest(
            name: trimmedBranchName,
            startingPoint: startingPoint
        )
        Task { [request] in
            do {
                let createdBranch = try await onCreate(request)
                await MainActor.run {
                    onCreated(createdBranch)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
