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

struct ReflogDetailPanel: View {
    let entry: ReflogEntry
    let onClose: () -> Void
    let onShowCommit: () -> Void
    let onCreateBranch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Reflog Detail", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button("Close detail", systemImage: "xmark", action: onClose)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Close reflog detail")
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(entry.message)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            Text("Action").foregroundStyle(.secondary)
                            ReflogActionChip(action: entry.action)
                        }
                        detailRow("Reference", value: entry.reference)
                        detailRow("Event Date", value: entry.date?.formatted(date: .abbreviated, time: .complete) ?? "Unknown")
                        GridRow(alignment: .center) {
                            Text("Performed By").foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                ReflogActorAvatar(name: entry.actor, email: entry.email)
                                Text(entry.actor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        detailRow("Email", value: entry.email)
                        GridRow(alignment: .top) {
                            Text("Commit").foregroundStyle(.secondary)
                            Text(entry.hash)
                                .font(.callout.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    Text("This event records a local reference update. The commit is the destination of that update. Create a branch from it to keep a recovered commit.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            Divider()
            HStack {
                Button("Show Commit", action: onShowCommit)
                Spacer()
                Button("Create Branch…", action: onCreateBranch)
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
}
