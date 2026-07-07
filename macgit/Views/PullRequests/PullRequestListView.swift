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

struct PullRequestListView: View {
    @ObservedObject var controller: PullRequestController
    let repositoryURL: URL
    var onConnectAccount: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            if controller.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = controller.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.headline)
                    if errorMessage == "Connect Account..." || errorMessage == "Reconnect..." {
                        Button(errorMessage, action: onConnectAccount)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.items.isEmpty {
                Text("No open pull requests")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(controller.items) { item in
                    PullRequestRow(summary: item) {
                        controller.openInBrowser(item)
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
        .task(id: repositoryURL) {
            await controller.loadPullRequests(repositoryURL: repositoryURL)
        }
    }

    private var header: some View {
        HStack {
            Text("Pull Requests")
                .font(.headline)
            Spacer()
            Button {
                Task { await controller.loadPullRequests(repositoryURL: repositoryURL) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(controller.isLoading)
            .help("Refresh pull requests")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
}

private struct PullRequestRow: View {
    let summary: PullRequestSummary
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(summary.number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(2)
                    if summary.state == .draft {
                        Text("Draft")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text("\(summary.source.ref) -> \(summary.target.ref)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(summary.author.username) updated \(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(action: onOpen) {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open in browser")
        }
        .padding(.vertical, 8)
    }
}
