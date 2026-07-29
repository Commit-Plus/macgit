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

enum IntegrationApplicationLauncher {
    @MainActor
    static func launch(
        _ application: IntegrationApplication,
        opening itemURL: URL? = nil,
        workspace: NSWorkspace = .shared
    ) async throws {
        if let itemURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                workspace.open(
                    [itemURL],
                    withApplicationAt: application.applicationURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } else if !workspace.open(application.applicationURL) {
            throw IntegrationLaunchError.noApplicationAvailable(application.displayName)
        }
    }

    @MainActor
    static func launchDiff(
        _ application: IntegrationApplication,
        beforeURL: URL,
        afterURL: URL
    ) throws {
        let command = try diffCommand(
            for: application,
            beforeURL: beforeURL,
            afterURL: afterURL
        )
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @MainActor
    static func launchMerge(
        _ application: IntegrationApplication,
        baseURL: URL,
        currentURL: URL,
        incomingURL: URL,
        outputURL: URL
    ) async throws {
        let command = try mergeCommand(
            for: application,
            baseURL: baseURL,
            currentURL: currentURL,
            incomingURL: incomingURL,
            outputURL: outputURL
        )
        try await runAndWait(
            executableURL: command.executableURL,
            arguments: command.arguments,
            applicationName: application.displayName
        )
    }

    private static func diffCommand(
        for application: IntegrationApplication,
        beforeURL: URL,
        afterURL: URL
    ) throws -> (executableURL: URL, arguments: [String]) {
        let executableURL: URL
        let arguments: [String]

        switch application.bundleIdentifier {
        case "com.apple.FileMerge":
            executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
            arguments = [beforeURL.path, afterURL.path]
        case "com.kaleidoscope.Kaleidoscope", "com.blackpixel.kaleidoscope":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/ksdiff", "Contents/Resources/ksdiff"]
            )
            arguments = [beforeURL.path, afterURL.path]
        case "com.scootersoftware.BeyondCompare":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/bcomp", "Contents/MacOS/BCompare"]
            )
            arguments = [beforeURL.path, afterURL.path]
        case "com.araxis.merge":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Utilities/compare", "Contents/MacOS/Araxis Merge"]
            )
            arguments = [beforeURL.path, afterURL.path]
        case "com.perforce.p4merge":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/p4merge"]
            )
            arguments = [beforeURL.path, afterURL.path]
        case "com.microsoft.VSCode":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Resources/app/bin/code"]
            )
            arguments = ["--diff", beforeURL.path, afterURL.path]
        case "com.todesktop.230313mzl4w4u92":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Resources/app/bin/cursor"]
            )
            arguments = ["--diff", beforeURL.path, afterURL.path]
        default:
            throw IntegrationLaunchError.unsupportedDiffApplication(application.displayName)
        }

        return (executableURL, arguments)
    }

    private static func mergeCommand(
        for application: IntegrationApplication,
        baseURL: URL,
        currentURL: URL,
        incomingURL: URL,
        outputURL: URL
    ) throws -> (executableURL: URL, arguments: [String]) {
        let executableURL: URL
        let arguments: [String]

        switch application.bundleIdentifier {
        case "com.apple.FileMerge":
            executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
            arguments = [
                currentURL.path,
                incomingURL.path,
                "-ancestor", baseURL.path,
                "-merge", outputURL.path
            ]
        case "com.kaleidoscope.Kaleidoscope", "com.blackpixel.kaleidoscope":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/ksdiff", "Contents/Resources/ksdiff"]
            )
            arguments = [
                "--merge",
                "--output", outputURL.path,
                "--base", baseURL.path,
                currentURL.path,
                incomingURL.path
            ]
        case "com.scootersoftware.BeyondCompare":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/bcomp", "Contents/MacOS/BCompare"]
            )
            arguments = [
                currentURL.path,
                incomingURL.path,
                baseURL.path,
                "-mergeoutput=\(outputURL.path)"
            ]
        case "com.araxis.merge":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Utilities/compare", "Contents/MacOS/Araxis Merge"]
            )
            arguments = [
                "-wait", "-merge", "-3", "-a1",
                baseURL.path,
                currentURL.path,
                incomingURL.path,
                outputURL.path
            ]
        case "com.perforce.p4merge":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/MacOS/p4merge"]
            )
            arguments = [
                baseURL.path,
                incomingURL.path,
                currentURL.path,
                outputURL.path
            ]
        case "com.microsoft.VSCode":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Resources/app/bin/code"]
            )
            arguments = [
                "--wait", "--merge",
                incomingURL.path,
                currentURL.path,
                baseURL.path,
                outputURL.path
            ]
        case "com.todesktop.230313mzl4w4u92":
            executableURL = try firstExecutable(
                in: application,
                relativePaths: ["Contents/Resources/app/bin/cursor"]
            )
            arguments = [
                "--wait", "--merge",
                incomingURL.path,
                currentURL.path,
                baseURL.path,
                outputURL.path
            ]
        default:
            throw IntegrationLaunchError.unsupportedMergeApplication(application.displayName)
        }

        return (executableURL, arguments)
    }

    private static func firstExecutable(
        in application: IntegrationApplication,
        relativePaths: [String]
    ) throws -> URL {
        for relativePath in relativePaths {
            let candidate = application.applicationURL.appendingPathComponent(relativePath)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw IntegrationLaunchError.missingCommandLineTool(application.displayName)
    }

    private static func runAndWait(
        executableURL: URL,
        arguments: [String],
        applicationName: String
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: IntegrationLaunchError.externalToolFailed(applicationName)
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
