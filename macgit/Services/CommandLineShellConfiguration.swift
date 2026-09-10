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
import Darwin

struct CommandLineShellConfiguration {
    let home: URL
    let shell: String
    let zshDirectory: URL?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         shell: String? = nil,
         zshDirectory: URL? = ProcessInfo.processInfo.environment["ZDOTDIR"].map { URL(fileURLWithPath: $0) }) {
        self.home = home
        self.shell = shell ?? getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        self.zshDirectory = zshDirectory
    }

    var command: String {
        shell.hasSuffix("/fish")
            ? "set -gx PATH \"$HOME/.local/bin\" $PATH"
            : "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    var files: [URL] {
        switch URL(fileURLWithPath: shell).lastPathComponent {
        case "zsh":
            return [(zshDirectory ?? home).appendingPathComponent(".zshrc")]
        case "bash":
            let loginNames = [".bash_profile", ".bash_login", ".profile"]
            let login = loginNames.first { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) } ?? ".bash_profile"
            return [home.appendingPathComponent(login), home.appendingPathComponent(".bashrc")]
        case "fish":
            return [home.appendingPathComponent(".config/fish/config.fish")]
        default:
            return []
        }
    }

    var isConfigured: Bool {
        !files.isEmpty && files.allSatisfy { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return containsConfiguration(content)
        }
    }

    private func containsConfiguration(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces) == command
        }
    }

    func configure() throws {
        guard !files.isEmpty else {
            throw RepositoryOpenError.message("Automatic PATH setup is not supported for \(shell). Add ~/.local/bin to your shell's PATH manually.")
        }
        let manager = FileManager.default
        for file in files {
            let exists = manager.fileExists(atPath: file.path)
            let content = exists ? try String(contentsOf: file, encoding: .utf8) : ""
            if containsConfiguration(content) { continue }
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if exists {
                let backup = file.appendingPathExtension("commitplus-backup-\(UUID().uuidString)")
                let descriptor = open(backup.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                let backupHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? backupHandle.close() }
                try backupHandle.write(contentsOf: Data(content.utf8))
            } else {
                try Data().write(to: file, options: .withoutOverwriting)
            }
            // Append through the existing file, preserving shell-config symlinks and permissions.
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n# Commit+ command line tools\n\(command)\n".utf8))
        }
    }
}
