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

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var featureAccessController: FeatureAccessController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    @ObservedObject var appUpdateController: AppUpdateController
    @Binding private var selectedSection: AppSettingsSection
    @State private var aiProviderKeyDrafts: [AIProviderAPIKeyDraft]
    @State private var saveErrorMessage: String?
    @State private var isShowingSaveError = false

    init(
        appState: AppState,
        accountController: AccountSessionController,
        featureAccessController: FeatureAccessController,
        providerAccountController: GitProviderAccountController,
        aiProviderController: AIProviderController,
        appUpdateController: AppUpdateController,
        selectedSection: Binding<AppSettingsSection>
    ) {
        self.appState = appState
        self.accountController = accountController
        self.featureAccessController = featureAccessController
        self.providerAccountController = providerAccountController
        self.aiProviderController = aiProviderController
        self.appUpdateController = appUpdateController
        _selectedSection = selectedSection
        _aiProviderKeyDrafts = State(initialValue: aiProviderController.descriptors
            .filter { $0.dataProcessing == .cloud }
            .map { AIProviderAPIKeyDraft(id: $0.id) })
    }

    var body: some View {
        NavigationSplitView {
            List(AppSettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                AppSettingsDetailView(
                    section: selectedSection,
                    appState: appState,
                    accountController: accountController,
                    providerAccountController: providerAccountController,
                    aiProviderController: aiProviderController,
                    appUpdateController: appUpdateController,
                    restrictedAIProviderAccess: restrictedAIProviderAccess,
                    aiProviderKeyDrafts: $aiProviderKeyDrafts
                )

                Divider()

                HStack {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Done", action: saveChangesAndDismiss)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 460, idealHeight: 580, maxHeight: 660)
        .navigationTitle("Settings")
        .alert("Couldn’t Save Settings", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func saveChangesAndDismiss() {
        do {
            try aiProviderController.applyAPIKeyChanges(
                aiProviderKeyDrafts,
                restrictedProviderAccess: restrictedAIProviderAccess
            )
            Task { await aiProviderController.refreshAvailability() }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isShowingSaveError = true
        }
    }

    private var restrictedAIProviderAccess: FeatureAccessDecision {
        featureAccessController.decision(
            for: .aiBringYourOwnKey,
            entitlement: accountController.entitlement
        )
    }
}
