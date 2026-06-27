//
//  macgitApp.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

@main
struct macgitApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var appUpdateController = AppUpdateController(updater: SparkleAppUpdater())

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appUpdateController)
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
        }
    }
}
