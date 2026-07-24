//
//  BranchFilterBar.swift
//  macgit
//

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

struct BranchFilterBar: View {
    @Binding var showAllBranches: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Picker("Branch Filter", selection: $showAllBranches) {
                Text("All Branches").tag(true)
                Text("Current Branch").tag(false)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
            .padding(.leading, 8)

            Spacer()
        }
        .padding(.trailing, 16)
        .frame(height: 28)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
        .onChange(of: showAllBranches) { _, _ in
            onChange()
        }
    }
}

struct ColumnResizer: View {
    @Binding var leftWidth: CGFloat
    @Binding var rightWidth: CGFloat
    var minimumLeftWidth: CGFloat = 40
    @State private var initialLeftWidth: CGFloat?
    @State private var initialRightWidth: CGFloat?
    @State private var dragHasRightColumn = false

    /// Whether the right side is a real column (true) or empty space (false)
    private var hasRightColumn: Bool { rightWidth > 10 }

    static func committedWidths(
        initialLeft: CGFloat,
        initialRight: CGFloat,
        translation: CGFloat,
        hasRightColumn: Bool,
        minimumLeftWidth: CGFloat = 40
    ) -> (left: CGFloat, right: CGFloat) {
        let minimumRightWidth: CGFloat = 40

        if hasRightColumn {
            // Standard two-column resizer: space moves from right to left.
            let maxExpand = initialRight - minimumRightWidth
            let actualDelta = max(-(initialLeft - minimumLeftWidth), min(translation, maxExpand))
            return (
                left: initialLeft + actualDelta,
                right: initialRight - actualDelta
            )
        } else {
            // Last resizer: only clamp left column minimum.
            let actualDelta = max(-(initialLeft - minimumLeftWidth), translation)
            return (
                left: initialLeft + actualDelta,
                right: initialRight
            )
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if initialLeftWidth == nil {
                            initialLeftWidth = leftWidth
                            initialRightWidth = rightWidth
                            dragHasRightColumn = hasRightColumn
                        }

                        guard let initialLeftWidth,
                              let initialRightWidth else {
                            return
                        }

                        let resizedWidths = Self.committedWidths(
                            initialLeft: initialLeftWidth,
                            initialRight: initialRightWidth,
                            translation: value.translation.width,
                            hasRightColumn: dragHasRightColumn,
                            minimumLeftWidth: minimumLeftWidth
                        )
                        leftWidth = resizedWidths.left
                        rightWidth = resizedWidths.right
                    }
                    .onEnded { _ in
                        initialLeftWidth = nil
                        initialRightWidth = nil
                    }
            )
            .overlay(
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            )
    }
}
