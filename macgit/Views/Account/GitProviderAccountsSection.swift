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

import AppKit
import SwiftUI

struct GitProviderAccountsSection: View {
    @ObservedObject var controller: GitProviderAccountController
    let isSignedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Git Provider Accounts")
                .font(.headline)
                .fontWeight(.semibold)

            if isSignedIn {
                if controller.accounts.isEmpty {
                    Text("Connect a Git provider account to use private repositories and pull request workflows.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(controller.accounts) { account in
                            GitProviderAccountRow(
                                account: account,
                                reconnect: { Task { await controller.reconnect(account) } },
                                disconnect: { Task { await controller.disconnect(account) } }
                            )
                        }
                    }
                }

                Button("Add GitHub Account...", systemImage: "plus") {
                    Task { await controller.connectGitHub() }
                }
                .disabled(controller.isLoading)

                if let authorization = controller.pendingDeviceAuthorization {
                    GitProviderDeviceAuthorizationView(
                        authorization: authorization,
                        openVerification: controller.openPendingDeviceVerification,
                        copyToPasteboard: copyToPasteboard
                    )
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
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct GitProviderDeviceAuthorizationView: View {
    let authorization: GitProviderDeviceAuthorization
    let openVerification: () -> Void
    let copyToPasteboard: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter this code on GitHub to finish connecting:")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(authorization.userCode)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)

                Button {
                    copyToPasteboard(authorization.userCode)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy GitHub device code")
                .help("Copy code")
            }

            Button("Open GitHub Device Page", action: openVerification)
        }
        .padding(.top, 2)
    }
}
