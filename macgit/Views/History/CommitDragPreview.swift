//
//  CommitDragPreview.swift
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

struct CommitDragPreview: View {
    let presentation: CommitDragPreviewPresentation
    let onDragStateChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(presentation.subject)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 300, alignment: .leading)

            Text(presentation.author)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text(presentation.date, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)

            Text(presentation.shortHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(width: 664, height: 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .onAppear {
            onDragStateChange(true)
        }
        .onDisappear {
            onDragStateChange(false)
        }
    }
}
