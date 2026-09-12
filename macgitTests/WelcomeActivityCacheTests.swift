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
import XCTest
@testable import macgit

final class WelcomeActivityCacheTests: XCTestCase {
    func testCacheExpiresAfterSixHoursAndWhenCalendarDayChanges() {
        let now = Date(timeIntervalSince1970: 1_789_210_800)
        let days = WelcomeDashboardSnapshot.days(endingAt: now)
        let entry = makeEntry(days: days, now: now)
        XCTAssertTrue(entry.isValid(for: days, now: now.addingTimeInterval(3600)))
        XCTAssertFalse(entry.isValid(for: days, now: now.addingTimeInterval(21600)))
        XCTAssertFalse(entry.isValid(for: days, now: now.addingTimeInterval(-1)))
        let nextDays = days.map { $0.addingTimeInterval(86400) }
        XCTAssertFalse(entry.isValid(for: nextDays, now: now.addingTimeInterval(60)))
    }

    func testSavedActivitySurvivesANewCacheInstance() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("cache.json")
        let now = Date.now
        let days = WelcomeDashboardSnapshot.days(endingAt: now)
        let entry = makeEntry(days: days, now: now)
        let first = WelcomeActivityCache(fileURL: file)
        await first.save(entry)
        let reopened = WelcomeActivityCache(fileURL: file)
        let cached = await reopened.entry(for: entry.activity.url, days: days, now: now)
        XCTAssertEqual(cached?.activity.commitsByDay, entry.activity.commitsByDay)
        XCTAssertEqual(cached?.activity.behindCount, 2)
        XCTAssertEqual(cached?.savedAt, now)
        let other = await reopened.entry(for: URL(fileURLWithPath: "/another"), days: days, now: now)
        XCTAssertNil(other)
    }

    func testCorruptCacheFallsBackToAMiss() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        let cache = WelcomeActivityCache(fileURL: file)
        let value = await cache.entry(for: URL(fileURLWithPath: "/repo"),
                                      days: WelcomeDashboardSnapshot.days(endingAt: .now), now: .now)
        XCTAssertNil(value)
    }

    private func makeEntry(days: [Date], now: Date) -> WelcomeActivityCacheEntry {
        var commits = days.map { _ in Set<String>() }
        commits[0] = ["commit-hash"]
        var activity = WelcomeRepositoryActivity(url: URL(fileURLWithPath: "/repo"), name: "Repo", commitsByDay: commits)
        activity.behindCount = 2
        return WelcomeActivityCacheEntry(days: days, savedAt: now, activity: activity)
    }
}
