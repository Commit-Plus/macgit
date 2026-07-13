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

enum GitSubmoduleParser {
    private struct Configuration {
        var name: String
        var path: String?
        var url: String?
        var branch: String?
    }

    private struct StatusRecord {
        var commit: String
        var state: GitSubmoduleState
    }

    static func parse(config: String, index: String, status: String) throws -> [GitSubmoduleEntry] {
        let configurations = parseConfigurations(config)
        let recordedCommits = parseIndexGitlinks(index)
        let statuses = parseStatuses(status)

        return configurations.values.compactMap { configuration in
            guard let configuredPath = configuration.path,
                  let url = configuration.url else {
                return nil
            }

            let path = normalizePath(configuredPath)
            let statusRecord = statuses[path]
            let state = statusRecord?.state ?? .missing
            let checkedOutCommit = state == .uninitialized ? nil : statusRecord?.commit

            return GitSubmoduleEntry(
                name: configuration.name,
                path: path,
                url: url,
                branch: configuration.branch,
                recordedCommit: recordedCommits[path],
                checkedOutCommit: checkedOutCommit,
                state: state
            )
        }
        .sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private static func parseConfigurations(_ output: String) -> [String: Configuration] {
        var configurations: [String: Configuration] = [:]

        for rawRecord in output.split(separator: "\0", omittingEmptySubsequences: true) {
            let record = String(rawRecord)
            guard let separator = record.firstIndex(of: "\n") else { continue }

            let key = String(record[..<separator])
            let value = String(record[record.index(after: separator)...])
            guard let parsedKey = parseConfigurationKey(key) else { continue }

            var configuration = configurations[parsedKey.name]
                ?? Configuration(name: parsedKey.name)
            switch parsedKey.field {
            case "path":
                configuration.path = value
            case "url":
                configuration.url = value
            case "branch":
                configuration.branch = value
            default:
                break
            }
            configurations[parsedKey.name] = configuration
        }

        return configurations
    }

    private static func parseConfigurationKey(_ key: String) -> (name: String, field: String)? {
        let prefix = "submodule."
        guard key.hasPrefix(prefix) else { return nil }

        let body = String(key.dropFirst(prefix.count))
        for field in ["path", "url", "branch"] {
            let suffix = ".\(field)"
            guard body.hasSuffix(suffix) else { continue }
            let name = String(body.dropLast(suffix.count))
            guard !name.isEmpty else { return nil }
            return (name, field)
        }
        return nil
    }

    private static func parseIndexGitlinks(_ output: String) -> [String: String] {
        var commitsByPath: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let metadata = line[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            guard metadata.count >= 2, metadata[0] == "160000" else { continue }
            let path = normalizePath(String(line[line.index(after: tab)...]))
            commitsByPath[path] = String(metadata[1])
        }

        return commitsByPath
    }

    private static func parseStatuses(_ output: String) -> [String: StatusRecord] {
        var statusesByPath: [String: StatusRecord] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefix = line.first,
                  let state = state(for: prefix) else {
                continue
            }

            let payload = line.dropFirst()
            guard let commitSeparator = payload.firstIndex(of: " ") else { continue }
            let commit = String(payload[..<commitSeparator])
            var pathAndDescription = String(payload[payload.index(after: commitSeparator)...])
            if let descriptionRange = pathAndDescription.range(of: " (", options: .backwards) {
                pathAndDescription = String(pathAndDescription[..<descriptionRange.lowerBound])
            }
            let path = normalizePath(pathAndDescription)
            guard !path.isEmpty else { continue }
            statusesByPath[path] = StatusRecord(commit: commit, state: state)
        }

        return statusesByPath
    }

    private static func state(for prefix: Character) -> GitSubmoduleState? {
        switch prefix {
        case " ": .clean
        case "-": .uninitialized
        case "+": .newCommits
        case "U": .conflict
        default: nil
        }
    }

    private static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }
}
