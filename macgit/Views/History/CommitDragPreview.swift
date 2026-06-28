//
//  CommitDragPreview.swift
//  macgit
//

import SwiftUI

struct CommitDragPreview: View {
    let presentation: CommitDragPreviewPresentation
    let onDragStateChange: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if presentation.showsStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .frame(width: 288, height: 86)
                    .offset(x: 8, y: 8)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .frame(width: 288, height: 86)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text(presentation.subject)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(presentation.shortHash)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                HStack(spacing: 6) {
                    if !presentation.author.isEmpty {
                        Label(presentation.author, systemImage: "person.fill")
                            .lineLimit(1)
                    }

                    Text(presentation.date, format: .relative(presentation: .named))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 288, alignment: .leading)
            .frame(minHeight: 86)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            if let countBadgeText = presentation.countBadgeText {
                Text(countBadgeText)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                    .offset(x: 8, y: -8)
            }
        }
        .padding(.top, 8)
        .padding(.trailing, presentation.showsStack ? 16 : 8)
        .padding(.bottom, presentation.showsStack ? 16 : 8)
        .accessibilityElement(children: .combine)
        .onAppear {
            onDragStateChange(true)
        }
        .onDisappear {
            onDragStateChange(false)
        }
    }
}
