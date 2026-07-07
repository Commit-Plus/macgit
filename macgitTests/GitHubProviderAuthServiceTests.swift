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

final class GitHubProviderAuthServiceTests: XCTestCase {
    func testDeviceAuthorizationRequestsUserCodeWithClientIDAndScopes() async throws {
        let client = StubGitProviderHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"device_code":"device-code","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            )
        ])
        let service = makeService(httpClient: client)

        let authorization = try await service.requestDeviceAuthorization()

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(body.contains("client_id=github-client-id"))
        XCTAssertTrue(body.contains("scope=repo%20read:user"))
        XCTAssertEqual(authorization.deviceCode, "device-code")
        XCTAssertEqual(authorization.userCode, "ABCD-EFGH")
        XCTAssertEqual(authorization.verificationURI, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(authorization.expiresIn, 900)
        XCTAssertEqual(authorization.interval, 5)
    }

    func testDeviceTokenPollSendsDeviceCodeWithoutClientSecret() async throws {
        let client = StubGitProviderHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"access_token":"secret-token","token_type":"bearer","scope":"repo read:user"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let token = try await service.pollDeviceAuthorization(makeDeviceAuthorization())

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/oauth/access_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(body.contains("client_id=github-client-id"))
        XCTAssertTrue(body.contains("device_code=device-code"))
        XCTAssertTrue(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(token.accessToken, "secret-token")
        XCTAssertEqual(token.tokenType, "bearer")
    }

    func testDevicePollPendingMapsToAuthorizationPending() async throws {
        let client = StubGitProviderHTTPClient(responses: [
            .json(statusCode: 200, body: #"{"error":"authorization_pending"}"#)
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.pollDeviceAuthorization(makeDeviceAuthorization())
            XCTFail("Expected pending device authorization to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .authorizationPending)
        }
    }

    func testProfileResponseCreatesProviderAccountMetadata() async throws {
        let client = StubGitProviderHTTPClient(responses: [
            .json(
                statusCode: 200,
                headers: ["X-OAuth-Scopes": "repo, read:user"],
                body: #"{"id":583231,"login":"octocat","name":"The Octocat","avatar_url":"https://avatars.githubusercontent.com/u/583231"}"#
            )
        ])
        let service = makeService(httpClient: client)
        let token = GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )

        let account = try await service.fetchAccount(
            token: token,
            macgitUID: "macgit-user-1",
            host: .githubDotCom
        )

        XCTAssertEqual(account.id, "macgit-user-1:github:github.com:583231")
        XCTAssertEqual(account.provider, .github)
        XCTAssertEqual(account.hostURL, URL(string: "https://github.com"))
        XCTAssertEqual(account.providerUserID, "583231")
        XCTAssertEqual(account.username, "octocat")
        XCTAssertEqual(account.displayName, "The Octocat")
        XCTAssertEqual(account.scopes, ["repo", "read:user"])
        XCTAssertEqual(account.permissions, [:])
        XCTAssertEqual(account.tokenStatus, .valid)
        XCTAssertEqual(account.connectedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(account.lastValidatedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(client.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testHTTPUnauthorizedMapsToReauthorizationRequired() async throws {
        let client = StubGitProviderHTTPClient(responses: [.json(statusCode: 401, body: #"{"message":"Bad credentials"}"#)])
        let service = makeService(httpClient: client)
        let token = GitProviderToken(
            accessToken: "expired-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )

        do {
            _ = try await service.fetchAccount(
                token: token,
                macgitUID: "macgit-user-1",
                host: .githubDotCom
            )
            XCTFail("Expected fetchAccount to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .reauthorizationRequired)
        }
    }

    private func makeService(httpClient: GitProviderHTTPClient) -> GitHubProviderAuthService {
        GitHubProviderAuthService(
            configuration: GitHubProviderAuthConfiguration(
                clientID: "github-client-id",
                scopes: ["repo", "read:user"]
            ),
            httpClient: httpClient,
            deviceEndpoint: URL(string: "https://github.com/login/device/code")!,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func makeDeviceAuthorization() -> GitProviderDeviceAuthorization {
        GitProviderDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "ABCD-EFGH",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 900,
            interval: 5
        )
    }
}

private final class StubGitProviderHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var headers: [String: String]
        var data: Data

        static func json(statusCode: Int, headers: [String: String] = [:], body: String) -> Response {
            Response(statusCode: statusCode, headers: headers, data: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response] = []) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )
        )
        return (response.data, httpResponse)
    }
}
