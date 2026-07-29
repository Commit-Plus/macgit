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

import Combine
import Foundation

@MainActor
final class IntegrationSettingsStore: ObservableObject {
    static let shared = IntegrationSettingsStore()

    @Published var preferredTerminalBundleIdentifier: String? {
        didSet { save(preferredTerminalBundleIdentifier, forKey: Self.terminalKey) }
    }
    @Published var preferredDiffBundleIdentifier: String? {
        didSet { save(preferredDiffBundleIdentifier, forKey: Self.diffKey) }
    }
    @Published var preferredMergeBundleIdentifier: String? {
        didSet { save(preferredMergeBundleIdentifier, forKey: Self.mergeKey) }
    }
    @Published private(set) var refreshID = UUID()

    private static let terminalKey = "integration.preferredTerminal"
    private static let diffKey = "integration.preferredDiffTool"
    private static let mergeKey = "integration.preferredMergeTool"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        preferredTerminalBundleIdentifier = userDefaults.string(forKey: Self.terminalKey)
        preferredDiffBundleIdentifier = userDefaults.string(forKey: Self.diffKey)
        preferredMergeBundleIdentifier = userDefaults.string(forKey: Self.mergeKey)
    }

    func refreshApplications() {
        refreshID = UUID()
        validateSelections()
    }

    func validateSelections() {
        preferredTerminalBundleIdentifier = validatedSelection(
            preferredTerminalBundleIdentifier,
            role: .terminal
        )
        preferredDiffBundleIdentifier = validatedSelection(
            preferredDiffBundleIdentifier,
            role: .diff
        )
        preferredMergeBundleIdentifier = validatedSelection(
            preferredMergeBundleIdentifier,
            role: .merge
        )
    }

    func selectedApplication(for role: IntegrationRole) -> IntegrationApplication? {
        let bundleIdentifier = selection(for: role)
        let availableApplications = IntegrationApplicationCatalog.availableApplications(for: role)

        if let bundleIdentifier,
           let selectedApplication = availableApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier
           }) {
            return selectedApplication
        }

        return role == .terminal ? availableApplications.first : nil
    }

    func openTerminal(at directoryURL: URL) async throws {
        guard let terminal = selectedApplication(for: .terminal) else {
            throw IntegrationLaunchError.noApplicationAvailable("Terminal")
        }
        try await IntegrationApplicationLauncher.launch(terminal, opening: directoryURL)
    }

    func test(role: IntegrationRole) async throws {
        guard let application = selectedApplication(for: role) else {
            throw IntegrationLaunchError.noApplicationAvailable(role.rawValue)
        }
        try await IntegrationApplicationLauncher.launch(application)
    }

    func restoreDefaults() {
        preferredTerminalBundleIdentifier = nil
        preferredDiffBundleIdentifier = nil
        preferredMergeBundleIdentifier = nil
        refreshApplications()
    }

    private func selection(for role: IntegrationRole) -> String? {
        switch role {
        case .editor:
            nil
        case .terminal:
            preferredTerminalBundleIdentifier
        case .diff:
            preferredDiffBundleIdentifier
        case .merge:
            preferredMergeBundleIdentifier
        }
    }

    private func validatedSelection(_ selection: String?, role: IntegrationRole) -> String? {
        guard let selection else { return nil }
        return IntegrationApplicationCatalog.availableApplications(for: role).contains {
            $0.bundleIdentifier == selection
        } ? selection : nil
    }

    private func save(_ selection: String?, forKey key: String) {
        if let selection {
            userDefaults.set(selection, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
