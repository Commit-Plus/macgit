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
    @ObservedObject var accountController: AccountSessionController
    let restrictedProviderAccess: FeatureAccessDecision
    @Binding var drafts: [AIProviderConfigurationDraft]
    @State private var authenticationMode: AuthenticationMode?
    @State private var isOpeningRestrictedProviderAccess = false

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

            ForEach($drafts) { $draft in
                let descriptor = controller.descriptors.first { $0.id == draft.id }
                if let descriptor {
                    CloudAIProviderSettingsSection(
                        descriptor: descriptor,
                        controller: controller,
                        accountController: accountController,
                        draft: $draft,
                        restrictedProviderAccess: restrictedProviderAccess,
                        isOpeningAccess: isOpeningRestrictedProviderAccess,
                        onAccessAction: presentRestrictedProviderAccess
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Providers")
        .sheet(item: $authenticationMode) { mode in
            AuthenticationSheet(controller: accountController, mode: mode)
        }
        .onChange(of: accountController.account?.uid) { _, accountUID in
            if accountUID != nil {
                authenticationMode = nil
            }
        }
        .task {
            await controller.refreshAvailability()
        }
    }

    private func presentRestrictedProviderAccess() {
        if accountController.account == nil {
            accountController.errorMessage = nil
            authenticationMode = .signIn
        } else {
            guard !isOpeningRestrictedProviderAccess,
                  accountController.openingWebDestination != .pricing else { return }
            isOpeningRestrictedProviderAccess = true
            Task {
                await accountController.openPricingOnWeb()
                isOpeningRestrictedProviderAccess = false
            }
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
