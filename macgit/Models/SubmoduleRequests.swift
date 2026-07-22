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
    case invalidLocalRepository
    case emptyPath
    case absolutePath
    case pathOutsideRepository
    case duplicatePath(String)

    var errorDescription: String? {
        switch self {
        case .emptyRepository:
            "Enter a submodule repository URL."
        case .invalidLocalRepository:
            "The selected local folder is not a Git repository."
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
        if NSString(string: repository).isAbsolutePath {
            let localRepositoryURL = URL(fileURLWithPath: repository).standardizedFileURL
            guard FileManager.default.fileExists(
                atPath: localRepositoryURL.appendingPathComponent(".git").path
            ) else {
                throw SubmoduleRequestValidationError.invalidLocalRepository
            }
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

        if GitStatusService.shared.configuredSubmodulePaths(in: repositoryURL).contains(path) {
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

    static func relativePath(for url: URL, in repositoryURL: URL) -> String? {
        let root = repositoryURL.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate != root,
              candidate.pathComponents.starts(with: root.pathComponents) else {
            return nil
        }

        return candidate.pathComponents
            .dropFirst(root.pathComponents.count)
            .joined(separator: "/")
    }

}
