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

import AppKit
import Foundation
import MachO

@main
struct CommitCommand {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print("Usage: commit [<folder>]\nOpen the current folder's Git repository in Commit+. This does not create a commit.")
            return
        }
        do {
            let directory = try RepositoryOpenRequest.directory(
                arguments: arguments, currentDirectory: FileManager.default.currentDirectoryPath
            )
            // Resolve the installed symlink to target this helper's app, including when several builds exist.
            var capacity: UInt32 = 0
            _NSGetExecutablePath(nil, &capacity)
            var buffer = [CChar](repeating: 0, count: Int(capacity))
            guard _NSGetExecutablePath(&buffer, &capacity) == 0 else {
                throw RepositoryOpenError.message("Cannot locate the installed command.")
            }
            let executable = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
            let application = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard application.pathExtension == "app", let bundle = Bundle(url: application),
                  let identifier = bundle.bundleIdentifier else {
                throw RepositoryOpenError.message("Cannot locate Commit+. Reinstall the command from Settings > General.")
            }
            let live = GitRuntimeConfiguration.live()
            let configuration = GitRuntimeConfiguration(
                applicationSupportDirectory: live.applicationSupportDirectory,
                candidateSystemGitURLs: live.candidateSystemGitURLs,
                manifest: live.manifest,
                preferenceDefaults: UserDefaults(suiteName: identifier) ?? .standard,
                preferenceKey: live.preferenceKey
            )
            let root = try await RepositoryPathResolver().root(at: directory, runtime: GitRuntimeManager(configuration: configuration))
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            _ = try await NSWorkspace.shared.open(
                [RepositoryOpenRequest.url(for: root)], withApplicationAt: application, configuration: options
            )
        } catch {
            FileHandle.standardError.write(Data("commit: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
