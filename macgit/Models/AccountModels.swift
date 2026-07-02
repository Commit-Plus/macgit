//
//  AccountModels.swift
//  macgit
//

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

enum AccountPlan: String, Codable, Equatable {
    case free
    case pro
}

enum EntitlementAccess: String, Codable, Equatable {
    case active
    case inactive
}

enum BillingStatus: String, Codable, Equatable {
    case none
    case trialing
    case active
    case pastDue = "past_due"
    case canceled
}

enum EntitlementSource: String, Codable, Equatable {
    case adminTest = "admin_test"
    case polar
}

struct AccountEntitlement: Codable, Equatable {
    var plan: AccountPlan
    var access: EntitlementAccess
    var billingStatus: BillingStatus
    var source: EntitlementSource?
    var currentPeriodEnd: Date?
    var cancelAtPeriodEnd: Bool

    static let free = AccountEntitlement(
        plan: .free,
        access: .inactive,
        billingStatus: .none
    )

    init(
        plan: AccountPlan,
        access: EntitlementAccess,
        billingStatus: BillingStatus,
        source: EntitlementSource? = nil,
        currentPeriodEnd: Date? = nil,
        cancelAtPeriodEnd: Bool = false
    ) {
        self.plan = plan
        self.access = access
        self.billingStatus = billingStatus
        self.source = source
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    var hasProAccess: Bool {
        plan == .pro && access == .active
    }
}

struct AccountSnapshot: Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    let providerIDs: [String]

    var displayLabel: String {
        displayName ?? email ?? "Commit+ Account"
    }
}

enum FirebaseBootstrapStatus: Equatable {
    case configured
    case missingConfiguration
    case failed(String)
}
