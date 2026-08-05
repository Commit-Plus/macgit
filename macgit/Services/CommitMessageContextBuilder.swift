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

enum CommitMessageContextBuilder {
    static func build(
        nameStatus: String,
        numberStats: String,
        patch: String,
        characterBudget: Int
    ) -> (context: String, isTruncated: Bool) {
        let budget = max(2_000, characterBudget)
        let metadataBudget = min(1_500, budget / 4)
        let patchBudget = max(500, budget - metadataBudget)

        let metadata = """
        Files:
        \(nameStatus.trimmingCharacters(in: .whitespacesAndNewlines))

        Line statistics:
        \(numberStats.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        let boundedMetadata = bounded(metadata, to: metadataBudget)
        let boundedPatch = bounded(patch, to: patchBudget)
        let context = """
        \(boundedMetadata.text)

        Patch:
        \(boundedPatch.text)
        """

        return (
            context.trimmingCharacters(in: .whitespacesAndNewlines),
            boundedMetadata.wasTruncated || boundedPatch.wasTruncated
        )
    }

    private static func bounded(
        _ text: String,
        to maximumCharacters: Int
    ) -> (text: String, wasTruncated: Bool) {
        guard text.count > maximumCharacters else {
            return (text, false)
        }
        return (
            String(text.prefix(maximumCharacters)) + "\n[Additional change data omitted]",
            true
        )
    }
}
