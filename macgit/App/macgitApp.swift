//
//  macgitApp.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

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
import GoogleSignIn
import SwiftUI

@main
struct macgitApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var appUpdateController = AppUpdateController(updater: SparkleAppUpdater())
    @StateObject private var accountController: AccountSessionController

    init() {
        let firebaseStatus = FirebaseBootstrap.configure()
        _accountController = StateObject(
            wrappedValue: AccountSessionController(
                auth: FirebaseAuthService(),
                bootstrapStatus: firebaseStatus,
                entitlementProvider: firebaseStatus == .configured
                    ? FirestoreEntitlementStore()
                    : nil
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(accountController: accountController)
                .environmentObject(appState)
                .environmentObject(appUpdateController)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
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
