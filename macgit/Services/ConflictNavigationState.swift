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
        unresolvedConflictSectionIndices = document.sections.indices.filter { index in
            document.sections[index].isConflict && !document.sections[index].isResolved
        }

        let normalizedCurrentSectionIndex = Self.normalizedCurrentSectionIndex(
            preferredSectionIndex: currentSectionIndex,
            unresolvedSectionIndices: unresolvedConflictSectionIndices
        )

        self.currentSectionIndex = normalizedCurrentSectionIndex

        if let normalizedCurrentSectionIndex,
           let currentIndex = unresolvedConflictSectionIndices.firstIndex(of: normalizedCurrentSectionIndex) {
            previousSectionIndex = currentIndex > 0 ? unresolvedConflictSectionIndices[currentIndex - 1] : nil
            nextSectionIndex = currentIndex + 1 < unresolvedConflictSectionIndices.count ? unresolvedConflictSectionIndices[currentIndex + 1] : nil
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
