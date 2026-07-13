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

enum GitSubmoduleState: Equatable, Sendable {
    case clean
    case modified
    case newCommits
    case uninitialized
    case missing
    case conflict
}

struct GitSubmoduleEntry: Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let url: String
    let branch: String?
    let recordedCommit: String?
    let checkedOutCommit: String?
    let state: GitSubmoduleState

    var id: String { path }

    var isInitialized: Bool {
        state != .uninitialized && state != .missing
    }
}
