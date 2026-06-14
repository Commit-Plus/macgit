//
//  ToolbarAction.swift
//  macgit
//

import SwiftUI

enum ToolbarAction: Hashable {
    case commit, pull, push, fetch, branch, merge, stash
}

struct ToolbarActionKey: FocusedValueKey {
    typealias Value = Binding<ToolbarAction>
}

extension FocusedValues {
    var toolbarAction: Binding<ToolbarAction>? {
        get { self[ToolbarActionKey.self] }
        set { self[ToolbarActionKey.self] = newValue }
    }
}
