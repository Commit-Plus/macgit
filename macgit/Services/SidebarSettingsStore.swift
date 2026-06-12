//
//  SidebarSettingsStore.swift
//  macgit
//

import Foundation

struct SidebarSectionState: Codable {
    var branchesExpanded: Bool = true
    var tagsExpanded: Bool = true
    // Future sections: remotesExpanded, stashesExpanded, etc.
}

final class SidebarSettingsStore {
    static let shared = SidebarSettingsStore()
    private let key = "com.thanhtran.macgit.sidebarSettings"

    private var settings: [String: SidebarSectionState] = [:]

    private init() {
        load()
    }

    func state(for repositoryPath: String) -> SidebarSectionState {
        settings[repositoryPath] ?? SidebarSectionState()
    }

    func update(for repositoryPath: String, state: SidebarSectionState) {
        settings[repositoryPath] = state
        save()
    }

    func toggleSection(_ section: SidebarSection, for repositoryPath: String) {
        var state = self.state(for: repositoryPath)
        switch section {
        case .branches:
            state.branchesExpanded.toggle()
        case .tags:
            state.tagsExpanded.toggle()
        default:
            break
        }
        update(for: repositoryPath, state: state)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SidebarSectionState].self, from: data) else {
            return
        }
        settings = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
