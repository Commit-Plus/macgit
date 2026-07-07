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

struct GitProviderAccountRow: View {
    let account: GitProviderAccount
    let reconnect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(providerName, systemImage: "chevron.left.forwardslash.chevron.right")
                    .bold()
                Spacer()
                Text(statusText)
                    .foregroundStyle(account.tokenStatus == .valid ? Color.secondary : Color.orange)
            }

            LabeledContent("Account", value: account.username)
            LabeledContent("Host", value: account.hostURL.host() ?? account.hostURL.absoluteString)

            HStack {
                Spacer()
                if account.tokenStatus != .valid {
                    Button("Reconnect...", action: reconnect)
                }
                Button("Disconnect...", role: .destructive, action: disconnect)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var providerName: String {
        switch account.provider {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    private var statusText: String {
        switch account.tokenStatus {
        case .valid: "Connected"
        case .expired: "Expired"
        case .revoked: "Revoked"
        case .reauthorizationRequired: "Reconnect required"
        case .unavailableOnThisDevice: "Unavailable on this Mac"
        }
    }
}
