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
    @State private var deviceToReplace: AccountDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Device Limit Reached", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
                .font(.title2.bold())

            if let details = controller.deviceAccessState.limitReachedDetails {
                Text("This Commit+ account is using \(details.devices.count) of \(details.limit) available Mac \(details.limit == 1 ? "slot" : "slots"). Replace one of the Macs below to continue signing in here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                deviceList(details.devices)

                if details.limit == 1 {
                    Button(action: openPricing) {
                        Label("Get Commit+ Pro for up to 3 Macs", systemImage: "star.fill")
                    }
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
                        .accessibilityLabel("Updating device access")
                }
                Button("Try Again", action: retry)
                    .disabled(controller.isUpdatingDeviceAccess)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
        .interactiveDismissDisabled(controller.isUpdatingDeviceAccess)
        .confirmationDialog(
            "Replace this Mac?",
            isPresented: Binding(
                get: { deviceToReplace != nil },
                set: { if !$0 { deviceToReplace = nil } }
            ),
            presenting: deviceToReplace
        ) { device in
            Button("Replace \(device.modelFamily)", role: .destructive) {
                replace(device)
            }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text("\(device.modelFamily) will be signed out of Commit+ cloud features. Local repositories and Git data on that Mac are not changed.")
        }
    }

    private func deviceList(_ devices: [AccountDevice]) -> some View {
        VStack(spacing: 0) {
            ForEach(devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .font(.title3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.modelFamily)
                            .fontWeight(.medium)
                        Text("macOS \(device.osVersion) · Commit+ \(device.appVersion) · Last used \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replace") { deviceToReplace = device }
                        .disabled(controller.isUpdatingDeviceAccess)
                }
                .padding(.vertical, 11)
                if device.id != devices.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func retry() {
        Task { await controller.retryDeviceActivation() }
    }

    private func replace(_ device: AccountDevice) {
        deviceToReplace = nil
        Task { await controller.replaceDevice(device) }
    }

    private func openPricing() {
        Task { await controller.openPricingOnWeb() }
    }
}
