import Foundation
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdaterProtocol {
    private var updaterController: SPUStandardUpdaterController!
    private var eventHandler: ((AppUpdaterEvent) -> Void)?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    func showUpdateWindow() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
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
