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

actor RepositoryPathResolver {
    func root(at directory: URL, runtime: GitRuntimeManager = .shared) async throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RepositoryOpenError.message("'\(directory.path)' is not an existing folder.")
        }
        guard FileManager.default.isReadableFile(atPath: directory.path) else {
            throw RepositoryOpenError.message("Cannot read '\(directory.path)'.")
        }
        let executable = try await runtime.executableURL()
        var environment = await runtime.environment(
            for: executable, inheriting: ProcessInfo.processInfo.environment
        )
        // The explicit folder owns discovery, even inside a Git hook or shell with Git overrides.
        for key in environment.keys where key.hasPrefix("GIT_") {
            if !["GIT_EXEC_PATH", "GIT_CONFIG_SYSTEM", "GIT_TEMPLATE_DIR"].contains(key) {
                environment.removeValue(forKey: key)
            }
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-C", directory.path, "rev-parse", "--show-toplevel"]
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        // Keep Git's diagnostic (permissions, unsafe ownership, corrupt metadata) for the caller.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorFile.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardError = errorFile
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostic = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw RepositoryOpenError.message(
                "Cannot open '\(directory.path)' as a Git working tree. " + diagnostic.trimmingCharacters(in: .newlines)
            )
        }
        guard var path = String(data: data, encoding: .utf8), path.hasSuffix("\n") else {
            throw RepositoryOpenError.message("Git returned an invalid repository path.")
        }
        path.removeLast() // Preserve spaces and newlines that belong to the filename.
        guard path.hasPrefix("/") else {
            throw RepositoryOpenError.message("Git returned an invalid repository path.")
        }
        return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }
}
