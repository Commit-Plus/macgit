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

struct ManageAccountSheet: View {
    @ObservedObject var controller: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Manage Account")
                .font(.title2)
                .bold()

            if let account = controller.account {
                Form {
                    LabeledContent("Account", value: account.displayLabel)
                    LabeledContent("Sign-in methods", value: providerSummary(for: account))
                    LabeledContent("Plan") {
                        Label(
                            controller.entitlement.hasProAccess ? "Pro" : "Free",
                            systemImage: controller.entitlement.hasProAccess ? "star.fill" : "person"
                        )
                    }
                    LabeledContent("Sync Settings") {
                        syncSettingsControl
                    }
                    if let entitlementError = controller.entitlementError {
                        LabeledContent("Cloud status") {
                            Text(entitlementError)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)

                Button(billingActionTitle) {}
                    .disabled(true)

                Divider()

                Button("Sign Out", action: controller.signOut)

                if controller.requiresRecentAuthentication {
                    Button("Sign In Again...", action: controller.presentReauthentication)
                }

                Button("Delete Account...", role: .destructive) {
                    confirmsDeletion = true
                }
                .disabled(controller.isDeletingAccount)

                if controller.isDeletingAccount {
                    ProgressView("Deleting account...")
                        .controlSize(.small)
                }

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let settingsSyncError = controller.settingsSyncError {
                    Text(settingsSyncError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ContentUnavailableView(
                    "Not Signed In",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Sign in to manage your Commit+ account.")
                )
            }

            GitProviderAccountsSection(
                controller: providerAccountController,
                isSignedIn: controller.account != nil
            )

            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 480)
        .alert("Delete Commit+ Account?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await controller.deleteAccount() }
            }
        } message: {
            Text("This removes your Commit+ cloud settings, entitlement record, and account. Local repositories and Git data will not be changed.")
        }
    }

    private var billingActionTitle: String {
        controller.entitlement.hasProAccess
            ? "Manage Subscription · Coming later"
            : "Upgrade to Pro · Coming later"
    }

    @ViewBuilder
    private var syncSettingsControl: some View {
        HStack(spacing: 8) {
            Toggle(
                "Sync Settings",
                isOn: Binding(
                    get: { controller.settingsSyncEnabled },
                    set: controller.setSettingsSyncEnabled
                )
            )
            .labelsHidden()

            Text(controller.settingsSyncDisplayText)
                .foregroundStyle(.secondary)
        }
    }

    private func providerSummary(for account: AccountSnapshot) -> String {
        let names = account.providerIDs.map { providerID in
            switch providerID {
            case "password": "Email & Password"
            case "google.com": "Google"
            default: providerID
            }
        }
        return names.isEmpty ? "Unknown" : names.joined(separator: ", ")
    }

    private func dismiss() {
        controller.presentedSheet = nil
    }
}

struct SettingsSyncConflictSheet: View {
    @ObservedObject var controller: AccountSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Settings to Sync")
                .font(.title2)
                .bold()

            Text("This Mac and your cloud account have different settings. Choose which version Commit+ should use on all synced devices.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                settingsGroup(title: "Current Mac", snapshot: controller.localSettingsSnapshot)
                settingsGroup(title: "Cloud", snapshot: controller.pendingCloudSettings ?? controller.localSettingsSnapshot)
            }

            HStack {
                Button("Cancel") {
                    resolve(.cancel)
                }
                Spacer()
                Button("Use Cloud Settings") {
                    resolve(.useCloud)
                }
                Button("Keep This Mac's Settings") {
                    resolve(.keepThisMac)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560)
        .interactiveDismissDisabled()
    }

    private func settingsGroup(title: String, snapshot: AppSettingsSnapshot) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                settingRow("Toolbar button text", enabled: snapshot.showToolbarButtonText)
                settingRow("Submodules", enabled: snapshot.showSubmodules)
                settingRow("Subtrees", enabled: snapshot.showSubtrees)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func settingRow(_ label: String, enabled: Bool) -> some View {
        GridRow {
            Text(label)
            Label(enabled ? "Shown" : "Hidden", systemImage: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(enabled ? .primary : .secondary)
        }
    }

    private func resolve(_ choice: InitialSettingsChoice) {
        Task { await controller.resolveInitialSettingsChoice(choice) }
    }
}
