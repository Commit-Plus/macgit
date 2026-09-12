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
@testable import macgit

struct WelcomeDashboardTestRunner: GitCommandRunning {
    var email = "me@example.com"

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        switch arguments.first {
        case "rev-parse": return arguments.contains("--git-dir") ? ".git" : "origin/main"
        case "diff": return "first.swift\0second.swift\0"
        case "rev-list": return "3\n"
        case "config": return email
        case "log":
            let timestamp = Int(Date.now.timeIntervalSince1970)
            return "mine\tme@example.com\t\(timestamp)\nother\tother@example.com\t\(timestamp)\n"
        default: throw CocoaError(.featureUnsupported)
        }
    }

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        guard environment["GIT_NO_LAZY_FETCH"] == "1" else {
            throw CocoaError(.featureUnsupported)
        }
        return try await runGit(arguments: arguments, in: directory)
    }
}
