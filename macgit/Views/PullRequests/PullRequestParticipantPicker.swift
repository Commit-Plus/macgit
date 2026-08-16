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

struct PullRequestParticipantPicker: View {
    let title: String
    let participants: [PullRequestParticipant]
    @Binding var selectedIDs: Set<String>
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if participants.isEmpty {
                Text("No available users")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Menu {
                    Button {
                        selectedIDs.removeAll()
                    } label: {
                        if selectedIDs.isEmpty {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    .disabled(selectedIDs.isEmpty)

                    Divider()

                    ForEach(participants) { participant in
                        Button {
                            toggle(participant.id)
                        } label: {
                            if selectedIDs.contains(participant.id) {
                                Label(participant.username, systemImage: "checkmark")
                            } else {
                                Text(participant.username)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectionLabel)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectionLabel: String {
        let selected = participants
            .filter { selectedIDs.contains($0.id) }
            .map(\.username)
        return selected.isEmpty ? "None" : selected.joined(separator: ", ")
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
