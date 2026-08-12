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

    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isRemovingKey = false

    private var isConfigured: Bool {
        controller.isAPIKeyConfigured(for: descriptor.id)
    }

    var body: some View {
        Section {
            LabeledContent("Model") {
                Text(descriptor.detail.replacing("Cloud · ", with: ""))
                    .foregroundStyle(.secondary)
            }

            SecureField(
                isConfigured ? "Enter a replacement API key" : "API key",
                text: $apiKey
            )
            .textContentType(.password)
            .onSubmit(saveAPIKey)

            HStack {
                Label(
                    isConfigured ? "Configured in Keychain" : "API key required",
                    systemImage: isConfigured ? "checkmark.circle.fill" : "key"
                )
                .foregroundStyle(isConfigured ? .primary : .secondary)

                Spacer()

                if isConfigured {
                    Button("Remove Key", role: .destructive) {
                        isRemovingKey = true
                    }
                }

                Button(isConfigured ? "Replace API Key" : "Save API Key", action: saveAPIKey)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Label(descriptor.displayName, systemImage: descriptor.systemImage)
        } footer: {
            Text("The key stays in this Mac's Keychain. When selected, bounded change context is sent directly to \(descriptor.displayName).")
        }
        .alert("Couldn’t Update API Key", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Remove \(descriptor.displayName) API Key?",
            isPresented: $isRemovingKey
        ) {
            Button("Remove API Key", role: .destructive, action: removeAPIKey)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Commit+ will no longer be able to use \(descriptor.displayName) until a new key is saved.")
        }
    }

    private func saveAPIKey() {
        do {
            try controller.saveAPIKey(apiKey, for: descriptor.id)
            apiKey = ""
            Task { await controller.refreshAvailability() }
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func removeAPIKey() {
        do {
            try controller.removeAPIKey(for: descriptor.id)
            apiKey = ""
            Task { await controller.refreshAvailability() }
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}
