//
//  GitUndoMenuAction.swift
//  macgit
//

import Foundation

enum GitUndoMenuAction {
    case undo
    case redo
}

extension Notification.Name {
    static let gitUndoAction = Notification.Name("macgit.gitUndoAction")
}
