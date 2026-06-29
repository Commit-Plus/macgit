//
//  GitInProgressOperation.swift
//  macgit
//

import Foundation

enum GitInProgressOperation: Equatable {
    case cherryPick(head: String)
    case revert(head: String)

    var displayName: String {
        switch self {
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        }
    }

    var shortHead: String {
        switch self {
        case .cherryPick(let head), .revert(let head):
            return String(head.prefix(7))
        }
    }

    var message: String {
        "\(displayName) in progress (\(shortHead)). Resolve conflicts, then continue or abort."
    }

    var emptyMessage: String {
        "\(displayName) (\(shortHead)) produced an empty commit. Skip the commit or abort."
    }
}
