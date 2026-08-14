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
    private let accountCreationDecision: GitProviderAccountCreationDecision

    @State private var selectedHost: GitProviderAddAccountHost = .github
    @State private var selectedAuthType: GitProviderAddAccountAuthType = .oauth
    @State private var selectedProtocol: GitProviderAddAccountProtocol = .https
    @State private var connectedUsername = ""
    @State private var bitbucketUsername = ""
    @State private var bitbucketAPIToken = ""
    @State private var sshKeyPath = ""
    @State private var connectionTask: Task<Void, Never>?

    init(
        controller: GitProviderAccountController,
        editingAccount: GitProviderAccount? = nil,
        accountCreationDecision: GitProviderAccountCreationDecision = .allowed
    ) {
        self.controller = controller
        self.editingAccount = editingAccount
        self.accountCreationDecision = accountCreationDecision
        _selectedHost = State(initialValue: editingAccount.map(GitProviderAddAccountPresentationPolicy.host(for:)) ?? .github)
        _selectedAuthType = State(initialValue: editingAccount?.provider == .bitbucket ? .personalAccessToken : .oauth)
        _selectedProtocol = State(initialValue: editingAccount?.transportProtocol == .ssh ? .ssh : .https)
        _connectedUsername = State(initialValue: editingAccount?.username ?? "")
        _bitbucketUsername = State(initialValue: editingAccount?.provider == .bitbucket ? editingAccount?.username ?? "" : "")
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
                    bitbucketUsername = ""
                    bitbucketAPIToken = ""
                    selectedAuthType = selectedHost == .bitbucket ? .personalAccessToken : .oauth
                }

                Picker("Auth Type", selection: $selectedAuthType) {
                    ForEach(GitProviderAddAccountPresentationPolicy.authTypeOptions(for: selectedHost), id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }
                .disabled(!GitProviderAddAccountPresentationPolicy.canSelectAuthType(for: selectedHost))

                if selectedHost == .bitbucket {
                    TextField("Username", text: $bitbucketUsername)
                        .disabled(editingAccount != nil)
                    if selectedProtocol == .https {
                        SecureField("API Token", text: $bitbucketAPIToken)
                        Text("Requires read:repository:bitbucket and write:repository:bitbucket scopes.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Get API Token", action: openBitbucketAPITokenPage)
                            .buttonStyle(.link)
                    }
                } else {
                    LabeledContent("Username") {
                        Text(GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: connectedUsername))
                            .foregroundStyle(connectedUsername.isEmpty ? .secondary : .primary)
                    }
                }

                if selectedProtocol == .https {
                    Button(connectButtonTitle, action: connectAccount)
                        .disabled(!canConnect || controller.isLoading)
                }

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

                    Button(connectButtonTitle, action: connectAccount)
                        .disabled(!canConnect || controller.isLoading || sshKeyPath.isEmpty)
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

            if editingAccount == nil,
               matchingAccount() == nil,
               let message = GitProviderAccountsPresentationPolicy.accountCreationMessage(
                   for: accountCreationDecision
               ) {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Need help logging into your account?", action: openGitProviderHelpPage)
                    .buttonStyle(.link)

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
        guard (editingAccount != nil || accountCreationDecision.isAllowed),
              GitProviderAddAccountPresentationPolicy.canConnect(
            host: selectedHost,
            authType: selectedAuthType,
            protocol: selectedProtocol
        ) else {
            return false
        }
        guard selectedHost == .bitbucket else { return true }
        guard !bitbucketUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if selectedProtocol == .ssh {
            return !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !bitbucketAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var connectButtonTitle: String {
        GitProviderAddAccountPresentationPolicy.connectButtonTitle(
            connectedUsername: connectedUsername,
            protocol: selectedProtocol
        )
    }

    private var canSave: Bool {
        (editingAccount != nil || matchingAccount() != nil || accountCreationDecision.isAllowed)
            && GitProviderAddAccountPresentationPolicy.canSave(
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
            switch selectedHost {
            case .github:
                if let editingAccount {
                    await controller.reconnect(editingAccount)
                } else {
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(host: .githubDotCom, key: GitProviderSSHKey(path: sshKeyPath))
                    } else {
                        await controller.connectGitHub()
                    }
                }
            case .gitlab:
                if let editingAccount {
                    await controller.reconnect(editingAccount)
                } else {
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(host: .gitlabDotCom, key: GitProviderSSHKey(path: sshKeyPath))
                    } else {
                        await controller.connectGitLabDotCom()
                    }
                }
            case .bitbucket:
                if selectedProtocol == .ssh {
                    await controller.connectSSH(
                        host: .bitbucketDotOrg,
                        key: GitProviderSSHKey(path: sshKeyPath),
                        username: bitbucketUsername,
                        replacing: editingAccount
                    )
                } else {
                    await controller.connectBitbucket(
                        username: bitbucketUsername,
                        apiToken: bitbucketAPIToken,
                        replacing: editingAccount
                    )
                    if controller.errorMessage == nil {
                        bitbucketAPIToken = ""
                    }
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
                return account.provider == .bitbucket
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

    private func openBitbucketAPITokenPage() {
        guard let url = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openGitProviderHelpPage() {
        do {
            let url = try CommitPlusWebConfiguration.baseURL()
                .appending(path: "blog")
                .appending(path: "connect-git-provider-accounts")
            guard NSWorkspace.shared.open(url) else {
                throw WebAccountSessionError.unableToOpenBrowser
            }
        } catch {
            controller.errorMessage = error.localizedDescription
        }
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
