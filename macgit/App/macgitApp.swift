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

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
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

            CommandMenu("Actions") {
                @FocusedBinding(\.toolbarAction) var action: ToolbarAction?

                Button("Commit...") {
                    action = .commit
                }
                .disabled(action == nil)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Pull") {
                    action = .pull
                }
                .disabled(action == nil)
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Push") {
                    action = .push
                }
                .disabled(action == nil)
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Fetch") {
                    action = .fetch
                }
                .disabled(action == nil)
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Branch...") {
                    action = .branch
                }
                .disabled(action == nil)
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Merge...") {
                    action = .merge
                }
                .disabled(action == nil)
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Stash...") {
                    action = .stash
                }
                .disabled(action == nil)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
