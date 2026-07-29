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
import Foundation
import Combine

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var latestVersionCheckError: String?

    let currentVersion: String
    let currentBuild: String?

    var displayState: AppUpdateState {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-macgit-show-update-button") {
            return .available
        }
#endif
        return state
    }

    private let updater: AppUpdaterProtocol
    private var hasStarted = false

    init(
        updater: AppUpdaterProtocol,
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown",
        currentBuild: String? = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
    ) {
        self.updater = updater
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        updater.setEventHandler { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        guard !hasStarted else { return }

        hasStarted = true
        state = .checking
        latestVersionCheckError = nil
        updater.start()
        updater.checkForUpdatesInBackground()
    }

    func openUpdateWindow() {
        updater.showUpdateWindow()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func refreshLatestVersion() {
        guard state != .downloading else { return }

        state = .checking
        latestVersionCheckError = nil
        updater.checkForUpdatesInBackground()
    }

    private func handle(_ event: AppUpdaterEvent) {
        switch event {
        case let .updateAvailable(version):
            latestVersion = version
            latestVersionCheckError = nil
            state = .available
        case let .noUpdateFound(latestVersion):
            self.latestVersion = latestVersion ?? currentVersion
            latestVersionCheckError = nil
            state = .idle
        case let .checkFailed(message):
            latestVersionCheckError = message
            state = .idle
        case .downloadStarted:
            state = .downloading
        case .sessionDismissed:
            if state != .downloading {
                state = .available
            }
        }
    }
}
