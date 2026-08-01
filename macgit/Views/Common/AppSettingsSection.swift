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

enum AppSettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case git
    case accounts
    case integrations
    case aiProviders
    case update
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .git: "Git"
        case .accounts: "Account"
        case .integrations: "Integrations"
        case .aiProviders: "AI Providers"
        case .update: "Update"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .git: "point.3.connected.trianglepath.dotted"
        case .accounts: "person.crop.circle"
        case .integrations: "puzzlepiece.extension"
        case .aiProviders: "sparkles"
        case .update: "arrow.triangle.2.circlepath"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    var detail: String {
        switch self {
        case .general:
            "Configure the default behavior of Commit+."
        case .appearance:
            "Customize how Commit+ looks and presents repository information."
        case .git:
            "Manage global Git behavior and command preferences."
        case .accounts:
            "Manage your Commit+ account and Git provider connections."
        case .integrations:
            "Connect Commit+ with external tools and services."
        case .aiProviders:
            "Configure AI providers for commit-message generation."
        case .update:
            "View version information and check for Commit+ updates."
        case .advanced:
            "Configure advanced options for troubleshooting and power users."
        }
    }
}
