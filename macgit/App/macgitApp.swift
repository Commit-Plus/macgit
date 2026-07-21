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
import AppKit
import GoogleSignIn
import SwiftUI

@main
struct macgitApp: App {
    @StateObject private var appState: AppState
    @StateObject private var appUpdateController = AppUpdateController(updater: SparkleAppUpdater())
    @StateObject private var accountController: AccountSessionController
    @StateObject private var providerAccountController: GitProviderAccountController

    init() {
        let firebaseStatus = FirebaseBootstrap.configure()
        let appState = AppState.shared
        _appState = StateObject(wrappedValue: appState)
        _accountController = StateObject(
            wrappedValue: AccountSessionController(
                auth: FirebaseAuthService(),
                bootstrapStatus: firebaseStatus,
                entitlementProvider: firebaseStatus == .configured
                    ? FirestoreEntitlementStore()
                    : nil,
                appState: appState,
                settingsStore: firebaseStatus == .configured
                    ? FirestoreSettingsStore()
                    : nil
            )
        )
        let providerConfiguration = GitHubProviderAuthConfiguration.appConfiguration()
        let gitLabProviderConfiguration = GitLabProviderAuthConfiguration.appConfiguration()
        let providerStore: GitProviderAccountStore = firebaseStatus == .configured
            ? FirestoreGitProviderAccountStore()
            : UnavailableGitProviderAccountStore()
        _providerAccountController = StateObject(
            wrappedValue: GitProviderAccountController(
                store: providerStore,
                tokenVault: KeychainGitProviderTokenVault(),
                authService: GitHubProviderAuthService(configuration: providerConfiguration),
                configuration: providerConfiguration,
                gitLabAuthService: GitLabProviderAuthService(configuration: gitLabProviderConfiguration),
                gitLabRedirectURI: gitLabProviderConfiguration.redirectURI,
                openURL: NSWorkspace.shared.open
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(
                accountController: accountController,
                providerAccountController: providerAccountController
            )
                .environmentObject(appState)
                .environmentObject(appUpdateController)
                .onOpenURL { url in
                    Task { @MainActor in
                        if await providerAccountController.handleProviderOAuthCallback(url) {
                            return
                        }
                        _ = GIDSignIn.sharedInstance.handle(url)
                    }
                }
                .task {
                    appUpdateController.start()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdateController.checkForUpdates()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New...") {
                    appState.fileMenuAction = .new
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    appState.fileMenuAction = .open
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    let recents = Array(RecentRepositoriesStore.shared.repositories.prefix(10))
                    if recents.isEmpty {
                        Text("No Recent Repositories")
                    } else {
                        ForEach(recents) { repo in
                            Button(repo.name) {
                                appState.fileMenuAction = .openRecent(repo.url)
                            }
                        }
                    }
                }

                Divider()

                Button("Close") {
                    appState.fileMenuAction = .close
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(!appState.hasOpenRepository)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Git Action") {
                    NotificationCenter.default.post(
                        name: .gitUndoAction,
                        object: nil,
                        userInfo: ["action": GitUndoMenuAction.undo]
                    )
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo Git Action") {
                    NotificationCenter.default.post(
                        name: .gitUndoAction,
                        object: nil,
                        userInfo: ["action": GitUndoMenuAction.redo]
                    )
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Actions") {
                Button("Commit...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.commit])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Pull") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.pull])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Push") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.push])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Fetch") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.fetch])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Add Submodule...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.addSubmodule])
                }
                .disabled(!appState.hasOpenRepository)

                Button("Add/Link Subtree...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.addLinkSubtree])
                }
                .disabled(!appState.hasOpenRepository)

                Divider()

                Button("Branch...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.branch])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Merge...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.merge])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Stash...") {
                    NotificationCenter.default.post(name: .toolbarAction, object: nil, userInfo: ["action": ToolbarAction.stash])
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Search...") {
                    NotificationCenter.default.post(name: .showSearchModal, object: nil)
                }
                .disabled(!appState.hasOpenRepository)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("Accounts") {
                AccountMenuContent(controller: accountController)
            }

            CommandGroup(before: .sidebar) {
                Menu("Show Header Buttons") {
                    Toggle("Branch", isOn: $appState.showHeaderBranchButton)
                    Toggle("Merge", isOn: $appState.showHeaderMergeButton)
                    Toggle("Stash", isOn: $appState.showHeaderStashButton)
                    Toggle("Remote", isOn: $appState.showHeaderRemoteButton)
                    Toggle("Finder", isOn: $appState.showHeaderFinderButton)
                    Toggle("Terminal", isOn: $appState.showHeaderTerminalButton)
                }
            }

            CommandGroup(before: .toolbar) {
                Toggle(isOn: $appState.showToolbarButtonText) {
                    Label("Show Button Text", systemImage: "character.textbox")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle(isOn: $appState.showSubmodules) {
                    Label("Show Submodules", systemImage: "folder.badge.gearshape")
                }
                Toggle(isOn: $appState.showSubtrees) {
                    Label("Show Subtrees", systemImage: "tree")
                }
            }
        }
    }
}
