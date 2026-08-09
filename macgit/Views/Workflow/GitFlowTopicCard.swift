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

struct GitFlowTopicCard: View {
    let kind: GitFlowTopicKind
    let prefix: String
    let baseBranch: String
    let canStart: Bool
    let canFinish: Bool
    let onStart: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: kind.dashboardIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 36, height: 36)
                    .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.headline)
                    Text("\(prefix) · from \(baseBranch)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(kind.dashboardDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Start…", systemImage: "play.fill", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)

                Button("Finish…", systemImage: "checkmark", action: onFinish)
                    .buttonStyle(.bordered)
                    .disabled(!canFinish)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

private extension GitFlowTopicKind {
    var dashboardIcon: String {
        switch self {
        case .feature: return "sparkles"
        case .bugfix: return "ladybug"
        case .release: return "shippingbox"
        case .hotfix: return "bandage"
        }
    }

    var tint: Color {
        switch self {
        case .feature: return .blue
        case .bugfix: return .orange
        case .release: return .purple
        case .hotfix: return .red
        }
    }

    var dashboardDescription: String {
        switch self {
        case .feature:
            return "Develop a new product capability independently, then integrate it into Develop."
        case .bugfix:
            return "Fix a non-critical defect on an isolated branch before returning it to Develop."
        case .release:
            return "Stabilize an upcoming version and finish it into the release branches."
        case .hotfix:
            return "Ship an urgent production fix from Main and merge it back into the workflow."
        }
    }
}
