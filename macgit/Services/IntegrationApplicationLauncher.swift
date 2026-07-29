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

enum IntegrationApplicationLauncher {
    @MainActor
    static func launch(
        _ application: IntegrationApplication,
        opening itemURL: URL? = nil,
        workspace: NSWorkspace = .shared
    ) async throws {
        if let itemURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                workspace.open(
                    [itemURL],
                    withApplicationAt: application.applicationURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } else if !workspace.open(application.applicationURL) {
            throw IntegrationLaunchError.noApplicationAvailable(application.displayName)
        }
    }
}
