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

final class GitProviderOAuthTests: XCTestCase {
    func testPKCEVerifierUsesAllowedCharacters() {
        let verifier = GitProviderPKCE.generateVerifier()
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        )

        XCTAssertTrue((43...128).contains(verifier.count))
        XCTAssertNil(verifier.unicodeScalars.first { !allowedCharacters.contains($0) })
    }

    func testPKCEChallengeIsBase64URLWithoutPadding() {
        let challenge = GitProviderPKCE.challenge(
            for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testCallbackRejectsMismatchedState() throws {
        let session = try makeSession(state: "expected-state")
        let callbackURL = try XCTUnwrap(
            URL(string: "macgit://git-provider/oauth/callback?code=oauth-code&state=wrong-state")
        )

        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(callbackURL, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .stateMismatch)
        }
    }

    func testCallbackExtractsAuthorizationCode() throws {
        let session = try makeSession(state: "expected-state")
        let callbackURL = try XCTUnwrap(
            URL(string: "macgit://git-provider/oauth/callback?code=oauth-code&state=expected-state")
        )

        let callback = try GitProviderOAuthCallback.parse(callbackURL, for: session)

        XCTAssertEqual(callback, GitProviderOAuthCallback(code: "oauth-code", state: "expected-state"))
    }

    private func makeSession(state: String) throws -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .github,
            host: .githubDotCom,
            state: state,
            codeVerifier: "test-verifier",
            redirectURI: try XCTUnwrap(URL(string: "macgit://git-provider/oauth/callback"))
        )
    }
}
