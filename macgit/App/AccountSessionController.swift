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

import Combine
import Foundation

@MainActor
final class AccountSessionController: ObservableObject {
    @Published private(set) var state: AccountSessionState
    @Published var presentedSheet: AccountSheet?
    @Published var errorMessage: String?
    @Published private(set) var passwordResetMessage: String?
    @Published private(set) var pendingLinkEmail: String?
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var requiresRecentAuthentication = false
    @Published private(set) var entitlement: AccountEntitlement = .free
    @Published private(set) var entitlementError: String?
    @Published private(set) var settingsSyncStatus: SettingsSyncStatus = .off

    let cloudFeaturesAvailable: Bool

    private let auth: AccountAuthenticating
    private let entitlementProvider: EntitlementProviding?
    private let appState: AppState
    private let settingsSyncService: SettingsSyncService?
    private var entitlementObservation: ObservationToken?
    private var settingsEligibilityTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var account: AccountSnapshot? {
        guard case .authenticated(let account) = state else { return nil }
        return account
    }

    var isLoading: Bool {
        state == .loading
    }

    var settingsSyncEnabled: Bool {
        appState.syncEnabled
    }

    var pendingCloudSettings: AppSettingsSnapshot? {
        guard case .needsInitialChoice(let snapshot) = settingsSyncStatus else { return nil }
        return snapshot
    }

    var localSettingsSnapshot: AppSettingsSnapshot {
        appState.snapshot
    }

    var settingsSyncStatusText: String {
        switch settingsSyncStatus {
        case .off: "Off"
        case .locked: "Sign In Required"
        case .starting: "Starting..."
        case .needsInitialChoice: "Choose Settings"
        case .syncing: "Syncing"
        case .paused: "Paused"
        case .failed: "Error"
        }
    }

    var settingsSyncDisplayText: String {
        guard account != nil else { return "Sign In Required" }
        guard settingsSyncEnabled else { return "Off" }

        switch settingsSyncStatus {
        case .off:
            return "Starting..."
        default:
            return settingsSyncStatusText
        }
    }

    var settingsSyncError: String? {
        guard case .failed(let message) = settingsSyncStatus else { return nil }
        return message
    }

    init(
        auth: AccountAuthenticating,
        bootstrapStatus: FirebaseBootstrapStatus,
        entitlementProvider: EntitlementProviding? = nil,
        appState: AppState? = nil,
        settingsStore: CloudSettingsStore? = nil
    ) {
        self.auth = auth
        self.entitlementProvider = entitlementProvider
        let resolvedAppState = appState ?? AppState.shared
        self.appState = resolvedAppState
        if let settingsStore {
            settingsSyncService = SettingsSyncService(
                store: settingsStore,
                currentSnapshot: { resolvedAppState.snapshot },
                applySnapshot: { resolvedAppState.apply($0) },
                setSyncEnabled: { resolvedAppState.syncEnabled = $0 }
            )
        } else {
            settingsSyncService = nil
        }
        cloudFeaturesAvailable = bootstrapStatus == .configured
        let initialAccount = cloudFeaturesAvailable ? auth.currentAccount : nil
        if let initialAccount {
            state = .authenticated(initialAccount)
        } else {
            state = .guest
        }

        bindSettingsSync()
        if let initialAccount {
            startEntitlementObservation(for: initialAccount.uid)
        }
        scheduleSettingsSyncEligibilityUpdate()
    }

    func presentAuthentication(_ mode: AuthenticationMode) {
        errorMessage = nil
        passwordResetMessage = nil
        presentedSheet = .authentication(mode)
    }

    func presentManageAccount() {
        presentedSheet = .manageAccount
    }

    func presentConnections() {
        presentedSheet = .connections
    }

    func signIn(email: String, password: String) async {
        await authenticate { [auth] in
            try await auth.signIn(email: email, password: password)
        }
    }

    func createAccount(email: String, password: String) async {
        await authenticate { [auth] in
            try await auth.createAccount(email: email, password: password)
        }
    }

    func signInWithGoogle() async {
        await authenticate { [auth] in
            try await auth.signInWithGoogle()
        }
    }

    func completePendingLink(password: String) async {
        guard let email = pendingLinkEmail else { return }
        await authenticate { [auth] in
            try await auth.completePendingLink(email: email, password: password)
        }
    }

    func sendPasswordReset(email: String) async {
        guard cloudFeaturesAvailable else {
            errorMessage = AccountAuthError.cloudNotConfigured.localizedDescription
            return
        }

        let previousState = state
        state = .loading
        errorMessage = nil
        passwordResetMessage = nil
        do {
            try await auth.sendPasswordReset(email: email)
            state = previousState
            passwordResetMessage = "Password reset email sent."
        } catch {
            state = previousState
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() {
        do {
            try auth.signOut()
            stopEntitlementObservation()
            state = .guest
            presentedSheet = nil
            errorMessage = nil
            pendingLinkEmail = nil
            scheduleSettingsSyncEligibilityUpdate()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func deleteAccount() async {
        guard account != nil else { return }
        isDeletingAccount = true
        errorMessage = nil
        requiresRecentAuthentication = false
        defer { isDeletingAccount = false }

        do {
            try await auth.deleteAccount()
            stopEntitlementObservation()
            state = .guest
            presentedSheet = nil
            pendingLinkEmail = nil
            scheduleSettingsSyncEligibilityUpdate()
        } catch let error as AccountAuthError where error == .requiresRecentAuthentication {
            requiresRecentAuthentication = true
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func presentReauthentication() {
        presentAuthentication(.signIn)
    }

    private func authenticate(
        operation: () async throws -> AccountSnapshot
    ) async {
        guard cloudFeaturesAvailable else {
            state = .guest
            errorMessage = AccountAuthError.cloudNotConfigured.localizedDescription
            return
        }

        let previousState = state
        state = .loading
        errorMessage = nil
        passwordResetMessage = nil
        do {
            let account = try await operation()
            state = .authenticated(account)
            startEntitlementObservation(for: account.uid)
            requiresRecentAuthentication = false
            pendingLinkEmail = nil
            presentedSheet = nil
            scheduleSettingsSyncEligibilityUpdate()
        } catch let error as AccountAuthError {
            state = previousState == .loading ? .guest : previousState
            if case .needsExistingMethod(let email, _) = error {
                pendingLinkEmail = email
            }
            errorMessage = error.localizedDescription
        } catch {
            state = previousState == .loading ? .guest : previousState
            errorMessage = Self.message(for: error)
        }
    }

    private func startEntitlementObservation(for uid: String) {
        stopEntitlementObservation()
        guard let entitlementProvider else { return }
        entitlementObservation = entitlementProvider.observe(
            uid: uid,
            onChange: { [weak self] entitlement in
                guard self?.account?.uid == uid else { return }
                self?.entitlement = entitlement
                self?.entitlementError = nil
                self?.scheduleSettingsSyncEligibilityUpdate()
            },
            onError: { [weak self] message in
                guard self?.account?.uid == uid else { return }
                self?.entitlement = .free
                self?.entitlementError = message
                self?.scheduleSettingsSyncEligibilityUpdate()
            }
        )
    }

    private func stopEntitlementObservation() {
        entitlementObservation?.cancel()
        entitlementObservation = nil
        entitlement = .free
        entitlementError = nil
        scheduleSettingsSyncEligibilityUpdate()
    }

    func setSettingsSyncEnabled(_ enabled: Bool) {
        guard account != nil else { return }
        appState.syncEnabled = enabled
    }

    func resolveInitialSettingsChoice(_ choice: InitialSettingsChoice) async {
        await settingsSyncService?.resolveInitialChoice(choice)
    }

    func synchronizeSettingsNow() async {
        guard let settingsSyncService else {
            settingsSyncStatus = account == nil ? .off : .locked
            return
        }
        await settingsSyncService.updateEligibility(
            uid: account?.uid,
            enabled: appState.syncEnabled
        )
    }

    private func bindSettingsSync() {
        guard let settingsSyncService else { return }

        settingsSyncService.$status
            .sink { [weak self] status in
                guard let self else { return }
                settingsSyncStatus = status
                if case .needsInitialChoice = status {
                    presentSettingsConflictSheet()
                } else if presentedSheet == .settingsConflict {
                    presentedSheet = nil
                }
            }
            .store(in: &cancellables)

        appState.settingsSnapshotPublisher
            .dropFirst()
            .sink { [weak self] snapshot in
                guard let self else { return }
                settingsSyncService.localSettingsDidChange(snapshot)
            }
            .store(in: &cancellables)

        appState.$syncEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.scheduleSettingsSyncEligibilityUpdate(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func scheduleSettingsSyncEligibilityUpdate(enabled enabledOverride: Bool? = nil) {
        settingsEligibilityTask?.cancel()
        guard let settingsSyncService else {
            settingsSyncStatus = account == nil ? .off : .locked
            return
        }
        let uid = account?.uid
        let enabled = enabledOverride ?? appState.syncEnabled
        settingsEligibilityTask = Task {
            guard !Task.isCancelled else { return }
            await settingsSyncService.updateEligibility(
                uid: uid,
                enabled: enabled
            )
        }
    }

    private func presentSettingsConflictSheet() {
        guard presentedSheet != .settingsConflict else { return }
        guard presentedSheet != nil else {
            presentedSheet = .settingsConflict
            return
        }

        presentedSheet = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard case .needsInitialChoice = settingsSyncStatus else { return }
            presentedSheet = .settingsConflict
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
