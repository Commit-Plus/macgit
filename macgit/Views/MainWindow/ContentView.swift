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

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController

    @State private var repositoryURL: URL?
    @State private var showingRepoPickerSheet = false
    @State private var showingCloneSheet = false
    @State private var showingKeepCurrentAlert = false
    @State private var pendingAction: FileMenuAction?

    var body: some View {
        Group {
            if let url = repositoryURL {
                MainWindowView(
                    repositoryURL: url,
                    providerAccountController: providerAccountController,
                    onOpenConnections: accountController.presentConnections
                )
            } else {
                RepoPickerView(
                    showCloneSheetInitially: false,
                    onRepositoryOpened: { url in
                        repositoryURL = url
                    }
                )
            }
        }
        .sheet(isPresented: $showingRepoPickerSheet) {
            RepoPickerView(
                showCloneSheetInitially: false,
                onRepositoryOpened: { url in
                    showingRepoPickerSheet = false
                    repositoryURL = url
                }
            )
            .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showingCloneSheet) {
            CloneSheetView(onClone: { url in
                showingCloneSheet = false
                repositoryURL = url
            })
            .frame(minWidth: 480)
        }
        .sheet(item: $accountController.presentedSheet) { sheet in
            switch sheet {
            case .authentication(let mode):
                AuthenticationSheet(controller: accountController, mode: mode)
            case .manageAccount:
                ManageAccountSheet(
                    controller: accountController
                )
            case .connections:
                ConnectionsSheet(
                    accountController: accountController,
                    providerAccountController: providerAccountController
                )
            case .settingsConflict:
                SettingsSyncConflictSheet(controller: accountController)
            }
        }
        .alert("Current Repository is Open", isPresented: $showingKeepCurrentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Close Current", role: .destructive) {
                closeCurrentAndPerformPending()
            }
            Button("Keep Open") {
                openNewWindowForPending()
            }
        } message: {
            Text("Do you want to keep the current repository open?")
        }
        .onChange(of: appState.fileMenuAction) { _, newValue in
            guard let action = newValue else { return }
            appState.fileMenuAction = nil

            switch action {
            case .new:
                if repositoryURL == nil {
                    showingCloneSheet = true
                } else {
                    appState.openWindowWithCloneSheet = true
                    openWindow(id: "main")
                }
            case .open, .openRecent:
                if repositoryURL != nil {
                    pendingAction = action
                    showingKeepCurrentAlert = true
                } else {
                    performAction(action, inNewWindow: false)
                }
            case .close:
                repositoryURL = nil
            }
        }
        .onChange(of: repositoryURL) { _, newValue in
            appState.hasOpenRepository = newValue != nil
        }
        .onAppear {
            appState.hasOpenRepository = repositoryURL != nil
            handlePendingWindowFlags()
        }
        .task(id: accountController.account?.uid) {
            await providerAccountController.updateMacgitAccount(accountController.account)
        }
        .overlay(
            WindowCloseButtonModifier(isVisible: repositoryURL == nil)
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AccountToolbarMenu(controller: accountController)
            }
        }
    }

    private func handlePendingWindowFlags() {
        if let url = appState.newWindowRepoURL {
            repositoryURL = url
            appState.newWindowRepoURL = nil
        }
        if appState.openWindowWithCloneSheet {
            appState.openWindowWithCloneSheet = false
            showingCloneSheet = true
        }
    }

    private func performAction(_ action: FileMenuAction, inNewWindow: Bool) {
        switch action {
        case .new:
            if inNewWindow {
                appState.openWindowWithCloneSheet = true
                openWindow(id: "main")
            } else {
                showingCloneSheet = true
            }
        case .open:
            if inNewWindow {
                openWindow(id: "main")
            } else {
                showingRepoPickerSheet = true
            }
        case .openRecent(let url):
            if inNewWindow {
                appState.newWindowRepoURL = url
                openWindow(id: "main")
            } else {
                repositoryURL = url
            }
        case .close:
            repositoryURL = nil
        }
    }

    private func closeCurrentAndPerformPending() {
        repositoryURL = nil
        if let action = pendingAction {
            performAction(action, inNewWindow: false)
            pendingAction = nil
        }
    }

    private func openNewWindowForPending() {
        if let action = pendingAction {
            performAction(action, inNewWindow: true)
            pendingAction = nil
        }
    }
}

struct WindowCloseButtonModifier: NSViewRepresentable {
    let isVisible: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.update(window: view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(window: nsView.window)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: isVisible)
    }
    
    class Coordinator {
        var isVisible: Bool
        
        init(isVisible: Bool) {
            self.isVisible = isVisible
        }
        
        func update(window: NSWindow?) {
            guard let window = window else { return }
            if let closeButton = window.standardWindowButton(.closeButton) {
                closeButton.isHidden = !isVisible
                closeButton.isEnabled = isVisible
            }
        }
    }
}
