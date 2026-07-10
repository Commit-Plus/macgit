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
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdaterProtocol {
    private var updaterController: SPUStandardUpdaterController?
    private var eventHandler: ((AppUpdaterEvent) -> Void)?
    private let isEnabled: Bool

    override convenience init() {
        self.init(bundle: .main)
    }

    init(bundle: Bundle) {
        isEnabled = Self.isConfigurationUsable(
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
        super.init()
        if isEnabled {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        }
    }

    static func isConfigurationUsable(feedURL: String?, publicKey: String?) -> Bool {
        guard let feedURL = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let publicKey = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !feedURL.isEmpty && !publicKey.isEmpty
    }

    func start() {
        guard isEnabled, let updaterController else {
            eventHandler?(.noUpdateFound)
            return
        }
        updaterController.startUpdater()
    }

    func checkForUpdatesInBackground() {
        updaterController?.updater.checkForUpdatesInBackground()
    }

    func showUpdateWindow() {
        updaterController?.checkForUpdates(nil)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void) {
        eventHandler = handler
    }
}

extension SparkleAppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        eventHandler?(.updateAvailable)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        eventHandler?(.downloadStarted)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        eventHandler?(.noUpdateFound)
    }

    func updater(_ updater: SPUUpdater, userDidMake userChoice: SPUUserUpdateChoice, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if userChoice != .install {
            eventHandler?(.sessionDismissed)
        }
    }
}
