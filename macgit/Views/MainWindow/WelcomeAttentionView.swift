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
    let snapshot: WelcomeDashboardSnapshot
    let isLoading: Bool
    let onRepositoryOpened: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Needs your attention").font(.title3.bold())
            Text("Current branch · Remote status reflects the last fetch, which may be out of date.")
                .font(.caption).foregroundStyle(.secondary)
            if isLoading {
                Label("Checking local repositories…", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if snapshot.attentionCount == 0 {
                Label(snapshot.repositories.isEmpty ? "Repository notices will appear here" : "No issues found in the scanned repositories", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(snapshot.repositories.filter(\.needsAttention)) { repository in
                Button { onRepositoryOpened(repository.url) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: repository.conflictCount > 0 ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(repository.conflictCount > 0 ? Color.orange : Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(repository.name).font(.subheadline.bold())
                            if repository.conflictCount > 0 {
                                Text("\(repository.conflictCount) file(s) with unresolved conflicts")
                            }
                            if repository.behindCount > 0 {
                                Text("\(repository.behindCount) commit(s) behind cached upstream · Review before pulling")
                            }
                            if let note = repository.activityNote { Text(note) }
                            if let note = repository.statusNote { Text(note) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(repository.name) to review")
            }
            Divider()
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("More notifications, later").font(.caption.weight(.medium))
                    Text("A home for repository reminders and background task results.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bell.badge").foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
    }
}
