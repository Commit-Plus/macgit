//
//  DiffPatchBuilder.swift
//  macgit
//

import Foundation

enum DiffPatchBuilder {
    nonisolated static func patchString(for hunk: DiffHunk, filePath: String) -> String {
        let linesString = hunk.lines.map { line in
            switch line.type {
            case .added:
                return "+\(line.text)"
            case .removed:
                return "-\(line.text)"
            case .context:
                return " \(line.text)"
            case .header:
                return line.text
            case .conflictMarker:
                return " \(line.text)"
            }
        }.joined(separator: "\n")

        return "--- a/\(filePath)\n+++ b/\(filePath)\n\(hunk.header)\n\(linesString)\n"
    }

    nonisolated static func patchString(for hunk: DiffHunk, selectedLines: [DiffLine], filePath: String) -> String {
        let selectedIDs = Set(selectedLines.map(\.id))
        var oldCount = 0
        var newCount = 0
        var filteredLines: [String] = []

        for line in hunk.lines {
            switch line.type {
            case .context:
                filteredLines.append(" \(line.text)")
                oldCount += 1
                newCount += 1
            case .added:
                if selectedIDs.contains(line.id) {
                    filteredLines.append("+\(line.text)")
                    newCount += 1
                }
            case .removed:
                if selectedIDs.contains(line.id) {
                    filteredLines.append("-\(line.text)")
                    oldCount += 1
                }
            case .header:
                filteredLines.append(line.text)
            case .conflictMarker:
                filteredLines.append(" \(line.text)")
                oldCount += 1
                newCount += 1
            }
        }

        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
              let oldStartRange = Range(match.range(at: 1), in: hunk.header),
              let newStartRange = Range(match.range(at: 2), in: hunk.header),
              let oldStart = Int(hunk.header[oldStartRange]),
              let newStart = Int(hunk.header[newStartRange]) else {
            return patchString(for: hunk, filePath: filePath)
        }

        let newHeader = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        return "--- a/\(filePath)\n+++ b/\(filePath)\n\(newHeader)\n\(filteredLines.joined(separator: "\n"))\n"
    }
}
