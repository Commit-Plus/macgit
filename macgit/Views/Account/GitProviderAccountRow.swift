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
        HStack(alignment: .top, spacing: 12) {
            Image(providerAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(providerName)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(statusColor)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Account")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(account.username)
                    }

                    GridRow {
                        Text("Host")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(account.hostURL.host() ?? account.hostURL.absoluteString)
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Reconnect...", action: reconnect)
                        .buttonStyle(.bordered)
                    Button("Disconnect...", role: .destructive, action: disconnect)
                        .foregroundStyle(.red)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .accessibilityElement(children: .contain)
    }

    private var providerAssetName: String {
        switch account.provider {
        case .github: "github"
        case .gitlab: "gitlab"
        }
    }

    private var providerName: String {
        switch account.provider {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    private var statusColor: Color {
        switch account.tokenStatus {
        case .valid: .green
        case .expired, .revoked, .reauthorizationRequired, .unavailableOnThisDevice: .orange
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
