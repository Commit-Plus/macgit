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

import AppKit
import Foundation

enum IntegrationApplicationCatalog {
    @MainActor
    static func availableApplications(
        for role: IntegrationRole,
        workspace: NSWorkspace = .shared
    ) -> [IntegrationApplication] {
        if role == .editor {
            return SearchFileApplicationResolver.availableApplications(workspace: workspace)
                .filter { $0.bundleIdentifier != SearchFileApplicationResolver.previewBundleIdentifier }
                .map {
                    IntegrationApplication(
                        bundleIdentifier: $0.bundleIdentifier,
                        displayName: $0.displayName,
                        applicationURL: $0.applicationURL
                    )
                }
        }

        return candidates(for: role).compactMap { bundleIdentifier, displayName in
            guard let applicationURL = workspace.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                return nil
            }
            return IntegrationApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                applicationURL: applicationURL
            )
        }
    }

    private static func candidates(for role: IntegrationRole) -> [(String, String)] {
        switch role {
        case .editor:
            []
        case .terminal:
            [
                ("com.apple.Terminal", "Terminal"),
                ("com.googlecode.iterm2", "iTerm2"),
                ("dev.warp.Warp-Stable", "Warp"),
                ("com.mitchellh.ghostty", "Ghostty"),
                ("org.alacritty", "Alacritty"),
                ("net.kovidgoyal.kitty", "kitty")
            ]
        case .diff, .merge:
            [
                ("com.apple.FileMerge", "FileMerge"),
                ("com.kaleidoscope.Kaleidoscope", "Kaleidoscope"),
                ("com.blackpixel.kaleidoscope", "Kaleidoscope"),
                ("com.scootersoftware.BeyondCompare", "Beyond Compare"),
                ("com.araxis.merge", "Araxis Merge"),
                ("com.perforce.p4merge", "P4Merge"),
                ("com.microsoft.VSCode", "Visual Studio Code"),
                ("com.todesktop.230313mzl4w4u92", "Cursor")
            ]
        }
    }
}
