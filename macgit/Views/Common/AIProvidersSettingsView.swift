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

struct AIProvidersSettingsView: View {
    @ObservedObject var controller: AIProviderController

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(
                        controller.availability(for: .appleIntelligence).detail,
                        systemImage: appleStatusImage
                    )
                    .foregroundStyle(appleStatusStyle)
                }

                LabeledContent("Processing") {
                    Text("On-device")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Apple Intelligence", systemImage: "apple.intelligence")
            } footer: {
                Text("Commit+ processes staged changes on this Mac. Source code is not uploaded to an AI service.")
            }

            ForEach(controller.descriptors.filter { $0.dataProcessing == .cloud }) { descriptor in
                CloudAIProviderSettingsSection(
                    descriptor: descriptor,
                    controller: controller
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Providers")
        .task {
            await controller.refreshAvailability()
        }
    }

    private var appleStatusImage: String {
        switch controller.availability(for: .appleIntelligence) {
        case .available: "checkmark.circle.fill"
        case .checking: "clock"
        case .unavailable: "exclamationmark.triangle.fill"
        case .comingSoon: "clock"
        }
    }

    private var appleStatusStyle: HierarchicalShapeStyle {
        controller.availability(for: .appleIntelligence).isAvailable ? .primary : .secondary
    }
}
