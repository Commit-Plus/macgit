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

enum GitFlowLocalStateIssue: Equatable {
    case corrupt
    case unsupportedVersion(Int)

    var message: String {
        switch self {
        case .corrupt:
            return "Commit+ could not read the saved Git Flow recovery state. Open File Status and recover the Git operation manually before starting another flow."
        case .unsupportedVersion(let version):
            return "This Git Flow recovery state was written by a newer version (schema \(version)). Update Commit+ or recover the Git operation manually."
        }
    }
}

enum GitFlowLocalStateLoadResult<Value> {
    case none
    case value(Value)
    case invalid(GitFlowLocalStateIssue)
}
