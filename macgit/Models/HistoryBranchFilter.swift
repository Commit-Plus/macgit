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

enum HistoryBranchFilter: Hashable, Sendable {
    case all
    case current
    case branch(String)

    init?(storageValue: String) {
        switch storageValue {
        case "all":
            self = .all
        case "current":
            self = .current
        default:
            let prefix = "branch:"
            guard storageValue.hasPrefix(prefix) else { return nil }
            let branch = String(storageValue.dropFirst(prefix.count))
            guard !branch.isEmpty else { return nil }
            self = .branch(branch)
        }
    }

    var storageValue: String {
        switch self {
        case .all:
            return "all"
        case .current:
            return "current"
        case .branch(let branch):
            return "branch:\(branch)"
        }
    }
}

extension HistoryBranchFilter: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let filter = HistoryBranchFilter(storageValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid history branch filter."
            )
        }
        self = filter
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}
