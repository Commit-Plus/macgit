//
//  CommitDragPreviewPresentation.swift
//  macgit
//

import Foundation

nonisolated struct CommitDragPreviewPresentation: Equatable, Sendable {
    let subject: String
    let shortHash: String
    let author: String
    let date: Date
    let commitCount: Int

    init(commit: Commit, commitCount: Int) {
        self.subject = commit.message
        self.shortHash = commit.shortHash
        self.author = commit.author
        self.date = commit.date
        self.commitCount = max(1, commitCount)
    }

    var showsStack: Bool {
        commitCount > 1
    }

    var countBadgeText: String? {
        showsStack ? "\(commitCount) commits" : nil
    }
}
