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

struct PotentialConflictCodeBlockView: View {
    let block: PotentialConflictBlock
    let fileExtension: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(block.lines) { line in
                HStack(spacing: 0) {
                    Text(String(line.lineNumber))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                        .padding(.trailing, 8)

                    Text(highlightedText(for: line))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .background(rowBackground(for: line))
            }
        }
        .padding(.vertical, 8)
    }

    private func highlightedText(for line: PotentialConflictLine) -> AttributedString {
        var attributed = SyntaxHighlighter(fileExtension: fileExtension)
            .attributedString(for: line.text, fontSize: 12)

        if line.isMarker {
            attributed.foregroundColor = markerColor(for: line.region)
            attributed.backgroundColor = markerColor(for: line.region).opacity(0.16)
            attributed.font = .system(size: 12, weight: .semibold, design: .monospaced)
        }

        return attributed
    }

    private func rowBackground(for line: PotentialConflictLine) -> Color {
        if line.isMarker {
            return markerColor(for: line.region).opacity(0.16)
        }

        switch line.region {
        case .context:
            return .clear
        case .local:
            return Color.red.opacity(0.10)
        case .mergeBase:
            return Color.orange.opacity(0.08)
        case .incoming:
            return Color.green.opacity(0.10)
        }
    }

    private func markerColor(for region: PotentialConflictLineRegion) -> Color {
        switch region {
        case .context:
            return .secondary
        case .local:
            return .red
        case .mergeBase:
            return .orange
        case .incoming:
            return .green
        }
    }
}
