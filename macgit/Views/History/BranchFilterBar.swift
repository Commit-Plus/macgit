//
//  BranchFilterBar.swift
//  macgit
//

import SwiftUI

struct BranchFilterBar: View {
    @Binding var showAllBranches: Bool
    let graphWidth: CGFloat
    @Binding var messageWidth: CGFloat
    @Binding var authorWidth: CGFloat
    @Binding var dateWidth: CGFloat
    @Binding var commitWidth: CGFloat
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Branch filter dropdown
            Picker("Branch Filter", selection: $showAllBranches) {
                Text("All Branches").tag(true)
                Text("Current Branch").tag(false)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
            .padding(.leading, 8)

            // Column headers aligned with CommitRowView
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: graphWidth, height: 16)
                    .fixedSize()

                Text("Message")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: messageWidth, alignment: .leading)

                ColumnResizer(width: $messageWidth)

                Spacer(minLength: 8)

                Text("Author")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: authorWidth, alignment: .leading)

                ColumnResizer(width: $authorWidth)

                Text("Date")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: dateWidth, alignment: .trailing)

                ColumnResizer(width: $dateWidth)

                Text("Commit")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: commitWidth, alignment: .trailing)
            }
            .padding(.leading, 8)
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
    @Binding var width: CGFloat
    @State private var lastX: CGFloat = 0

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
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if lastX == 0 {
                            lastX = value.startLocation.x
                        }
                        let delta = value.location.x - lastX
                        width = max(40, width + delta)
                        lastX = value.location.x
                    }
                    .onEnded { _ in
                        lastX = 0
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
