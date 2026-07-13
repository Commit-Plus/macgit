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

struct SubmoduleAddRequest: Equatable, Sendable {
    let repository: String
    let path: String
    let branch: String?
    let initializeAfterAdd: Bool
    let shallow: Bool
}

enum SubmoduleUpdateMode: Equatable, Sendable {
    case recordedCommit
    case remoteCheckout
}

enum SubmoduleRequestValidationError: LocalizedError, Equatable {
    case emptyRepository
    case emptyPath
    case absolutePath
    case pathOutsideRepository
    case duplicatePath(String)

    var errorDescription: String? {
        switch self {
        case .emptyRepository:
            "Enter a submodule repository URL."
        case .emptyPath:
            "Choose a path inside this repository."
        case .absolutePath:
            "The submodule path must be relative to this repository."
        case .pathOutsideRepository:
            "The submodule path must stay inside this repository."
        case let .duplicatePath(path):
            "A submodule is already configured at \(path)."
        }
    }
}

enum SubmoduleRequestValidator {
    static func validate(
        addRequest request: SubmoduleAddRequest,
        in repositoryURL: URL
    ) throws -> SubmoduleAddRequest {
        let repository = request.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw SubmoduleRequestValidationError.emptyRepository
        }

        let rawPath = request.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !rawPath.isEmpty else {
            throw SubmoduleRequestValidationError.emptyPath
        }
        guard !NSString(string: rawPath).isAbsolutePath else {
            throw SubmoduleRequestValidationError.absolutePath
        }

        let lexicalRepositoryURL = repositoryURL.standardizedFileURL
        let lexicalCandidateURL = lexicalRepositoryURL
            .appendingPathComponent(rawPath)
            .standardizedFileURL
        guard lexicalCandidateURL != lexicalRepositoryURL,
              lexicalCandidateURL.pathComponents.starts(with: lexicalRepositoryURL.pathComponents) else {
            throw SubmoduleRequestValidationError.pathOutsideRepository
        }

        let relativeComponents = lexicalCandidateURL.pathComponents
            .dropFirst(lexicalRepositoryURL.pathComponents.count)
        let path = relativeComponents.joined(separator: "/")
        let standardizedRepositoryURL = lexicalRepositoryURL.resolvingSymlinksInPath()
        let candidateURL = relativeComponents.reduce(standardizedRepositoryURL) { currentURL, component in
            currentURL
                .appendingPathComponent(component)
                .resolvingSymlinksInPath()
        }
        guard candidateURL != standardizedRepositoryURL,
              candidateURL.pathComponents.starts(with: standardizedRepositoryURL.pathComponents) else {
            throw SubmoduleRequestValidationError.pathOutsideRepository
        }

        if configuredSubmodulePaths(in: repositoryURL).contains(path) {
            throw SubmoduleRequestValidationError.duplicatePath(path)
        }

        let branch = request.branch?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SubmoduleAddRequest(
            repository: repository,
            path: path.replacingOccurrences(of: "\\", with: "/"),
            branch: branch?.isEmpty == true ? nil : branch,
            initializeAfterAdd: request.initializeAfterAdd,
            shallow: request.shallow
        )
    }

    private static func configuredSubmodulePaths(in repositoryURL: URL) -> Set<String> {
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
}
