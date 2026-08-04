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

struct FeatureAccessResolver {
    let policy: FeatureAccessPolicy

    func decision(
        for feature: PlanFeature,
        entitlement: AccountEntitlement,
        repositoryVisibility: RepositoryVisibility? = nil
    ) -> FeatureAccessDecision {
        let featureRule = policy.rule(for: feature)
        guard featureRule.enabled else { return .denied(.featureDisabled) }

        let hasProAccess = entitlement.hasProAccess
        let planRule = hasProAccess ? featureRule.pro : featureRule.free
        guard planRule.enabled else {
            return .denied(hasProAccess ? .featureDisabled : .requiresPro)
        }

        guard let scope = planRule.repositoryScope else { return .allowed }
        guard let repositoryVisibility else {
            return .denied(.repositoryVisibilityUnavailable)
        }

        switch (scope, repositoryVisibility) {
        case (.all, _), (.public, .public), (.publicOrLocal, .public), (.publicOrLocal, .local):
            return .allowed
        case (_, .unknown):
            return .denied(.repositoryVisibilityUnavailable)
        default:
            return .denied(hasProAccess ? .repositoryScopeNotAllowed : .requiresPro)
        }
    }
}
