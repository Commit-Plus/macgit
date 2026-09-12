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

/// Shared by the heatmap and its legend so intensity and borders always match.
struct WelcomeActivityCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.primary.opacity(colorScheme == .light ? 0.18 : 0.12), lineWidth: 0.5)
            }
    }

    private var fill: Color {
        if colorScheme == .light {
            switch count {
            case 0: Color(red: 0.91, green: 0.93, blue: 0.94)
            case 1: Color(red: 0.61, green: 0.87, blue: 0.65)
            case 2...3: Color(red: 0.25, green: 0.74, blue: 0.39)
            case 4...7: Color(red: 0.19, green: 0.60, blue: 0.30)
            default: Color(red: 0.13, green: 0.43, blue: 0.22)
            }
        } else {
            switch count {
            case 0: Color.primary.opacity(0.06)
            case 1: Color.green.opacity(0.25)
            case 2...3: Color.green.opacity(0.45)
            case 4...7: Color.green.opacity(0.7)
            default: Color.green
            }
        }
    }
}
