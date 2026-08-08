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

import SwiftUI

struct GitFlowCommandMenuContent: View {
    let state: GitFlowCommandState?
    let hasOpenRepository: Bool
    let perform: (GitFlowMenuAction) -> Void

    var body: some View {
        if let state, state.isEnabled {
            if state.hasPendingFinish {
                Button("Resume Finish") {
                    perform(.resumeFinish)
                }
                .disabled(!state.canResumeOrAbortFinish)

                Button("Abort Finish", role: .destructive) {
                    perform(.abortFinish)
                }
                .disabled(!state.canResumeOrAbortFinish)

                Divider()
            }

            ForEach(GitFlowTopicKind.allCases) { kind in
                Button("Start \(kind.displayName)…") {
                    perform(.start(kind))
                }
                .disabled(!state.canStart(kind))

                Button("Finish \(kind.displayName)…") {
                    perform(.finish(kind))
                }
                .disabled(!state.canFinish(kind))

                if kind != GitFlowTopicKind.allCases.last {
                    Divider()
                }
            }

            Divider()

            Button("Configure Git Flow…") {
                perform(.configure)
            }
            .disabled(state.operationInProgress)

            Button("Disable Git Flow") {
                perform(.disable)
            }
            .disabled(state.operationInProgress)
        } else {
            Button("Set Up Git Flow…") {
                perform(.configure)
            }
            .disabled(!hasOpenRepository || state?.operationInProgress == true)
        }
    }
}
