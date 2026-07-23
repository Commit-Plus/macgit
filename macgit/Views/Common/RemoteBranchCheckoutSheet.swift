//
//  RemoteBranchCheckoutSheet.swift
//  macgit
//

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

struct RemoteBranchCheckoutTarget: Identifiable {
    let id = UUID()
    let remote: String
    let branch: String

    var remoteReference: String { "\(remote)/\(branch)" }
}

struct RemoteBranchCheckoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: RemoteBranchCheckoutTarget
    let onConfirm: (String, Bool) -> Void

    @State private var localBranchName: String
    @State private var trackRemote = true

    init(target: RemoteBranchCheckoutTarget, onConfirm: @escaping (String, Bool) -> Void) {
        self.target = target
        self.onConfirm = onConfirm
        _localBranchName = State(initialValue: target.branch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Checkout New Branch")
                    .font(.headline)
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 8) {
                Text("Checkout remote branch:")
                    .frame(width: 150, alignment: .leading)
                Text(target.remoteReference)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text("New local branch name:")
                    .frame(width: 150, alignment: .leading)
                TextField("Branch name", text: $localBranchName)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Local branch should track remote branch", isOn: $trackRemote)
                .toggleStyle(.checkbox)
                .padding(.leading, 158)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Checkout") {
                    let name = localBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    onConfirm(name, trackRemote)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(localBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560)
    }
}
