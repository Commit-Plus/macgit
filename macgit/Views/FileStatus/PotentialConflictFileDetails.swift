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

struct PotentialConflictFileDetails: View {
    let baseRef: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Potential update conflict", systemImage: "exclamationmark.triangle")
                .bold()
                .foregroundStyle(.orange)

            Text("This file is not currently conflicted.")

            if let baseRef {
                Text("It has local changes and is also changed by \(baseRef).")
            } else {
                Text("It has local changes and is also changed by the incoming branch update.")
            }

            Text("Review, commit, or stash the local changes before updating the current branch.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}
