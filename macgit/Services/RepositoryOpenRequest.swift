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

nonisolated enum RepositoryOpenRequest {
    static func recognizes(_ url: URL) -> Bool {
        url.scheme == "macgit" && url.host == "open-repository"
    }

    static func repositoryURL(from url: URL) throws -> URL {
        guard recognizes(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 1,
              items[0].name == "path", let path = items[0].value,
              path.hasPrefix("/"), !path.contains("\0") else {
            throw RepositoryOpenError.message("Invalid repository URL. Expected an absolute folder path.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func url(for repositoryURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "macgit"
        components.host = "open-repository"
        components.queryItems = [URLQueryItem(name: "path", value: repositoryURL.path)]
        return components.url!
    }

    static func directory(arguments: [String], currentDirectory: String) throws -> URL {
        var paths = arguments
        if paths.first == "--" { paths.removeFirst() }
        else if paths.first?.hasPrefix("-") == true {
            throw RepositoryOpenError.message("Unknown option. Usage: commit [<folder>] (use -- before a path starting with '-').")
        }
        guard paths.count <= 1 else {
            throw RepositoryOpenError.message("Usage: commit [<folder>]")
        }
        let path = paths.first ?? "."
        guard !path.isEmpty, !path.contains("\0") else {
            throw RepositoryOpenError.message("Expected a folder path.")
        }
        return URL(fileURLWithPath: path, isDirectory: true,
                   relativeTo: URL(fileURLWithPath: currentDirectory, isDirectory: true)).standardizedFileURL
    }
}
