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

enum AIDataProcessing: Sendable {
    case onDevice
    case cloud
}

enum AIProviderBilling: Equatable, Sendable {
    case none
    case bringYourOwnKey
    case commitPlus

    var requiresProAccess: Bool {
        self == .commitPlus
    }
}

struct AIProviderDescriptor: Identifiable, Sendable {
    let id: AIProviderID
    let displayName: String
    let systemImage: String
    let detail: String
    let dataProcessing: AIDataProcessing
    let billing: AIProviderBilling
    let requiresProToConfigureAPIKey: Bool
    let defaultModel: String?
    let inputCharacterBudget: Int
    let isImplemented: Bool
}

enum AIProviderAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(String)
    case comingSoon

    var isAvailable: Bool {
        self == .available
    }

    var detail: String {
        switch self {
        case .checking:
            "Checking availability…"
        case .available:
            "Available"
        case .unavailable(let reason):
            reason
        case .comingSoon:
            "Coming soon"
        }
    }
}
