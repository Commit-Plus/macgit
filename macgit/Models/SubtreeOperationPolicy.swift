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

enum SubtreeOperation: Equatable, Sendable {
    case add
    case pull
    case push
}

struct SubtreeOperationDecision: Equatable, Sendable {
    let isAllowed: Bool
    let blockingPaths: [String]
    let message: String?
}

enum SubtreeOperationPolicy {
    static let unavailableMessage = "This Git installation does not include git subtree."
    static let dirtyTreeMessage = "Commit, stash, or discard changes before running subtree operations."

    static func decision(forStatus status: String) -> SubtreeOperationDecision {
        let blockingPaths = blockingPaths(fromPorcelainStatus: status)
        guard !blockingPaths.isEmpty else {
            return SubtreeOperationDecision(isAllowed: true, blockingPaths: [], message: nil)
        }
        return SubtreeOperationDecision(
            isAllowed: false,
            blockingPaths: blockingPaths,
            message: dirtyTreeMessage
        )
    }

    static func blockingPaths(fromPorcelainStatus status: String) -> [String] {
        let records = status.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var paths: [String] = []
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 4 else {
                index += 1
                continue
            }

            let state = String(record.prefix(2))
            let path = String(record.dropFirst(3))
            if state.first == "R" || state.first == "C" {
                if index + 1 < records.count {
                    paths.append(records[index + 1])
                    index += 2
                    continue
                }
            }
            paths.append(path)
            index += 1
        }
        return Array(Set(paths)).sorted { left, right in
            left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

