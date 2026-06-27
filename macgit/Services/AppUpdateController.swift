import Foundation
import Combine

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle

    private let updater: AppUpdaterProtocol
    private var hasStarted = false

    init(updater: AppUpdaterProtocol) {
        self.updater = updater
        updater.setEventHandler { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        guard !hasStarted else { return }

        hasStarted = true
        state = .checking
        updater.start()
        updater.checkForUpdatesInBackground()
    }

    func openUpdateWindow() {
        updater.showUpdateWindow()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func handle(_ event: AppUpdaterEvent) {
        switch event {
        case .updateAvailable:
            state = .available
        case .noUpdateFound:
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
