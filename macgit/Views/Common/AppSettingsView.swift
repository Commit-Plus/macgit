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
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var appUpdateController: AppUpdateController
    @State private var selectedSection: AppSettingsSection = .general

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
                    appUpdateController: appUpdateController
                )

                Divider()

                HStack {
                    Spacer()
                    Button("Done", action: dismiss.callAsFunction)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 460, idealHeight: 580, maxHeight: 660)
        .navigationTitle("Settings")
    }
}
