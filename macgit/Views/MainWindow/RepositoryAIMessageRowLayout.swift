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

struct RepositoryAIMessageRowLayout: Layout {
    let alignsTrailing: Bool
    let maximumWidthFraction: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let bubble = subviews.first else { return .zero }

        let availableWidth = proposal.width ?? bubble.sizeThatFits(.unspecified).width
        let bubbleSize = bubbleSize(for: bubble, availableWidth: availableWidth)
        return CGSize(width: availableWidth, height: bubbleSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let bubble = subviews.first else { return }

        let bubbleSize = bubbleSize(for: bubble, availableWidth: bounds.width)
        let originX = alignsTrailing ? bounds.maxX - bubbleSize.width : bounds.minX
        bubble.place(
            at: CGPoint(x: originX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(bubbleSize)
        )
    }

    private func bubbleSize(for bubble: LayoutSubview, availableWidth: CGFloat) -> CGSize {
        let maximumWidth = max(0, availableWidth * maximumWidthFraction)
        let idealSize = bubble.sizeThatFits(.unspecified)
        let idealWidth = idealSize.width.isFinite ? idealSize.width : maximumWidth
        let proposedWidth = min(idealWidth, maximumWidth)
        let fittedSize = bubble.sizeThatFits(
            ProposedViewSize(width: proposedWidth, height: nil)
        )

        return CGSize(
            width: min(fittedSize.width, maximumWidth),
            height: fittedSize.height
        )
    }
}
