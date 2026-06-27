import XCTest
@testable import macgit

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testStartPerformsSilentBackgroundCheckOnce() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        controller.start()

        XCTAssertEqual(updater.startCallCount, 1)
        XCTAssertEqual(updater.backgroundCheckCallCount, 1)
        XCTAssertEqual(controller.state, .checking)
    }

    func testAvailableUpdateTransitionsToAvailableState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)

        XCTAssertEqual(controller.state, .available)
    }

    func testNoUpdateFoundReturnsToIdleState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.noUpdateFound)

        XCTAssertEqual(controller.state, .idle)
    }

    func testDownloadStartedTransitionsToDownloadingState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)
        updater.emit(.downloadStarted)

        XCTAssertEqual(controller.state, .downloading)
    }

    func testDismissedSessionKeepsAvailableStateWhenNotDownloading() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)
        updater.emit(.sessionDismissed)

        XCTAssertEqual(controller.state, .available)
    }

    func testOpenUpdateWindowDelegatesToUpdater() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.openUpdateWindow()

        XCTAssertEqual(updater.showUpdateWindowCallCount, 1)
    }

    func testManualCheckDelegatesToUpdater() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.checkForUpdates()

        XCTAssertEqual(updater.userInitiatedCheckCallCount, 1)
    }
}

@MainActor
private final class FakeAppUpdater: AppUpdaterProtocol {
    var startCallCount = 0
    var backgroundCheckCallCount = 0
    var showUpdateWindowCallCount = 0
    var userInitiatedCheckCallCount = 0

    private var eventHandler: ((AppUpdaterEvent) -> Void)?

    func start() {
        startCallCount += 1
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCallCount += 1
    }

    func showUpdateWindow() {
        showUpdateWindowCallCount += 1
    }

    func checkForUpdates() {
        userInitiatedCheckCallCount += 1
    }

    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void) {
        eventHandler = handler
    }

    func emit(_ event: AppUpdaterEvent) {
        eventHandler?(event)
    }
}
