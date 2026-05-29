//
//  SidebarView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case fileStatus = "File status"
    case history = "History"
    case search = "Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fileStatus: return "doc.text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        case .search: return "magnifyingglass"
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case workspace = "WORKSPACE"
    case branches = "BRANCHES"
    case tags = "TAGS"
    case remotes = "REMOTES"
    case stashes = "STASHES"
    case submodules = "SUBMODULES"
    case subtrees = "SUBTREES"

    var items: [SidebarItem] {
        switch self {
        case .workspace:
            return [.fileStatus, .history, .search]
        default:
            return []
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section(SidebarSection.workspace.rawValue) {
                ForEach(SidebarSection.workspace.items) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

            ForEach(SidebarSection.allCases.dropFirst(), id: \.self) { section in
                Section(section.rawValue) {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
        .listStyle(.sidebar)
    }
}
