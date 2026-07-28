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

struct UpdateBannerView: View {
    struct Model: Equatable {
        let title: String
        let isEnabled: Bool
        let showsProgress: Bool

        static func make(for state: AppUpdateState) -> Self? {
            switch state {
            case .idle, .checking:
                return nil
            case .available:
                return .init(title: "Update", isEnabled: true, showsProgress: false)
            case .downloading:
                return .init(title: "Downloading…", isEnabled: false, showsProgress: true)
            }
        }
    }

    let model: Model
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: action) {
                Label(model.title, systemImage: "arrow.down.to.line")
            }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!model.isEnabled)
        }
    }
}
