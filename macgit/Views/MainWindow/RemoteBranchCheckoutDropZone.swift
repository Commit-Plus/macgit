//
//  RemoteBranchCheckoutDropZone.swift
//  macgit
//

import SwiftUI

struct RemoteBranchCheckoutDropZone: View {
    let remoteBranch: String
    let isTargeted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
            Text("Drop to Check Out")
                .bold()
            Spacer(minLength: 4)
            Text(remoteBranch)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop \(remoteBranch) to check out as a local branch")
    }
}
