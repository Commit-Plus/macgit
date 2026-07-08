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

import Foundation

enum GitProviderAccountPresentationAction: Equatable {
    case addGitHub
    case addGitLabDotCom
    case addSelfHostedGitLab
    case reconnect
    case disconnect
}

enum GitProviderAccountsPresentationPolicy {
    static func actions(
        isSignedIn: Bool,
        account: GitProviderAccount?
    ) -> [GitProviderAccountPresentationAction] {
        guard isSignedIn else { return [] }
        guard let account else { return [.addGitHub, .addGitLabDotCom, .addSelfHostedGitLab] }

        if account.tokenStatus == .valid {
            return [.disconnect]
        }
        return [.reconnect, .disconnect]
    }

    static func normalizedSelfHostedGitLabHost(from value: String) -> GitProviderHost? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(" ") else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host(percentEncoded: false),
              !host.isEmpty,
              host.lowercased() != "gitlab.com" else {
            return nil
        }

        return GitProviderHost(kind: .gitlab, baseURL: url).normalized
    }
}
