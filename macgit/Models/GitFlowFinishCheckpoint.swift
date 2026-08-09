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

struct GitFlowFinishCheckpoint: Codable, Equatable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    enum Phase: String, Codable {
        case primaryMerge
        case secondaryMerge
        case topicRebase
        case topicFastForward
    }

    var plan: GitFlowFinishPlan
    var sourceTip: String
    var targetResults: [GitFlowFinishTargetResult]
    var createdTagName: String?
    var phase: Phase
    var rewrittenSourceTip: String?
    var targetTipBeforeIntegration: String?

    init(
        schemaVersion: Int = GitFlowFinishCheckpoint.supportedSchemaVersion,
        plan: GitFlowFinishPlan,
        sourceTip: String,
        targetResults: [GitFlowFinishTargetResult],
        createdTagName: String?,
        phase: Phase,
        rewrittenSourceTip: String? = nil,
        targetTipBeforeIntegration: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.sourceTip = sourceTip
        self.targetResults = targetResults
        self.createdTagName = createdTagName
        self.phase = phase
        self.rewrittenSourceTip = rewrittenSourceTip
        self.targetTipBeforeIntegration = targetTipBeforeIntegration
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, plan, sourceTip, targetResults, createdTagName, phase
        case rewrittenSourceTip, targetTipBeforeIntegration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        plan = try container.decode(GitFlowFinishPlan.self, forKey: .plan)
        sourceTip = try container.decode(String.self, forKey: .sourceTip)
        targetResults = try container.decodeIfPresent(
            [GitFlowFinishTargetResult].self,
            forKey: .targetResults
        ) ?? []
        createdTagName = try container.decodeIfPresent(String.self, forKey: .createdTagName)
        phase = try container.decode(Phase.self, forKey: .phase)
        rewrittenSourceTip = try container.decodeIfPresent(String.self, forKey: .rewrittenSourceTip)
        targetTipBeforeIntegration = try container.decodeIfPresent(
            String.self,
            forKey: .targetTipBeforeIntegration
        )
    }
}
