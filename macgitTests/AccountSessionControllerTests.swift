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

import XCTest
@testable import macgit

@MainActor
final class AccountSessionControllerTests: XCTestCase {
    func testGuestRemainsAvailableWhenFirebaseIsMissing() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil),
            bootstrapStatus: .missingConfiguration
        )

        XCTAssertEqual(controller.state, .guest)
        XCTAssertFalse(controller.cloudFeaturesAvailable)
    }

    func testEmailSignInPublishesAccount() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertNil(controller.errorMessage)
    }

    func testSignInFailureReturnsToGuestAndPublishesMessage() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(error: .invalidCredentials),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "wrong")

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.errorMessage, "The email or password is incorrect.")
    }

    func testSignOutReturnsToGuest() {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        controller.signOut()

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(auth.signOutCallCount, 1)
    }

    func testPresentConnectionsShowsConnectionsSheet() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil),
            bootstrapStatus: .configured
        )

        controller.presentConnections()

        XCTAssertEqual(controller.presentedSheet, .connections)
    }

    func testSuccessfulAccountDeletionReturnsToGuest() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(auth.deleteAccountCallCount, 1)
        XCTAssertEqual(controller.state, .guest)
    }

    func testFailedAccountDeletionKeepsAuthenticatedState() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .networkUnavailable)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(controller.errorMessage, "Connect to the internet and try again.")
    }

    func testRecentAuthenticationFailureKeepsAccountAndOffersRecovery() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .requiresRecentAuthentication)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertTrue(controller.requiresRecentAuthentication)
    }

    func testOpenAccountOnWebUsesAuthenticatedProfileURL() async throws {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let profileURL = try XCTUnwrap(
            URL(string: "http://localhost:3000/session?next=/profile#token=test-token")
        )
        let provider = FakeWebAccountSessionProvider(
            urls: [.profile: profileURL]
        )
        var openedURLs: [URL] = []
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: provider,
            openWebURL: { url in
                openedURLs.append(url)
                return true
            }
        )

        await controller.openAccountOnWeb()

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(openedURLs, [profileURL])
        XCTAssertFalse(controller.isOpeningAccountOnWeb)
        XCTAssertNil(controller.openingWebDestination)
        XCTAssertNil(controller.errorMessage)
    }

    func testOpenPricingOnWebUsesAuthenticatedPricingURL() async throws {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let pricingURL = try XCTUnwrap(
            URL(string: "http://localhost:3000/session?next=/pricing#token=test-token")
        )
        let provider = FakeWebAccountSessionProvider(
            urls: [.pricing: pricingURL]
        )
        var openedURLs: [URL] = []
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: provider,
            openWebURL: { url in
                openedURLs.append(url)
                return true
            }
        )

        await controller.openPricingOnWeb()

        XCTAssertEqual(provider.requestedDestinations, [.pricing])
        XCTAssertEqual(openedURLs, [pricingURL])
        XCTAssertFalse(controller.isOpeningAccountOnWeb)
        XCTAssertNil(controller.openingWebDestination)
        XCTAssertNil(controller.errorMessage)
    }

    func testDeviceBoundSignInPublishesAccountOnlyAfterActivation() async {
        let account = Self.account
        let metadata = Self.metadata
        let device = Self.device(metadata: metadata)
        let auth = FakeAccountAuth(
            signInResult: account,
            customTokenResult: account,
            deviceClaims: AccountDeviceSessionClaims(deviceID: metadata.deviceID, version: 1)
        )
        let access = FakeDeviceAccessProvider(
            claimResult: .active(limit: 1, device: device, devices: [device], customToken: "bound-token")
        )
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(access.claimedMetadata, [metadata])
        XCTAssertEqual(auth.customTokens, ["bound-token"])
        XCTAssertEqual(controller.deviceLimit, 1)
    }

    func testDeviceLimitDoesNotExposeAuthenticatedAccount() async {
        let account = Self.account
        let metadata = Self.metadata
        let existing = Self.device(id: "11111111-1111-4111-8111-111111111111")
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: FakeDeviceAccessProvider(
                claimResult: .limitReached(limit: 1, devices: [existing])
            ),
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertNil(controller.account)
        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.presentedSheet, .deviceLimit)
        XCTAssertEqual(controller.deviceAccessState, .limitReached(limit: 1, devices: [existing]))
    }

    func testReplacingDeviceCompletesActivation() async {
        let account = Self.account
        let metadata = Self.metadata
        let existing = Self.device(id: "11111111-1111-4111-8111-111111111111")
        let replacement = Self.device(metadata: metadata)
        let auth = FakeAccountAuth(
            signInResult: account,
            customTokenResult: account,
            deviceClaims: AccountDeviceSessionClaims(deviceID: metadata.deviceID, version: 1)
        )
        let access = FakeDeviceAccessProvider(
            claimResult: .limitReached(limit: 1, devices: [existing]),
            replaceResult: .active(
                limit: 1,
                device: replacement,
                devices: [replacement],
                customToken: "replacement-token"
            )
        )
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        await controller.replaceDevice(existing)

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(access.replacedDeviceIDs, [existing.id])
        XCTAssertNil(controller.presentedSheet)
    }

    func testRemoteRevocationStopsCloudSessionAndPreservesGuestUse() async {
        let account = Self.account
        let metadata = Self.metadata
        let device = Self.device(metadata: metadata)
        let auth = FakeAccountAuth(
            signInResult: account,
            customTokenResult: account,
            deviceClaims: AccountDeviceSessionClaims(deviceID: metadata.deviceID, version: 1)
        )
        let access = FakeDeviceAccessProvider(
            claimResult: .active(limit: 1, device: device, devices: [device], customToken: "token")
        )
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )
        await controller.signIn(email: "a@example.com", password: "secret12")

        access.emit(.revoked(.replaced))

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.deviceAccessState, .revoked(.replaced))
        XCTAssertEqual(auth.signOutCallCount, 1)
        XCTAssertEqual(controller.errorMessage, AccountDeviceRevocationReason.replaced.message)
    }

    private static let account = AccountSnapshot(
        uid: "u-device",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )

    private static let metadata = AccountDeviceMetadata(
        deviceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        modelFamily: "MacBook Pro",
        osVersion: "15.6.0",
        appVersion: "1.0"
    )

    private static func device(
        id: String = metadata.deviceID,
        metadata: AccountDeviceMetadata? = nil
    ) -> AccountDevice {
        let metadata = metadata ?? AccountDeviceMetadata(
            deviceID: id,
            modelFamily: "MacBook Air",
            osVersion: "15.6.0",
            appVersion: "1.0"
        )
        return AccountDevice(
            id: metadata.deviceID,
            modelFamily: metadata.modelFamily,
            osVersion: metadata.osVersion,
            appVersion: metadata.appVersion,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: Date(timeIntervalSince1970: 2),
            revokedAt: nil,
            revokedReason: nil
        )
    }
}

@MainActor
private final class FakeWebAccountSessionProvider: WebAccountSessionProviding {
    let urls: [WebAccountDestination: URL]
    private(set) var requestedDestinations: [WebAccountDestination] = []

    var requestCount: Int {
        requestedDestinations.count
    }

    init(urls: [WebAccountDestination: URL]) {
        self.urls = urls
    }

    func signInURL(for destination: WebAccountDestination) async throws -> URL {
        requestedDestinations.append(destination)
        guard let url = urls[destination] else {
            throw WebAccountSessionError.invalidServerResponse
        }
        return url
    }
}

private final class FakeAccountAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?
    var signOutCallCount = 0
    var deleteAccountCallCount = 0

    private let signInResult: AccountSnapshot?
    private let customTokenResult: AccountSnapshot?
    private let deviceClaims: AccountDeviceSessionClaims?
    private let error: AccountAuthError?
    private(set) var customTokens: [String] = []

    init(
        current: AccountSnapshot? = nil,
        signInResult: AccountSnapshot? = nil,
        customTokenResult: AccountSnapshot? = nil,
        deviceClaims: AccountDeviceSessionClaims? = nil,
        error: AccountAuthError? = nil
    ) {
        currentAccount = current
        self.signInResult = signInResult
        self.customTokenResult = customTokenResult
        self.deviceClaims = deviceClaims
        self.error = error
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        if let error { throw error }
        return try XCTUnwrap(signInResult)
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func signInWithGoogle() async throws -> AccountSnapshot {
        try await signIn(email: "", password: "")
    }

    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {
        if let error { throw error }
    }

    func signIn(withCustomToken token: String) async throws -> AccountSnapshot {
        if let error { throw error }
        customTokens.append(token)
        let account = try XCTUnwrap(customTokenResult ?? signInResult)
        currentAccount = account
        return account
    }

    func deviceSessionClaims(forceRefresh: Bool) async throws -> AccountDeviceSessionClaims? {
        if let error { throw error }
        return deviceClaims
    }

    func deleteAccount() async throws {
        if let error { throw error }
        deleteAccountCallCount += 1
        currentAccount = nil
    }

    func signOut() throws {
        if let error { throw error }
        signOutCallCount += 1
        currentAccount = nil
    }
}

@MainActor
private struct FakeDeviceIdentity: DeviceIdentityProviding {
    let metadata: AccountDeviceMetadata

    func currentDevice() throws -> AccountDeviceMetadata { metadata }
}

@MainActor
private final class FakeDeviceAccessProvider: DeviceAccessProviding {
    let claimResult: DeviceActivationResult
    let replaceResult: DeviceActivationResult?
    private(set) var claimedMetadata: [AccountDeviceMetadata] = []
    private(set) var replacedDeviceIDs: [String] = []
    private var onChange: (@MainActor (AccountDeviceObservationState) -> Void)?

    init(claimResult: DeviceActivationResult, replaceResult: DeviceActivationResult? = nil) {
        self.claimResult = claimResult
        self.replaceResult = replaceResult
    }

    func claim(_ metadata: AccountDeviceMetadata) async throws -> DeviceActivationResult {
        claimedMetadata.append(metadata)
        return claimResult
    }

    func replace(
        replacing deviceID: String,
        with metadata: AccountDeviceMetadata
    ) async throws -> DeviceActivationResult {
        replacedDeviceIDs.append(deviceID)
        return try XCTUnwrap(replaceResult)
    }

    func releaseCurrentDevice() async throws {}
    func revoke(deviceID: String) async throws {}
    func heartbeat(_ metadata: AccountDeviceMetadata) async throws {}

    func listDevices() async throws -> AccountDeviceList {
        switch replaceResult ?? claimResult {
        case .active(let limit, _, let devices, _), .limitReached(let limit, let devices):
            return AccountDeviceList(limit: limit, devices: devices)
        }
    }

    func observeCurrentDevice(
        uid: String,
        deviceID: String,
        onChange: @escaping @MainActor (AccountDeviceObservationState) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> ObservationToken {
        self.onChange = onChange
        return TestDeviceObservationToken()
    }

    func emit(_ state: AccountDeviceObservationState) {
        onChange?(state)
    }
}

private final class TestDeviceObservationToken: ObservationToken {
    func cancel() {}
}

@MainActor
private final class FakeDeviceSessionCache: AccountDeviceSessionCaching {
    private var sessions: [String: CachedAccountDeviceSession] = [:]

    func session(for uid: String) -> CachedAccountDeviceSession? { sessions[uid] }
    func save(_ session: CachedAccountDeviceSession) { sessions[session.uid] = session }
    func removeSession(for uid: String) { sessions.removeValue(forKey: uid) }
}
