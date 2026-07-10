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

struct GitProviderAddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: GitProviderAccountController
    private let editingAccount: GitProviderAccount?

    @State private var selectedHost: GitProviderAddAccountHost = .github
    @State private var selectedAuthType: GitProviderAddAccountAuthType = .oauth
    @State private var selectedProtocol: GitProviderAddAccountProtocol = .https
    @State private var connectedUsername = ""
    @State private var sshKeyPath = ""
    @State private var connectionTask: Task<Void, Never>?

    init(controller: GitProviderAccountController, editingAccount: GitProviderAccount? = nil) {
        self.controller = controller
        self.editingAccount = editingAccount
        _selectedHost = State(initialValue: editingAccount.map(GitProviderAddAccountPresentationPolicy.host(for:)) ?? .github)
        _selectedAuthType = State(initialValue: .oauth)
        _selectedProtocol = State(initialValue: editingAccount?.transportProtocol == .ssh ? .ssh : .https)
        _connectedUsername = State(initialValue: editingAccount?.username ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Form {
                Picker("Host", selection: $selectedHost) {
                    ForEach(GitProviderAddAccountPresentationPolicy.hostOptions, id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }
                .disabled(editingAccount != nil)
                .onChange(of: selectedHost) { _, _ in
                    connectedUsername = ""
                }

                Picker("Auth Type", selection: $selectedAuthType) {
                    ForEach(GitProviderAddAccountPresentationPolicy.authTypeOptions, id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }

                LabeledContent("Username") {
                    Text(GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: connectedUsername))
                        .foregroundStyle(connectedUsername.isEmpty ? .secondary : .primary)
                }

                Button(connectButtonTitle, action: connectAccount)
                    .disabled(!canConnect || controller.isLoading)

                Picker("Protocol", selection: $selectedProtocol) {
                    ForEach(GitProviderAddAccountPresentationPolicy.protocolOptions, id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }

                if selectedProtocol == .ssh {
                    LabeledContent("SSH Key") {
                        HStack {
                            Text(sshKeyPath.isEmpty ? "_" : abbreviatedPath(sshKeyPath))
                                .foregroundStyle(sshKeyPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Choose...", action: chooseSSHKey)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let authorization = controller.pendingDeviceAuthorization {
                GitProviderDeviceAuthorizationView(
                    authorization: authorization,
                    openVerification: controller.openPendingDeviceVerification,
                    copyToPasteboard: copyToPasteboard,
                    cancel: cancelConnection
                )
            }

            if controller.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Connecting account...")
                        .controlSize(.small)
                    Spacer()
                }
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Need help logging into your account?") {}
                    .buttonStyle(.link)
                    .disabled(true)

                Spacer()

                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 360)
        .onAppear(perform: loadExistingSSHKey)
        .onDisappear(perform: cancelConnection)
    }

    private var canConnect: Bool {
        GitProviderAddAccountPresentationPolicy.canConnect(
            host: selectedHost,
            authType: selectedAuthType,
            protocol: selectedProtocol
        )
    }

    private var connectButtonTitle: String {
        GitProviderAddAccountPresentationPolicy.connectButtonTitle(connectedUsername: connectedUsername)
    }

    private var canSave: Bool {
        GitProviderAddAccountPresentationPolicy.canSave(
            connectedUsername: connectedUsername,
            protocol: selectedProtocol,
            sshKeyPath: sshKeyPath
        )
    }

    private var title: String {
        editingAccount == nil ? "Add Account" : "Edit Account"
    }

    private func connectAccount() {
        guard canConnect else { return }
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            if let editingAccount {
                await controller.reconnect(editingAccount)
            } else {
                switch selectedHost {
                case .github:
                    await controller.connectGitHub()
                case .gitlab:
                    await controller.connectGitLabDotCom()
                case .bitbucket:
                    break
                }
            }
            refreshConnectedUsername()
            connectionTask = nil
        }
    }

    private func refreshConnectedUsername() {
        connectedUsername = matchingAccount()?.username ?? ""
    }

    private func matchingAccount() -> GitProviderAccount? {
        controller.accounts.first { account in
            switch selectedHost {
            case .github:
                return account.provider == .github
            case .gitlab:
                return account.provider == .gitlab && account.hostURL.host(percentEncoded: false) == "gitlab.com"
            case .bitbucket:
                return false
            }
        }
    }

    private func cancel() {
        cancelConnection()
        dismiss()
    }

    private func save() {
        guard canSave, let account = matchingAccount() ?? editingAccount else { return }
        let transportProtocol: GitProviderTransportProtocol = selectedProtocol == .ssh ? .ssh : .https
        let sshKey = selectedProtocol == .ssh ? GitProviderSSHKey(path: sshKeyPath) : nil
        Task { @MainActor in
            await controller.saveConnectionSettings(
                account: account,
                transportProtocol: transportProtocol,
                sshKey: sshKey
            )
            dismiss()
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

    private func loadExistingSSHKey() {
        guard let editingAccount,
              let key = try? controller.sshKey(for: editingAccount) else {
            return
        }
        sshKeyPath = key.path
    }

    private func chooseSSHKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else {
            return path
        }
        return "~" + path.dropFirst(home.count)
    }
}
