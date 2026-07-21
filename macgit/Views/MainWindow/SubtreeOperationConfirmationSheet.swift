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

struct SubtreeOperationConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let operation: SubtreeOperation
    let entry: GitSubtreeEntry
    let onConfirm: () async throws -> Void
    let onCompleted: () -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Repository", entry.repository)
                    detailRow("Branch", entry.branch)
                    detailRow("Local folder", entry.path)
                    detailRow("Squash policy", entry.squash ? "Squash imported history" : "Preserve subtree history")
                }

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isLoading)

                Button(isLoading ? loadingTitle : actionTitle) {
                    confirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(isLoading)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 660)
        .frame(minHeight: 300, idealHeight: 360)
    }

    private var title: String {
        switch operation {
        case .add:
            "Add Subtree"
        case .pull:
            "Pull from Subtree Remote"
        case .push:
            "Push to Subtree Remote"
        }
    }

    private var actionTitle: String {
        switch operation {
        case .add:
            "Add"
        case .pull:
            "Pull"
        case .push:
            "Push"
        }
    }

    private var loadingTitle: String {
        switch operation {
        case .add:
            "Adding..."
        case .pull:
            "Pulling..."
        case .push:
            "Pushing..."
        }
    }

    private var progressTitle: String {
        switch operation {
        case .add:
            "Adding subtree..."
        case .pull:
            "Pulling \(entry.name)..."
        case .push:
            "Pushing \(entry.name)..."
        }
    }

    private var message: String {
        switch operation {
        case .add:
            "Add \(entry.repository) \(entry.branch) into \(entry.path)."
        case .pull:
            "Pull \(entry.repository) \(entry.branch) into \(entry.path)."
        case .push:
            "Commits affecting \(entry.path) will be split and sent to \(entry.repository) \(entry.branch)."
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func confirm() {
        isLoading = true
        errorMessage = nil
        onRunRepositoryOperation(progressTitle) {
            do {
                try await onConfirm()
                await MainActor.run {
                    isLoading = false
                    onCompleted()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = sanitizedErrorMessage(error.localizedDescription)
                    isLoading = false
                }
            }
        }
    }

    private func sanitizedErrorMessage(_ message: String) -> String {
        let lines = message
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let limited = lines.prefix(8).joined(separator: "\n")
        return limited.isEmpty ? "The subtree operation failed." : limited
    }
}
