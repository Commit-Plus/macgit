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

struct GitProviderDeviceAuthorizationView: View {
    let authorization: GitProviderDeviceAuthorization
    let openVerification: () -> Void
    let copyToPasteboard: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("Connect \(authorization.provider.displayName) Account")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .hidden()
                    .frame(width: 24, height: 24)

                Text(authorization.userCode)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .textSelection(.enabled)

                Button("Copy Code", systemImage: "doc.on.doc") {
                    copyToPasteboard(authorization.userCode)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy code")
                .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                Button("Open \(authorization.provider.displayName) Device Page", action: openVerification)
                Button("Cancel", role: .cancel, action: cancel)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
