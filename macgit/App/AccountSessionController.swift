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
    @Published var entitlement: AccountEntitlement = .free

    let cloudFeaturesAvailable: Bool

    private let auth: AccountAuthenticating

    var account: AccountSnapshot? {
        guard case .authenticated(let account) = state else { return nil }
        return account
    }

    var isLoading: Bool {
        state == .loading
    }

    init(auth: AccountAuthenticating, bootstrapStatus: FirebaseBootstrapStatus) {
        self.auth = auth
        cloudFeaturesAvailable = bootstrapStatus == .configured
        if let account = auth.currentAccount, cloudFeaturesAvailable {
            state = .authenticated(account)
        } else {
            state = .guest
        }
    }

    func presentAuthentication(_ mode: AuthenticationMode) {
        errorMessage = nil
        passwordResetMessage = nil
        presentedSheet = .authentication(mode)
    }

    func presentManageAccount() {
        presentedSheet = .manageAccount
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
            state = .guest
            entitlement = .free
            presentedSheet = nil
            errorMessage = nil
            pendingLinkEmail = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
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
            pendingLinkEmail = nil
            presentedSheet = nil
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

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
