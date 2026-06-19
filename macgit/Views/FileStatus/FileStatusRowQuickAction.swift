import Foundation

enum FileStatusRowQuickActionKind {
    case stage
    case unstage
}

struct FileStatusRowQuickAction {
    let kind: FileStatusRowQuickActionKind

    init(isStaged: Bool) {
        kind = isStaged ? .unstage : .stage
    }

    var systemImage: String {
        switch kind {
        case .stage:
            return "plus"
        case .unstage:
            return "minus"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .stage:
            return "Stage file"
        case .unstage:
            return "Unstage file"
        }
    }
}
