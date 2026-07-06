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

enum SearchResultType: String, CaseIterable {
    case commit = "Commits"
    case file = "Files"
    case branch = "Branches"
    case tag = "Tags"
    
    var icon: String {
        switch self {
        case .commit: return "doc.text"
        case .file: return "doc"
        case .branch: return "leaf"
        case .tag: return "tag"
        }
    }
}

enum SearchFilter: String, CaseIterable {
    case all
    case commit
    case file
    case branch
    case tag

    var title: String {
        switch self {
        case .all: return "All"
        case .commit: return "Commits"
        case .file: return "Files"
        case .branch: return "Branches"
        case .tag: return "Tags"
        }
    }

    var resultType: SearchResultType? {
        switch self {
        case .all: return nil
        case .commit: return .commit
        case .file: return .file
        case .branch: return .branch
        case .tag: return .tag
        }
    }
}

enum SearchAction: Hashable {
    case showCommit(String)        // commit hash
    case showFile(String)           // file path relative to repo root
    case checkoutBranch(String)     // branch name
    case showTag(String)            // tag name
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String
    let action: SearchAction
    let badge: String?
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
