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
import Observation

@MainActor
@Observable
final class GitSettingsViewModel {
    var settings = GlobalGitSettings.empty
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var savedSettings = GlobalGitSettings.empty
    private(set) var statusMessage: String?
    var errorMessage: String?
    var showingError = false

    @ObservationIgnored private let service: GitStatusService
    @ObservationIgnored private let fileManager: FileManager

    init(
        service: GitStatusService = .shared,
        fileManager: FileManager = .default
    ) {
        self.service = service
        self.fileManager = fileManager
    }

    var canSave: Bool {
        settings != savedSettings && !isLoading && !isSaving
    }

    func load() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await service.loadGlobalGitSettings()
            settings = loaded
            savedSettings = loaded
        } catch {
            present(error)
        }
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }

        do {
            try await service.updateGlobalGitSettings(settings)
            savedSettings = settings
            statusMessage = "Global Git settings saved."
        } catch {
            present(error)
        }
    }

    func chooseGlobalIgnoreFile() {
        let panel = NSSavePanel()
        panel.title = "Choose Global Git Ignore File"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = expandedURL(for: settings.excludesFilePath).lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.excludesFilePath = abbreviatedPath(for: url)
        statusMessage = nil
    }

    func useDefaultGlobalIgnoreFile() {
        settings.excludesFilePath = "~/.config/git/ignore"
        statusMessage = nil
    }

    func openGlobalIgnoreFile() {
        let trimmedPath = settings.excludesFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            present(GitError.commandFailed("Choose a global ignore file first."))
            return
        }
        openFile(at: expandedURL(for: trimmedPath))
    }

    func openGlobalGitConfig() {
        openFile(at: fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig"))
    }

    private func openFile(at url: URL) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(atPath: url.path, contents: Data()) else {
                    throw GitError.commandFailed("Could not create \(url.path).")
                }
            }
            guard NSWorkspace.shared.open(url) else {
                throw GitError.commandFailed("Could not open \(url.path).")
            }
        } catch {
            present(error)
        }
    }

    private func expandedURL(for path: String) -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    private func abbreviatedPath(for url: URL) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        guard url.path == homePath || url.path.hasPrefix(homePath + "/") else {
            return url.path
        }
        return "~" + url.path.dropFirst(homePath.count)
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
