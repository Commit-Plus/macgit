import Foundation

enum ConflictPaneSelectionSide {
    case incoming
    case current

    var title: String {
        switch self {
        case .incoming:
            return "Incoming"
        case .current:
            return "Current"
        }
    }

    var resolution: ConflictSectionResolution {
        switch self {
        case .incoming:
            return .incoming
        case .current:
            return .current
        }
    }
}
