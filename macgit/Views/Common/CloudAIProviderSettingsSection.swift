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

struct CloudAIProviderSettingsSection: View {
    let descriptor: AIProviderDescriptor
    @ObservedObject var controller: AIProviderController
    @ObservedObject var accountController: AccountSessionController
    @Binding var draft: AIProviderAPIKeyDraft
    let restrictedProviderAccess: FeatureAccessDecision
    let isOpeningAccess: Bool
    let onAccessAction: () -> Void

    @State private var isRemovingKey = false

    private var isConfigured: Bool {
        controller.isAPIKeyConfigured(for: descriptor.id)
    }

    private var hasPendingKey: Bool {
        !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canConfigureKey: Bool {
        !descriptor.requiresProToConfigureAPIKey || restrictedProviderAccess.isAllowed
    }

    var body: some View {
        Section {
            LabeledContent("Model") {
                Text(descriptor.detail.replacing("Cloud · ", with: ""))
                    .foregroundStyle(.secondary)
            }

            if (!isConfigured || draft.shouldRemove) && canConfigureKey {
                SecureField(
                    isConfigured ? "Enter a replacement API key" : "API key",
                    text: $draft.apiKey
                )
            }

            HStack {
                Label(
                    statusText,
                    systemImage: statusImage
                )
                .foregroundStyle(statusStyle)

                Spacer()

                if draft.shouldRemove {
                    Button("Keep Existing Key", action: keepExistingKey)
                } else if isConfigured {
                    Button("Remove API Key", systemImage: "trash", role: .destructive) {
                        isRemovingKey = true
                    }
                    .labelStyle(.iconOnly)
                    .help("Remove API key")
                    .confirmationDialog(
                        "Remove \(descriptor.displayName) API Key?",
                        isPresented: $isRemovingKey
                    ) {
                        Button("Remove API Key", role: .destructive, action: stageRemoval)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Enter a replacement key, or leave the field empty to remove the current key when you click Done.")
                    }
                } else if !canConfigureKey,
                          restrictedProviderAccess == .denied(.requiresPro) {
                    Button(accessActionTitle, action: onAccessAction)
                        .buttonStyle(.link)
                        .disabled(
                            isOpeningAccess
                                || accountController.openingWebDestination == .pricing
                        )
                }
            }
        } header: {
            Label(descriptor.displayName, systemImage: descriptor.systemImage)
        } footer: {
            Text(footerText)
        }
    }

    private var statusText: String {
        if hasPendingKey {
            isConfigured ? "Replacement ready" : "Ready to save"
        } else if draft.shouldRemove {
            "Will be removed"
        } else if !canConfigureKey {
            restrictedProviderAccess == .denied(.requiresPro)
                ? "Commit+ Pro required to add this provider"
                : "Provider configuration is currently unavailable"
        } else {
            isConfigured ? "Configured in Keychain" : "API key required"
        }
    }

    private var statusImage: String {
        if hasPendingKey {
            "checkmark.circle.fill"
        } else if draft.shouldRemove {
            "trash"
        } else if isConfigured {
            "checkmark.circle.fill"
        } else {
            "key"
        }
    }

    private var statusStyle: HierarchicalShapeStyle {
        !hasPendingKey && (draft.shouldRemove || !isConfigured) ? .secondary : .primary
    }

    private var footerText: String {
        if !canConfigureKey, isConfigured {
            return "This existing key remains available for AI generation. You can remove it, but adding or replacing this provider requires Commit+ Pro."
        }
        if !canConfigureKey {
            return "OpenAI and Gemini keys are available on the Free plan. Commit+ Pro unlocks Claude and additional AI providers."
        }
        return "Use the trash button before replacing a configured key. Changes are saved to this Mac's Keychain when you click Done."
    }

    private var accessActionTitle: String {
        if isOpeningAccess {
            return "Opening…"
        }
        if accountController.openingWebDestination == .pricing {
            return "Opening…"
        }
        return accountController.account == nil ? "Sign In" : "View Pro"
    }

    private func stageRemoval() {
        draft.apiKey = ""
        draft.shouldRemove = true
    }

    private func keepExistingKey() {
        draft.apiKey = ""
        draft.shouldRemove = false
    }
}
