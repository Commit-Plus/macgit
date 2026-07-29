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

enum AdvancedDiagnosticsService {
    static var applicationSupportDirectoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Commit+", isDirectory: true)
    }

    @MainActor
    static func report(
        runtimeStatus: GitRuntimeStatus,
        cloudFeaturesAvailable: Bool,
        isSignedIn: Bool,
        settingsSyncStatus: String,
        providerAccounts: [GitProviderAccount],
        integrationSettings: IntegrationSettingsStore
    ) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "Unknown"
        let runtime = runtimeStatus.activeRuntime
        let providerSummary = Dictionary(grouping: providerAccounts, by: \.provider)
            .map { "\($0.key.displayName): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")

        return """
        Commit+ Diagnostic Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        Application
        Version: \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)

        Git Runtime
        Preference: \(runtimeStatus.preference.title)
        Active version: \(runtime?.version ?? "Unavailable")
        Active executable: \(abbreviatedHomePath(runtime?.executableURL.path ?? "Unavailable"))
        System Git available: \(runtimeStatus.systemRuntime == nil ? "No" : "Yes")
        Embedded Git installed: \(runtimeStatus.embeddedRuntime == nil ? "No" : "Yes")

        Accounts
        Firebase configured: \(cloudFeaturesAvailable ? "Yes" : "No")
        Commit+ account signed in: \(isSignedIn ? "Yes" : "No")
        Settings sync: \(settingsSyncStatus)
        Git provider accounts: \(providerSummary.isEmpty ? "None" : providerSummary)

        Integrations
        Terminal: \(integrationSettings.selectedApplication(for: .terminal)?.displayName ?? "Unavailable")
        Diff tool: \(integrationSettings.selectedApplication(for: .diff)?.displayName ?? "Built-in Commit+")
        Merge tool: \(integrationSettings.selectedApplication(for: .merge)?.displayName ?? "Built-in Commit+")

        Privacy
        Credentials, tokens, repository paths, Git output, and account identifiers are excluded.
        """
    }

    private static var architecture: String {
#if arch(arm64)
        "Apple Silicon (arm64)"
#elseif arch(x86_64)
        "Intel (x86_64)"
#else
        "Unknown"
#endif
    }

    private static func abbreviatedHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
