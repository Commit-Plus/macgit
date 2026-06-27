import Foundation

enum AppUpdaterEvent {
    case updateAvailable
    case noUpdateFound
    case downloadStarted
    case sessionDismissed
}

@MainActor
protocol AppUpdaterProtocol: AnyObject {
    func start()
    func checkForUpdatesInBackground()
    func showUpdateWindow()
    func checkForUpdates()
    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void)
}
