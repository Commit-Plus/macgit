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

extension GitStatusService {
    func addSubmodule(
        _ request: SubmoduleAddRequest,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        let request = try SubmoduleRequestValidator.validate(addRequest: request, in: repositoryURL)
        let injection = try await credentialInjection(
            for: request.repository,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        defer { injection?.cleanup() }

        var arguments = ["submodule", "add"]
        if let branch = request.branch {
            arguments += ["--branch", branch]
        }
        if request.shallow {
            arguments += ["--depth", "1"]
        }
        arguments += ["--", request.repository, request.path]
        _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)

        if !request.initializeAfterAdd {
            _ = try await runGit(
                arguments: ["submodule", "deinit", "-f", "--", request.path],
                in: repositoryURL
            )
        }
        notifySubmoduleMutationSucceeded(in: repositoryURL)
    }

    func initializeSubmodule(
        path: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        let injection = try await submoduleCredentialInjection(
            path: path,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(
            arguments: ["submodule", "update", "--init", "--", path],
            in: repositoryURL,
            injection: injection
        )
        notifySubmoduleMutationSucceeded(in: repositoryURL)
    }

    func updateSubmodule(
        path: String,
        mode: SubmoduleUpdateMode,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        let injection = try await submoduleCredentialInjection(
            path: path,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )
        defer { injection?.cleanup() }
        let arguments: [String]
        switch mode {
        case .recordedCommit:
            arguments = ["submodule", "update", "--checkout", "--", path]
        case .remoteCheckout:
            arguments = ["submodule", "update", "--remote", "--checkout", "--", path]
        }
        _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
        notifySubmoduleMutationSucceeded(in: repositoryURL)
    }

    func synchronizeSubmoduleURL(path: String, in repositoryURL: URL) async throws {
        _ = try await runGit(
            arguments: ["submodule", "sync", "--", path],
            in: repositoryURL
        )
        notifySubmoduleMutationSucceeded(in: repositoryURL)
    }

    nonisolated func configuredSubmodulePaths(in repositoryURL: URL) -> Set<String> {
        let gitmodulesURL = repositoryURL.appendingPathComponent(".gitmodules")
        guard FileManager.default.fileExists(atPath: gitmodulesURL.path) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "config",
            "--null",
            "--file", gitmodulesURL.path,
            "--get-regexp", #"^submodule\..*\.path$"#
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        return Set(data.split(separator: 0).compactMap { record in
            guard let separator = record.firstIndex(of: 0x0A) else { return nil }
            let valueData = record[record.index(after: separator)...]
            guard let value = String(data: valueData, encoding: .utf8), !value.isEmpty else {
                return nil
            }

            let normalizedValue = value.replacingOccurrences(of: "\\", with: "/")
            return NSString(string: normalizedValue).standardizingPath
        })
    }

    func submodules(in repositoryURL: URL) async throws -> [GitSubmoduleEntry] {
        let gitmodulesURL = repositoryURL.appendingPathComponent(".gitmodules", isDirectory: false)
        guard FileManager.default.fileExists(atPath: gitmodulesURL.path) else {
            return []
        }

        let config = try await runGit(
            arguments: [
                "config",
                "-z",
                "--file",
                ".gitmodules",
                "--list"
            ],
            in: repositoryURL
        )
        let index = try await runGit(arguments: ["ls-files", "--stage"], in: repositoryURL)
        let status = try await runGit(
            arguments: ["submodule", "status", "--recursive"],
            in: repositoryURL
        )
        let parsed = try GitSubmoduleParser.parse(config: config, index: index, status: status)

        var entries: [GitSubmoduleEntry] = []
        entries.reserveCapacity(parsed.count)
        for entry in parsed {
            entries.append(try await enrichSubmodule(entry, in: repositoryURL))
        }
        return entries
    }

    private func enrichSubmodule(
        _ entry: GitSubmoduleEntry,
        in repositoryURL: URL
    ) async throws -> GitSubmoduleEntry {
        let checkoutURL = repositoryURL.appendingPathComponent(entry.path, isDirectory: true)
        var isDirectory: ObjCBool = false
        let checkoutExists = FileManager.default.fileExists(
            atPath: checkoutURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        if entry.state == .uninitialized {
            let localURL = try? await runGit(
                arguments: ["config", "--get", "submodule.\(entry.name).url"],
                in: repositoryURL
            )
            let state: GitSubmoduleState = !checkoutExists && localURL != nil
                ? .missing
                : .uninitialized
            return replacing(entry, checkedOutCommit: nil, state: state)
        }

        guard checkoutExists else {
            return replacing(entry, checkedOutCommit: nil, state: .missing)
        }

        let checkedOutCommit = try await runGit(
            arguments: ["rev-parse", "HEAD"],
            in: checkoutURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let workingTreeStatus = try await runGit(
            arguments: ["status", "--porcelain"],
            in: checkoutURL
        )
        let state = entry.state == .clean && !workingTreeStatus.isEmpty
            ? GitSubmoduleState.modified
            : entry.state

        return replacing(entry, checkedOutCommit: checkedOutCommit, state: state)
    }

    private func replacing(
        _ entry: GitSubmoduleEntry,
        checkedOutCommit: String?,
        state: GitSubmoduleState
    ) -> GitSubmoduleEntry {
        GitSubmoduleEntry(
            name: entry.name,
            path: entry.path,
            url: entry.url,
            branch: entry.branch,
            recordedCommit: entry.recordedCommit,
            checkedOutCommit: checkedOutCommit,
            state: state
        )
    }

    private func submoduleCredentialInjection(
        path: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws -> GitCredentialInjection? {
        guard credentialResolver != nil else { return nil }
        let pathOutput = try await runGit(
            arguments: ["config", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.path$"#],
            in: repositoryURL
        )
        guard let key = pathOutput.split(separator: "\n").compactMap({ line -> String? in
            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2, fields[1] == Substring(path) else { return nil }
            return String(fields[0].dropLast(".path".count))
        }).first else {
            return nil
        }
        let remoteURL = try await runGit(
            arguments: ["config", "--file", ".gitmodules", "--get", "\(key).url"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return try await credentialInjection(
            for: remoteURL,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
    }

    private func notifySubmoduleMutationSucceeded(in repositoryURL: URL) {
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }
}
