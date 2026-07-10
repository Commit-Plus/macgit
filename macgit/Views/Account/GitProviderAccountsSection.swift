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
    @State private var connectionTask: Task<Void, Never>?
    @State private var showingAddAccountSheet = false
    @State private var editingAccount: GitProviderAccount?

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
                                edit: { editingAccount = account },
                                delete: { Task { await controller.disconnect(account) } }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("Add", systemImage: "plus") {
                        showingAddAccountSheet = true
                    }
                    .disabled(controller.isLoading)
                }

                if let authorization = controller.pendingDeviceAuthorization {
                    GitProviderDeviceAuthorizationView(
                        authorization: authorization,
                        openVerification: controller.openPendingDeviceVerification,
                        copyToPasteboard: copyToPasteboard,
                        cancel: cancelConnection
                    )
                }
            } else {
                Button("Sign in to Commit+ to connect a Git provider account", systemImage: "person.crop.circle.badge.exclamationmark") {}
                    .disabled(true)
            }

            if controller.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Updating Git provider accounts...")
                        .controlSize(.small)
                    Spacer()
                }
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear(perform: cancelConnection)
        .sheet(isPresented: $showingAddAccountSheet) {
            GitProviderAddAccountSheet(controller: controller)
        }
        .sheet(item: $editingAccount) { account in
            GitProviderAddAccountSheet(controller: controller, editingAccount: account)
        }
    }

    private func startConnection(_ operation: @escaping @MainActor () async -> Void) {
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            await operation()
            connectionTask = nil
        }
    }

    private func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
