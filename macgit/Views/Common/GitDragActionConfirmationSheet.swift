//
//  GitDragActionConfirmationSheet.swift
//  macgit
//

import SwiftUI

struct GitDragActionConfirmationSheet: View {
    let title: String
    let message: String
    let targetBranchName: String
    let commits: [GitDraggedCommit]
    let primaryActionTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        title: String = "Confirm Commit Drop",
        message: String = "Review the commits before continuing.",
        targetBranchName: String,
        commits: [GitDraggedCommit],
        primaryActionTitle: String = "Continue",
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.targetBranchName = targetBranchName
        self.commits = commits
        self.primaryActionTitle = primaryActionTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Target branch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(targetBranchName)
                    .font(.system(size: 13, weight: .medium))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commits")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(commits.enumerated()), id: \.element.hash) { index, commit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(commit.hash)")
                                    .font(.system(size: 12, weight: .medium))
                                Text(commit.message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(primaryActionTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560)
    }
}

#Preview {
    GitDragActionConfirmationSheet(
        targetBranchName: "main",
        commits: [
            GitDraggedCommit(hash: "a1b2c3d", message: "Add commit drag policy", isMerge: false),
            GitDraggedCommit(hash: "d4e5f6g", message: "Refine drop affordances", isMerge: false)
        ],
        primaryActionTitle: "Cherry-pick",
        onConfirm: {},
        onCancel: {}
    )
}
