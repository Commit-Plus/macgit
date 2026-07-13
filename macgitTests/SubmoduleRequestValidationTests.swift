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

final class SubmoduleRequestValidationTests: XCTestCase {
    func testRejectsEmptyRepository() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(repository: "   "),
                in: repository
            )
        )
    }

    func testRejectsAbsolutePath() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "/tmp/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsParentTraversalOutsideRepository() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/../../SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsPathEscapingThroughSymlink() throws {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Parent", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: repository.appendingPathComponent("LinkedOutside"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "LinkedOutside/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsDuplicateConfiguredPath() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            path = Packages/SharedKit
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsDuplicateConfiguredPathWithCaseInsensitiveKey() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            PATH = Packages/SharedKit
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/SharedKit"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .duplicatePath("Packages/SharedKit")
            )
        }
    }

    func testRejectsDuplicateConfiguredPathWithQuotedEscapedValue() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            path = "Packages/Shared\\\"Kit"
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/Shared\"Kit"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .duplicatePath("Packages/Shared\"Kit")
            )
        }
    }

    func testTrimsConfiguredBranch() throws {
        let repository = try makeRepositoryDirectory()

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(branch: "  release/v2  "),
            in: repository
        )

        XCTAssertEqual(validated.branch, "release/v2")
    }

    func testAcceptsAndStandardizesNestedRelativePath() throws {
        let repository = try makeRepositoryDirectory()

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(
                repository: "  https://example.com/shared-kit.git  ",
                path: "  Packages\\Libraries/../SharedKit  "
            ),
            in: repository
        )

        XCTAssertEqual(validated.repository, "https://example.com/shared-kit.git")
        XCTAssertEqual(validated.path, "Packages/SharedKit")
        XCTAssertEqual(validated.initializeAfterAdd, true)
        XCTAssertEqual(validated.shallow, false)
    }

    private func request(
        repository: String = "https://example.com/shared-kit.git",
        path: String = "Packages/SharedKit",
        branch: String? = nil
    ) -> SubmoduleAddRequest {
        SubmoduleAddRequest(
            repository: repository,
            path: path,
            branch: branch,
            initializeAfterAdd: true,
            shallow: false
        )
    }

    private func makeRepositoryDirectory() throws -> URL {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Parent", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        return repository
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-submodule-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
