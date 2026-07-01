//
//  StashDragPreview.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C)  Thanh Tran <trantienthanh2412@gmail.com>
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

struct StashDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apply \(title)")
    }
}

#Preview {
    StashDragPreview(title: "On main : WIP")
        .padding()
}
