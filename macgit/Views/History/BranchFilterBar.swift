//
//  BranchFilterBar.swift
//  macgit
//

import SwiftUI

struct BranchFilterBar: View {
    @Binding var showAllBranches: Bool
    let graphWidth: CGFloat
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
            HStack(spacing: 8) {
                Color.clear
                    .frame(width: graphWidth, height: 16)
                    .fixedSize()

                Text("Message")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(minWidth: 120, alignment: .leading)

                Spacer(minLength: 8)

                Text("Author")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(minWidth: 80, maxWidth: 140, alignment: .leading)

                Text("Date")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(minWidth: 60, maxWidth: 80, alignment: .trailing)

                Text("Commit")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 60, alignment: .trailing)
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
