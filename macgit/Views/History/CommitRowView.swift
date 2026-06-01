//
//  CommitRowView.swift
//  macgit
//

import SwiftUI

struct CommitRowView: View {
    let node: GraphNode
    let graphWidth: CGFloat
    let isSelected: Bool
    
    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: node.commit.date, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Fixed-width spacer so all commit messages align regardless of lane count
            Color.clear
                .frame(width: graphWidth, height: 32)
                .fixedSize()
            
            // Commit message
            Text(node.commit.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 120, alignment: .leading)
            
            Spacer(minLength: 8)
            
            // Ref labels
            if !node.commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(node.commit.refs.prefix(3), id: \.self) { ref in
                        RefLabel(text: ref)
                    }
                }
            }
            
            // Author
            Text(node.commit.author)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 80, maxWidth: 140, alignment: .leading)
            
            // Date
            Text(relativeDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 60, maxWidth: 80, alignment: .trailing)
            
            // Hash
            Text(node.commit.shortHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 32)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }
}

struct RefLabel: View {
    let text: String
    
    var displayText: String {
        if text.hasPrefix("HEAD -> ") {
            return String(text.dropFirst(8))
        }
        if text.hasPrefix("tag: ") {
            return String(text.dropFirst(5))
        }
        return text
    }
    
    var isTag: Bool {
        text.hasPrefix("tag: ")
    }
    
    var backgroundColor: Color {
        isTag ? Color(nsColor: .systemPurple).opacity(0.15) : Color.accentColor.opacity(0.15)
    }
    
    var textColor: Color {
        isTag ? Color(nsColor: .systemPurple) : .accentColor
    }
    
    var body: some View {
        Text(displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
