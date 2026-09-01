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

struct PotentialConflictFileDetailSheet: View {
    let presentation: PotentialConflictFilePresentation
    let repositoryURL: URL
    let canUpdateCurrentBranch: Bool
    let onUpdateCurrentBranch: (CurrentBranchIntegrationStatus) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var analysis: PotentialConflictFileAnalysis?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            details
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 640)
        .task(id: presentation.id) {
            analysis = await GitStatusService.shared.potentialConflictFileAnalysis(
                for: presentation.file,
                status: presentation.status,
                in: repositoryURL
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Potential update conflict", systemImage: "exclamationmark.triangle")
                .font(.title3)
                .bold()
                .foregroundStyle(.orange)

            Text(presentation.file.path)
                .font(.headline)
                .textSelection(.enabled)

            Text("Local changes may interact with updates from \(presentation.status.baseRef ?? "the base branch"). The file is not currently conflicted.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var details: some View {
        if let analysis {
            VStack(alignment: .leading, spacing: 12) {
                analysisSummary(analysis)

                TabView {
                    DiffView(hunks: analysis.localHunks, filePath: presentation.file.path)
                        .tabItem {
                            Label("Local Changes", systemImage: "desktopcomputer")
                        }

                    DiffView(hunks: analysis.incomingHunks, filePath: presentation.file.path)
                        .tabItem {
                            Label(
                                "Incoming from \(presentation.status.baseRef ?? "Base")",
                                systemImage: "arrow.down.doc"
                            )
                        }
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Analyzing local and incoming changes…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func analysisSummary(_ analysis: PotentialConflictFileAnalysis) -> some View {
        if let conflictPreview = analysis.conflictPreview {
            VStack(alignment: .leading, spacing: 8) {
                Label("Textual overlap predicted", systemImage: "exclamationmark.triangle.fill")
                    .bold()
                    .foregroundStyle(.orange)

                ScrollView([.horizontal, .vertical]) {
                    Text(highlightedConflictPreview(conflictPreview))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            }
        } else if analysis.exactAnalysisPerformed {
            Label(
                "No exact textual overlap was produced, but both local and incoming changes touch this file.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        } else {
            Label(
                "Exact line-level analysis is unavailable for this file. Compare the local and incoming changes below.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func highlightedConflictPreview(_ preview: String) -> AttributedString {
        let lines = preview.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let highlighter = SyntaxHighlighter(fileExtension: presentation.file.fileExtension)
        var result = AttributedString()
        var section = 0

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            var markerColor: Color?

            if trimmedLine.hasPrefix("<<<<<<<") {
                section = 1
                markerColor = .red
            } else if trimmedLine.hasPrefix("|||||||") {
                section = 2
                markerColor = .orange
            } else if trimmedLine.hasPrefix("=======") {
                section = 3
                markerColor = .green
            } else if trimmedLine.hasPrefix(">>>>>>>") {
                markerColor = .green
            }

            var attributedLine = highlighter.attributedString(for: line, fontSize: 12)
            if let markerColor {
                attributedLine.foregroundColor = markerColor
                attributedLine.backgroundColor = markerColor.opacity(0.16)
                attributedLine.font = .system(size: 12, weight: .semibold, design: .monospaced)
            } else {
                switch section {
                case 1:
                    attributedLine.backgroundColor = Color.red.opacity(0.10)
                case 2:
                    attributedLine.backgroundColor = Color.orange.opacity(0.08)
                case 3:
                    attributedLine.backgroundColor = Color.green.opacity(0.10)
                default:
                    break
                }
            }

            result.append(attributedLine)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }

            if trimmedLine.hasPrefix(">>>>>>>") {
                section = 0
            }
        }

        return result
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !canUpdateCurrentBranch {
                Text("Commit or stash changes and finish other Git operations before updating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close", role: .cancel, action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)

            Button("Update Current Branch", systemImage: "arrow.triangle.2.circlepath", action: updateCurrentBranch)
                .buttonStyle(.borderedProminent)
                .disabled(!canUpdateCurrentBranch)
        }
        .padding()
    }

    private func updateCurrentBranch() {
        dismiss()
        onUpdateCurrentBranch(presentation.status)
    }
}
