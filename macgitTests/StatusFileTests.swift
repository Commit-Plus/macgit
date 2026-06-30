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
final class StatusFileTests: XCTestCase {
    func testVideoExtensionsAreRecognized() {
        for ext in ["mp4", "mov", "mkv", "avi", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp"] {
            let file = StatusFile(path: "clip.\(ext)", status: .modified, originalPath: nil)
            XCTAssertTrue(file.isVideo, ".\(ext) should be recognized as video")
        }
    }

    func testNonVideoExtensionsAreNotVideo() {
        for ext in ["png", "jpg", "txt", "pdf", "mp3", "zip"] {
            let file = StatusFile(path: "file.\(ext)", status: .modified, originalPath: nil)
            XCTAssertFalse(file.isVideo, ".\(ext) should not be recognized as video")
        }
    }
}
