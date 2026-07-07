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

struct GitProviderAccountsSection: View {
    @ObservedObject var controller: GitProviderAccountController
    let isSignedIn: Bool

    var body: some View {
        GroupBox("Git Provider Accounts") {
            VStack(alignment: .leading, spacing: 12) {
                if isSignedIn {
                    if controller.accounts.isEmpty {
                        Text("Connect a Git provider account to use private repositories and pull request workflows.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(controller.accounts) { account in
                            GitProviderAccountRow(
                                account: account,
                                reconnect: { Task { await controller.reconnect(account) } },
                                disconnect: { Task { await controller.disconnect(account) } }
                            )
                        }
                    }

                    Button("Add GitHub Account...", systemImage: "plus") {
                        Task { await controller.connectGitHub() }
                    }
                    .disabled(controller.isLoading)

                    if let authorization = controller.pendingDeviceAuthorization {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enter this code on GitHub to finish connecting:")
                                .foregroundStyle(.secondary)
                            Text(authorization.userCode)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                            Button("Open GitHub Device Page", action: controller.openPendingDeviceVerification)
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Button("Sign in to Commit+ to connect a Git provider account", systemImage: "person.crop.circle.badge.exclamationmark") {}
                        .disabled(true)
                }

                if controller.isLoading {
                    ProgressView("Updating Git provider accounts...")
                        .controlSize(.small)
                }

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
