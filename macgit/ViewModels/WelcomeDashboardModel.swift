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
import Observation

@MainActor
@Observable
final class WelcomeDashboardModel {
    private(set) var snapshot = WelcomeDashboardSnapshot(days: WelcomeDashboardSnapshot.days(endingAt: .now))
    private(set) var isLoading = true
    private(set) var updatedAt: Date?
    private(set) var attention: [WelcomeRepositoryAttention] = []
    private(set) var isCheckingAttention = true
    private(set) var attentionUpdatedAt: Date?
    private var attentionGeneration = UUID()
    private var generation = UUID()

    func refreshAttention(repositories: [RecentRepository]) async {
        let request = UUID()
        attentionGeneration = request
        isCheckingAttention = true
        var result: [WelcomeRepositoryAttention] = []
        var seen = Set<URL>()
        for repository in repositories.sorted(by: { $0.lastOpened > $1.lastOpened })
            where seen.insert(repository.url.standardizedFileURL).inserted {
            guard !Task.isCancelled, request == attentionGeneration else { return }
            do {
                let status = try await GitStatusService.shared.welcomeAttention(for: repository)
                if status.needsAttention { result.append(status) }
            } catch {
                guard !Task.isCancelled, request == attentionGeneration else { return }
            }
        }
        guard !Task.isCancelled, request == attentionGeneration else { return }
        attention = result.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        attentionUpdatedAt = .now
        isCheckingAttention = false
    }

    func refresh(repositories: [RecentRepository], force: Bool = false) async {
        let request = UUID()
        generation = request
        isLoading = true
        let now = Date.now
        let days = WelcomeDashboardSnapshot.days(endingAt: now)
        var oldestUpdate = now
        var result = WelcomeDashboardSnapshot(days: days)
        var seen = Set<URL>()
        let recent = repositories.sorted { $0.lastOpened > $1.lastOpened }
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
            .prefix(7)
        for repository in recent {
            guard !Task.isCancelled, request == generation else { return }
            if !force, let cached = await WelcomeActivityCache.shared.entry(for: repository.url, days: days, now: now) {
                result.repositories.append(cached.activity)
                oldestUpdate = min(oldestUpdate, cached.savedAt)
                continue
            }
            do {
                let activity = try await GitStatusService.shared.welcomeActivity(for: repository, days: days)
                guard !Task.isCancelled, request == generation else { return }
                result.repositories.append(activity)
                await WelcomeActivityCache.shared.save(WelcomeActivityCacheEntry(days: days, savedAt: now, activity: activity))
            } catch {
                guard !Task.isCancelled, request == generation else { return }
            }
        }
        guard !Task.isCancelled, request == generation else { return }
        snapshot = result
        updatedAt = oldestUpdate
        isLoading = false
    }
}
