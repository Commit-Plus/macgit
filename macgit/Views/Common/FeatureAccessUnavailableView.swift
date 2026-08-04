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

struct FeatureAccessUnavailableView: View {
    let notice: FeatureAccessNotice
    let isSignedIn: Bool
    let onAccountAction: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(notice.title, systemImage: systemImage)
        } description: {
            Text(notice.message)
        } actions: {
            if notice.denial == .requiresPro {
                Button(isSignedIn ? "Manage Account" : "Sign In", action: onAccountAction)
                    .buttonStyle(.borderedProminent)
            }
            if notice.denial == .repositoryVisibilityUnavailable {
                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
            }
        }
    }

    private var systemImage: String {
        switch notice.denial {
        case .requiresPro:
            "lock.fill"
        case .repositoryVisibilityUnavailable:
            "wifi.exclamationmark"
        case .featureDisabled, .repositoryScopeNotAllowed:
            "nosign"
        }
    }
}
