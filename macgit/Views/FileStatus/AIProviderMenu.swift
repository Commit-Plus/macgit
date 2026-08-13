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

struct AIProviderMenu: View {
    @ObservedObject var controller: AIProviderController

    var body: some View {
        Menu {
            ForEach(controller.descriptors) { descriptor in
                Button {
                    if requiresConfiguration(descriptor) {
                        NotificationCenter.default.post(
                            name: .showAppSettings,
                            object: nil,
                            userInfo: ["section": AppSettingsSection.aiProviders.rawValue]
                        )
                    } else {
                        controller.selectProvider(descriptor.id)
                    }
                } label: {
                    Label {
                        Text(menuTitle(for: descriptor))
                    } icon: {
                        Image(systemName: descriptor.id == controller.selectedProviderID
                            ? "checkmark"
                            : descriptor.systemImage)
                    }
                }
                .disabled(!descriptor.isImplemented || controller.isGenerating)
                .help(controller.availability(for: descriptor.id).detail)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.selectedProviderAvailability.isAvailable
                    ? "sparkles"
                    : "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                Text(controller.selectedDescriptor.displayName)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 10))
        .disabled(controller.isGenerating)
        .help(providerHelp)
    }

    private var providerHelp: String {
        let descriptor = controller.selectedDescriptor
        let availability = controller.selectedProviderAvailability
        if let model = controller.model(for: descriptor) {
            return "Cloud · \(model) · \(availability.detail)"
        }
        return "\(descriptor.detail) · \(availability.detail)"
    }

    private func menuTitle(for descriptor: AIProviderDescriptor) -> String {
        if descriptor.id == .appleIntelligence {
            return "\(descriptor.displayName) — On-device"
        }
        if requiresConfiguration(descriptor) {
            return "\(descriptor.displayName) — Config"
        }
        return "\(descriptor.displayName) — \(controller.model(for: descriptor) ?? "Default")"
    }

    private func requiresConfiguration(_ descriptor: AIProviderDescriptor) -> Bool {
        descriptor.dataProcessing == .cloud
            && !controller.isAPIKeyConfigured(for: descriptor.id)
    }
}
