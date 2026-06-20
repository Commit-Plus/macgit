//
//  GitUndoToolbarPolicy.swift
//  macgit
//

enum GitUndoToolbarPolicy {
    static func isUndoDisabled(isSyncing: Bool, canUndo: Bool) -> Bool {
        isSyncing || !canUndo
    }
}
