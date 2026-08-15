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
    @EnvironmentObject private var repositoryBookmarkController: RepositoryBookmarkController
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController

    @State private var repositoryURL: URL?
    @State private var showingRepoPickerSheet = false
    @State private var showingCloneSheet = false
    @State private var showingKeepCurrentAlert = false
    @State private var pendingAction: FileMenuAction?
    @State private var shouldFitScreenWhenRepositoryOpens = false
    @State private var windowContext = RepositoryWindowContext()
    @StateObject private var operationProgress = RepositoryOperationProgress()

    init(
        request: RepositoryWindowRequest?,
        accountController: AccountSessionController,
        providerAccountController: GitProviderAccountController,
        aiProviderController: AIProviderController
    ) {
        self.accountController = accountController
        self.providerAccountController = providerAccountController
        self.aiProviderController = aiProviderController
        _repositoryURL = State(initialValue: request?.repositoryURL)
        _showingCloneSheet = State(
            initialValue: request?.initialPresentation == .cloneRepository
        )
        _shouldFitScreenWhenRepositoryOpens = State(
            initialValue: request?.shouldFitVisibleScreen == true
        )
    }

    var body: some View {
        Group {
            if let url = repositoryURL {
                MainWindowView(
                    repositoryURL: url,
                    providerAccountController: providerAccountController,
                    aiProviderController: aiProviderController,
                    onOpenConnections: accountController.presentConnections,
                    windowContext: windowContext,
                    operationProgress: operationProgress
                )
                .environmentObject(accountController)
                .background(
                    WindowInitialScreenFitModifier(
                        isEnabled: shouldFitScreenWhenRepositoryOpens
                    )
                )
            } else {
                RepoPickerView(
                    showCloneSheetInitially: false,
                    onRepositoryOpened: { url in
                        openRepository(url, inNewWindow: false)
                    }
                )
            }
        }
        .sheet(isPresented: $showingRepoPickerSheet) {
            RepoPickerView(
                showCloneSheetInitially: false,
                onRepositoryOpened: { url in
                    openRepository(url, inNewWindow: false)
                }
            )
            .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showingCloneSheet) {
            CloneSheetView(onClone: { url in
                showingCloneSheet = false
                openRepository(url, inNewWindow: false)
            })
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
            case .deviceLimit:
                DeviceLimitSheet(controller: accountController)
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
        .onReceive(NotificationCenter.default.publisher(for: .fileMenuAction)) { notification in
            guard windowContext.owns(notification),
                  let action = notification.userInfo?["action"] as? FileMenuAction else { return }
            handleFileMenuAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newRepositoryTab)) { notification in
            guard windowContext.owns(notification) else { return }
            openWindow(
                id: "main",
                value: RepositoryWindowRequest.repositoryPicker()
            )
        }
        .task(id: accountController.account?.uid) {
            await providerAccountController.updateMacgitAccount(accountController.account)
            await repositoryBookmarkController.updateAccount(accountController.account)
        }
        .background(
            RepositoryWindowReader(
                repositoryWindowContext: windowContext,
                title: repositoryURL?.lastPathComponent ?? "Commit+"
            )
        )
        .focusedSceneValue(
            \.repositoryWindowCommandState,
            RepositoryWindowCommandState(
                hasOpenRepository: repositoryURL != nil,
                hasActiveOperation: operationProgress.activeOperation != nil
            )
        )
        .windowDismissBehavior(
            operationProgress.activeOperation == nil ? .automatic : .disabled
        )
    }

    private func handleFileMenuAction(_ action: FileMenuAction) {
        switch action {
        case .cloneRepository:
            if repositoryURL == nil {
                showingCloneSheet = true
            } else {
                openWindow(
                    id: "main",
                    value: RepositoryWindowRequest.cloneRepository()
                )
            }
        case .openRepository, .openRecent:
            if repositoryURL != nil {
                pendingAction = action
                showingKeepCurrentAlert = true
            } else {
                performAction(action, inNewWindow: false)
            }
        case .closeRepository:
            repositoryURL = nil
            showingRepoPickerSheet = false
            showingCloneSheet = false
        }
    }

    private func performAction(_ action: FileMenuAction, inNewWindow: Bool) {
        switch action {
        case .cloneRepository:
            if inNewWindow {
                openWindow(
                    id: "main",
                    value: RepositoryWindowRequest.cloneRepository()
                )
            } else {
                showingCloneSheet = true
            }
        case .openRepository:
            if inNewWindow {
                openWindow(
                    id: "main",
                    value: RepositoryWindowRequest.repositoryPicker()
                )
            } else {
                showingRepoPickerSheet = true
            }
        case .openRecent(let url):
            openRepository(url, inNewWindow: inNewWindow)
        case .closeRepository:
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

    private func openRepository(_ url: URL, inNewWindow: Bool) {
        if inNewWindow {
            openWindow(
                id: "main",
                value: RepositoryWindowRequest.repository(
                    url,
                    shouldFitVisibleScreen: true
                )
            )
        } else {
            shouldFitScreenWhenRepositoryOpens = true
            showingRepoPickerSheet = false
            showingCloneSheet = false
            repositoryURL = url
        }
    }
}
