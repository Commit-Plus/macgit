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

/// Versioned, local-only cache. Per-repository entries survive reordering the recent list.
actor WelcomeActivityCache {
    static let shared = WelcomeActivityCache()
    private let fileURL: URL?
    private var entries: [String: WelcomeActivityCacheEntry]?

    init(fileURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("dev.thanhtran.macgit", isDirectory: true)
        .appendingPathComponent("welcome-activity-v1.json")) {
        self.fileURL = fileURL
    }

    func entry(for url: URL, days: [Date], now: Date) -> WelcomeActivityCacheEntry? {
        loadIfNeeded()
        guard let entry = entries?[url.standardizedFileURL.path],
              entry.isValid(for: days, now: now) else { return nil }
        return entry
    }

    func save(_ entry: WelcomeActivityCacheEntry) {
        loadIfNeeded()
        entries?[entry.activity.url.standardizedFileURL.path] = entry
        // Keep bounded storage while retaining recently opened repositories outside the top seven.
        let recent = (entries ?? [:]).sorted { $0.value.savedAt > $1.value.savedAt }.prefix(20)
        entries = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A disk failure still leaves the in-memory cache usable for this app session.
        }
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: WelcomeActivityCacheEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }
}
