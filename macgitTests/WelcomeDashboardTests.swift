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

@MainActor
final class WelcomeDashboardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }

    func testBucketsMatchLiteralEmailAndUseLocalCalendarDays() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let days = WelcomeDashboardSnapshot.days(endingAt: today, calendar: calendar)
        let timestamp = Int(today.timeIntervalSince1970)
        let log = """
        own\tme+work@example.com\t\(timestamp)
        own\tme+work@example.com\t\(timestamp)
        other\tmeeeee@example.com\t\(timestamp)
        yesterday\tME+WORK@example.com\t\(timestamp - 1)
        old\tme+work@example.com\t\(timestamp - 30 * 86400)
        future\tme+work@example.com\t\(timestamp + 86400)
        malformed
        """
        let buckets = GitStatusService.welcomeCommitBuckets(
            log: log, email: "me+work@example.com", days: days, calendar: calendar
        )
        XCTAssertEqual(buckets.count, 30)
        XCTAssertEqual(buckets[29], ["own"])
        XCTAssertEqual(buckets[28], ["yesterday"])
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, 2)
    }

    func testOverviewDeduplicatesSharedCommitsAcrossRepositories() {
        let days = WelcomeDashboardSnapshot.days(endingAt: .now, calendar: calendar)
        var snapshot = WelcomeDashboardSnapshot(days: days)
        var commits = days.map { _ in Set<String>() }
        commits[0] = ["shared"]
        commits[29] = ["latest"]
        snapshot.repositories = [
            WelcomeRepositoryActivity(url: URL(fileURLWithPath: "/one"), name: "One", commitsByDay: commits),
            WelcomeRepositoryActivity(url: URL(fileURLWithPath: "/two"), name: "Two", commitsByDay: commits)
        ]
        XCTAssertEqual(snapshot.commitCount, 2)
        XCTAssertEqual(snapshot.activeDays, 2)
    }

    func testCalendarDaysStayAtMidnightAcrossDaylightSavingTransition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 15))!
        let days = WelcomeDashboardSnapshot.days(endingAt: date, calendar: calendar)
        XCTAssertEqual(days.count, 30)
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertEqual(calendar.component(.day, from: days[0]), 9)
    }

    func testLocalScanReportsConflictsBehindAndOnlyCurrentAuthor() async throws {
        let runner = WelcomeDashboardTestRunner()
        let service = GitStatusService(runner: runner)
        let days = WelcomeDashboardSnapshot.days(endingAt: .now, calendar: calendar)
        let result = try await service.welcomeActivity(
            for: RecentRepository(url: URL(fileURLWithPath: "/example")), days: days, calendar: calendar
        )
        XCTAssertEqual(result.conflictCount, 2)
        XCTAssertEqual(result.behindCount, 3)
        XCTAssertEqual(result.commitCount, 1)
        XCTAssertNil(result.activityNote)
        XCTAssertTrue(result.needsAttention)
    }

    func testMissingIdentityDoesNotCountOtherAuthors() async throws {
        let service = GitStatusService(runner: WelcomeDashboardTestRunner(email: ""))
        let result = try await service.welcomeActivity(
            for: RecentRepository(url: URL(fileURLWithPath: "/example")),
            days: WelcomeDashboardSnapshot.days(endingAt: .now)
        )
        XCTAssertEqual(result.commitCount, 0)
        XCTAssertNotNil(result.activityNote)
        XCTAssertEqual(result.behindCount, 3)
    }

    func testCreateRefusesAnExistingFolderWithoutInitializingIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("keep.txt")
        try "keep".write(to: file, atomically: true, encoding: .utf8)
        do {
            try await GitStatusService.shared.createEmptyRepository(at: folder)
            XCTFail("Existing folder must be rejected")
        } catch {
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "keep")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path))
        }
    }
}
