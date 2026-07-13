//
//  RecentRepositoriesStore.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation
import Combine

struct RecentRepository: Codable, Identifiable {
    let id: UUID
    var url: URL
    var lastOpened: Date
    var name: String

    init(url: URL, lastOpened: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.lastOpened = lastOpened
        self.name = url.lastPathComponent
    }
}

final class RecentRepositoriesStore: ObservableObject {
    static let shared = RecentRepositoriesStore()
    private let key = "dev.thanhtran.macgit.recentRepositories"

    @Published var repositories: [RecentRepository] = []

    private init() {
        load()
    }

    func add(_ url: URL) {
        var repos = repositories.filter { $0.url != url }
        repos.insert(RecentRepository(url: url), at: 0)
        repositories = Array(repos.prefix(20))
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            repositories.remove(at: index)
        }
        save()
    }

    func remove(_ repo: RecentRepository) {
        repositories.removeAll { $0.id == repo.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentRepository].self, from: data) else {
            return
        }
        repositories = decoded.sorted { $0.lastOpened > $1.lastOpened }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
