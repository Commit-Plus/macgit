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
                        Text(controller.entitlement.hasProAccess ? "Coming in Phase 3" : "Requires Pro")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                Button(billingActionTitle) {}
                    .disabled(true)

                Divider()

                Button("Sign Out", action: controller.signOut)

                Button("Delete Account...", role: .destructive) {}
                    .disabled(true)
                    .accessibilityHint("Account deletion will be available after secure reauthentication is added in Phase 2.")
            } else {
                ContentUnavailableView(
                    "Not Signed In",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Sign in to manage your Commit+ account.")
                )
            }

            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 360)
    }

    private var billingActionTitle: String {
        controller.entitlement.hasProAccess
            ? "Manage Subscription · Coming later"
            : "Upgrade to Pro · Coming later"
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
