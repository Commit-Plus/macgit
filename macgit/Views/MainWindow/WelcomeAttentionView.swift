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

struct WelcomeAttentionView: View {
    let repositories: [WelcomeRepositoryAttention]
    let isLoading: Bool
    let hasRepositories: Bool
    let updatedAt: Date?
    let onReview: (WelcomeRepositoryAttention) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Needs your attention").font(.title3.bold())
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }
            if repositories.isEmpty {
                Label(isLoading ? "Checking local repositories…" : hasRepositories ? "All caught up" : "Open a repository to see tasks here",
                      systemImage: isLoading ? "clock" : "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text("Current branches · Ahead / behind reflects the last fetch. No automatic fetch.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(repositories) { repository in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: repository.priority == 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.branch")
                            .foregroundStyle(repository.priority == 0 ? Color.orange : Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(repository.name).font(.subheadline.bold())
                            if !repository.unavailable {
                                Text(repository.branch).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(repository.summary).font(.caption).foregroundStyle(.secondary)
                            if let error = repository.error, repository.priority < 5 {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(repository.unavailable ? "Locate Folder" : repository.showsHistory ? "View History" : "Review") {
                            onReview(repository)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if let updatedAt, !repositories.isEmpty {
                Text("Checked \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
    }
}
