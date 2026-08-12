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

struct DeviceLimitSheet: View {
    @ObservedObject var controller: AccountSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Signed-in Mac Limit Reached", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
                .font(.title2.bold())

            if let limit = controller.deviceAccessState.reachedLimit {
                Text("This Commit+ account already uses all \(limit) signed-in Mac \(limit == 1 ? "slot" : "slots"). Remove a Mac from your web profile, then try again here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    "Guest mode and all local Git data remain available on every Mac.",
                    systemImage: "externaldrive.badge.checkmark"
                )
                .foregroundStyle(.secondary)

                Button(action: manageDevicesOnWeb) {
                    Label("Manage Devices on Web", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                .disabled(controller.isOpeningAccountOnWeb || controller.isUpdatingDeviceAccess)

                if limit == 1 {
                    Button("View Commit+ Pro Plans", systemImage: "star.fill", action: openPricing)
                        .disabled(controller.isOpeningAccountOnWeb || controller.isUpdatingDeviceAccess)
                }
            } else {
                Text(controller.errorMessage ?? "Commit+ could not verify this Mac. Check your connection and try again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            HStack {
                Button("Cancel", role: .cancel, action: controller.cancelDeviceActivation)
                Spacer()
                if controller.isUpdatingDeviceAccess {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking signed-in Mac access")
                }
                Button("Try Again", action: retry)
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.isUpdatingDeviceAccess)
            }
        }
        .padding(24)
        .frame(minWidth: 500)
        .interactiveDismissDisabled(controller.isUpdatingDeviceAccess)
    }

    private func retry() {
        Task { await controller.retryDeviceActivation() }
    }

    private func manageDevicesOnWeb() {
        Task { await controller.openDeviceManagementOnWeb() }
    }

    private func openPricing() {
        Task { await controller.openPricingOnWeb() }
    }
}
