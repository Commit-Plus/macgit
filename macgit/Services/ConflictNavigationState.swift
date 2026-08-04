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

struct ConflictNavigationState {
    let unresolvedConflictSectionIndices: [Int]
    let currentSectionIndex: Int?
    let previousSectionIndex: Int?
    let nextSectionIndex: Int?

    var canNavigatePrevious: Bool {
        previousSectionIndex != nil
    }

    var canNavigateNext: Bool {
        nextSectionIndex != nil
    }

    var currentOrdinal: Int? {
        guard let currentSectionIndex,
              let index = unresolvedConflictSectionIndices.firstIndex(of: currentSectionIndex) else {
            return nil
        }
        return index + 1
    }

    var remainingCount: Int {
        unresolvedConflictSectionIndices.count
    }

    init(document: ConflictResolutionDocument, currentSectionIndex: Int?) {
        unresolvedConflictSectionIndices = document.manualResolvedText == nil
            ? document.sections.indices.filter { index in
                document.sections[index].isConflict && !document.sections[index].isResolved
            }
            : []

        let normalizedCurrentSectionIndex = Self.normalizedCurrentSectionIndex(
            preferredSectionIndex: currentSectionIndex,
            unresolvedSectionIndices: unresolvedConflictSectionIndices
        )

        self.currentSectionIndex = normalizedCurrentSectionIndex

        if let normalizedCurrentSectionIndex,
           let currentIndex = unresolvedConflictSectionIndices.firstIndex(of: normalizedCurrentSectionIndex) {
            let count = unresolvedConflictSectionIndices.count
            // Cyclic navigation: the previous/next buttons remain enabled as long as
            // any unresolved conflicts exist, including when there is only a single
            // conflict block. Clicking either button re-scrolls to that block.
            let previousIndex = (currentIndex - 1 + count) % count
            let nextIndex = (currentIndex + 1) % count
            previousSectionIndex = unresolvedConflictSectionIndices[previousIndex]
            nextSectionIndex = unresolvedConflictSectionIndices[nextIndex]
        } else {
            previousSectionIndex = nil
            nextSectionIndex = nil
        }
    }

    private static func normalizedCurrentSectionIndex(
        preferredSectionIndex: Int?,
        unresolvedSectionIndices: [Int]
    ) -> Int? {
        guard !unresolvedSectionIndices.isEmpty else { return nil }
        guard let preferredSectionIndex else { return unresolvedSectionIndices.first }

        if unresolvedSectionIndices.contains(preferredSectionIndex) {
            return preferredSectionIndex
        }

        if let next = unresolvedSectionIndices.first(where: { $0 > preferredSectionIndex }) {
            return next
        }

        return unresolvedSectionIndices.last(where: { $0 < preferredSectionIndex })
    }
}
