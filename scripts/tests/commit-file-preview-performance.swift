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
// Standalone check; does not launch Commit+ or initialize Firebase.
// Compile with GitDiffModels.swift, SyntaxHighlighter.swift,
// CommitFilePreviewViewport.swift and CommitFilePreviewHighlightCache.swift.
import Foundation

@main
struct CommitFilePreviewPerformanceChecks {
    @MainActor
    static func main() {
        let height: CGFloat = 560
        for count in [0, 1, 2_000, 3_000, 10_000, 100_000] {
            let maxOffset = max(0, CGFloat(count) * 20 - height)
            for offset in [CGFloat(-50), 0, 1234, maxOffset, maxOffset + 100] {
                let range = CommitFilePreviewViewport.rows(offset: offset, height: height, count: count)
                precondition(range.lowerBound >= 0 && range.upperBound <= count)
                precondition(range.count <= 52, "Rendered rows must be independent of file length")
                let first = min(count, max(0, Int(floor(max(0, offset) / 20))))
                if first < count { precondition(range.contains(first)) }
            }
            let bottom = CommitFilePreviewViewport.rows(offset: maxOffset, height: height, count: count)
            precondition(bottom.upperBound == count, "Last line must remain reachable")
        }
        print("PASS: bounded viewport and last-line coverage for up to 100,000 lines")

        let lines = (0..<3_000).map { index in
            DiffLine(oldLineNumber: index + 1, newLineNumber: index + 1,
                     text: "let value\(index) = compute(input: \(index)) // sample", type: .context)
        }
        let range = CommitFilePreviewViewport.rows(offset: 20_000, height: height, count: lines.count)
        let cache = CommitFilePreviewHighlightCache()
        let clock = ContinuousClock()
        let cold = clock.measure {
            for index in range { _ = cache.text(for: lines[index], fileExtension: "swift") }
        }
        let warm = clock.measure {
            for _ in 0..<100 {
                for index in range { _ = cache.text(for: lines[index], fileExtension: "swift") }
            }
        }
        let expected = SyntaxHighlighter(fileExtension: "swift").attributedString(for: lines[0].text)
        precondition(cache.text(for: lines[0], fileExtension: "swift") == expected)
        // Exercise eviction and verify recomputation preserves the syntax output.
        for line in lines { _ = cache.text(for: line, fileExtension: "swift") }
        precondition(cache.text(for: lines[0], fileExtension: "swift") == expected)
        print("PASS: syntax cache parity after eviction")
        print("3,000-line fixture: \(range.count) rendered rows; cold highlight \(cold); 100 cached passes \(warm)")
    }
}
