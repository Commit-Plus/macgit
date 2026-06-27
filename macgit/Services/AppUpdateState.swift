import Foundation

enum AppUpdateState: Equatable {
    case idle
    case checking
    case available
    case downloading
}
