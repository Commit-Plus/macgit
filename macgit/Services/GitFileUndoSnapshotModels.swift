//
//  GitFileUndoSnapshotModels.swift
//  macgit
//

import Foundation

struct GitFileUndoSnapshot: Codable, Equatable {
    let id: UUID
    let items: [GitFileUndoSnapshotItem]
}

struct GitFileUndoSnapshotItem: Codable, Equatable {
    let path: String
    let existed: Bool
    let backupRelativePath: String?
}
