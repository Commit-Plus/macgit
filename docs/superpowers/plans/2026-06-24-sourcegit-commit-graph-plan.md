# Sourcegit-Based Commit Graph Drawing Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port sourcegit's commit graph generation and rendering algorithm to macgit, replacing the current `CommitGraphLayoutEngine` and `BranchGraphCanvas` while preserving lazy loading and adding All Branches / Current Branch highlighting.

**Architecture:** A new `CommitGraphGenerator` produces a `CommitGraphModel` (paths, links, dots, metadata) from the loaded `[Commit]` slice. `BranchGraphCanvas` renders that model using Bézier curves and sourcegit-style dots. `HistoryView` drives the generator with a highlighting mode derived from `showAllBranches` and a `headHash` resolved from refs.

**Tech Stack:** Swift, SwiftUI Canvas, XCTest. No external dependencies.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `macgit/Views/History/CommitGraphTypes.swift` | Public model types: `CommitGraphModel`, `GraphPath`, `GraphLink`, `GraphDot`, `GraphDotType`, `GraphCommitMetadata`, `CommitGraphHighlighting`. |
| `macgit/Views/History/CommitGraphLayoutEngine.swift` | Renamed/rewritten to `CommitGraphGenerator`. Contains the sourcegit `Generate` port plus internal `PathHelper` and `ColorPicker`. |
| `macgit/Views/History/BranchGraphCanvas.swift` | SwiftUI `Canvas` that draws paths, links, and dots from `CommitGraphModel`. |
| `macgit/Views/History/HistoryView.swift` | Wires `showAllBranches` to `CommitGraphHighlighting`, resolves `headHash`, and calls `CommitGraphGenerator.generate`. |
| `macgitTests/CommitGraphGeneratorTests.swift` | Replaces `CommitGraphLayoutEngineTests.swift`. Tests layout, merges, highlighting, lazy-loading boundary. |
| `macgitTests/BranchGraphCanvasTests.swift` | Tests path/link/dot rendering geometry. |

---

## Task 1: Add New Data Model Types

**Files:**
- Modify: `macgit/Views/History/CommitGraphTypes.swift`
- Test: `macgitTests/CommitGraphGeneratorTests.swift` (created in Task 2; no test-only file for this task)

**Goal:** Define the sourcegit-aligned model types. Keep the old `GraphNode`/`GraphPath`/`GraphPoint`/`CommitGraphLayout` types in place temporarily; do not remove them yet.

- [ ] **Step 1: Add `CommitGraphHighlighting` enum**

  ```swift
  enum CommitGraphHighlighting {
      case all
      case currentBranchOnly
  }
  ```

- [ ] **Step 2: Add `GraphCommitMetadata`**

  ```swift
  struct GraphCommitMetadata {
      let colorIndex: Int
      let isHighlighted: Bool
      let leftMargin: Double
  }
  ```

- [ ] **Step 3: Add `GraphPath`, `GraphLink`, `GraphDotType`, `GraphDot`**

  ```swift
  struct GraphPath {
      let points: [CGPoint]
      let colorIndex: Int
      let isHighlighted: Bool
  }

  struct GraphLink {
      let start: CGPoint
      let control: CGPoint
      let end: CGPoint
      let colorIndex: Int
      let isHighlighted: Bool
  }

  enum GraphDotType {
      case `default`
      case head
      case merge
  }

  struct GraphDot {
      let center: CGPoint
      let lane: Int
      let type: GraphDotType
      let colorIndex: Int
      let isHighlighted: Bool
  }
  ```

- [ ] **Step 4: Add `CommitGraphModel`**

  ```swift
  struct CommitGraphModel {
      let paths: [GraphPath]
      let links: [GraphLink]
      let dots: [GraphDot]
      let laneCount: Int
      let commitMetadata: [String: GraphCommitMetadata]
  }
  ```

- [ ] **Step 5: Add `GraphPalette`**

  ```swift
  struct GraphPalette {
      static let colors: [Color] = [
          Color(nsColor: .systemOrange),
          Color(nsColor: .systemGreen),
          Color(nsColor: .systemTeal),
          Color(nsColor: .systemYellow),
          Color(nsColor: .systemPink),
          Color(nsColor: .systemRed),
          Color(nsColor: .systemBrown),
          Color(nsColor: .systemGreen),
          Color(nsColor: .systemBlue),
          Color(nsColor: .systemCyan),
      ]

      static func color(for index: Int) -> Color {
          colors[index % colors.count]
      }
  }
  ```

- [ ] **Step 6: Build to verify**

  Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
  Expected: succeeds (old types still present).

- [ ] **Step 6: Commit**

  ```bash
  git add macgit/Views/History/CommitGraphTypes.swift
  git commit -m "feat(graph): add sourcegit-aligned model types"
  ```

---

## Task 2: Implement CommitGraphGenerator

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift` (rename to `CommitGraphGenerator`)
- Test: `macgitTests/CommitGraphGeneratorTests.swift`

**Goal:** Port sourcegit's `Models.CommitGraph.Generate` to Swift.

- [ ] **Step 1: Create the test file with a helper factory**

  ```swift
  import XCTest
  @testable import macgit

  final class CommitGraphGeneratorTests: XCTestCase {
      private func makeCommit(
          hash: String,
          parents: [String] = [],
          refs: [String] = []
      ) -> Commit {
          Commit(
              hash: hash,
              parents: parents,
              message: "",
              author: "",
              email: "",
              date: Date(),
              refs: refs
          )
      }
  }
  ```

- [ ] **Step 2: Write failing linear-history test**

  ```swift
  func testLinearHistory() {
      let a = makeCommit(hash: "a")
      let b = makeCommit(hash: "b", parents: ["a"])
      let c = makeCommit(hash: "c", parents: ["b"])

      let model = CommitGraphGenerator.generate(
          commits: [c, b, a],
          highlighting: .all,
          headHash: "c"
      )

      XCTAssertEqual(model.dots.count, 3)
      XCTAssertEqual(model.paths.count, 1)
      XCTAssertEqual(model.links.count, 0)
      XCTAssertEqual(model.laneCount, 1)
      XCTAssertTrue(model.dots.allSatisfy { $0.isHighlighted })
  }
  ```

  Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/CommitGraphGeneratorTests/testLinearHistory`
  Expected: build fails because `CommitGraphGenerator` does not exist.

- [ ] **Step 3: Rename file and add skeleton generator**

  Rename `macgit/Views/History/CommitGraphLayoutEngine.swift` to `macgit/Views/History/CommitGraphGenerator.swift`.

  Replace its contents with:

  ```swift
  import Foundation

  enum CommitGraphGenerator {
      static func generate(
          commits: [Commit],
          highlighting: CommitGraphHighlighting,
          headHash: String?
      ) -> CommitGraphModel {
          CommitGraphModel(
              paths: [],
              links: [],
              dots: [],
              laneCount: 1,
              commitMetadata: [:]
          )
      }
  }
  ```

  Update the Xcode project if needed so the renamed file is still in the target.

- [ ] **Step 4: Run linear test again**

  Run: `xcodebuild ... -only-testing:macgitTests/CommitGraphGeneratorTests/testLinearHistory`
  Expected: fails on `XCTAssertEqual(model.dots.count, 3)` (dots is empty).

- [ ] **Step 5: Implement full generator port**

  Implement `CommitGraphGenerator.generate` with `PathHelper` and `ColorPicker` classes following the design spec and sourcegit's `Models/CommitGraph.cs`.

  Key implementation details:
  - `unitWidth = 12`, `halfWidth = 6`, `unitHeight = 1`, `halfHeight = 0.5`.
  - Build `rowByHash` and `merged` set from `headHash`.
  - Iterate commits top-to-bottom, maintaining `unsolved: [PathHelper]` and `ended: [PathHelper]`.
  - For parent lookups use a dictionary `[String: PathHelper]` for O(1) access (but handle the rare case where two paths share the same next hash by falling back to the first match, as sourcegit does).
  - Record dot position, path points, links, and metadata.
  - End unsolved paths at `endY = (commits.count - 0.5) * unitHeight`.

- [ ] **Step 6: Run linear test**

  Run: `xcodebuild ... -only-testing:macgitTests/CommitGraphGeneratorTests/testLinearHistory`
  Expected: passes.

- [ ] **Step 7: Add and verify merge test**

  ```swift
  func testFeatureBranchAndMerge() {
      let a = makeCommit(hash: "a")
      let b = makeCommit(hash: "b", parents: ["a"])
      let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
      let f = makeCommit(hash: "f", parents: ["b"])
      let m = makeCommit(hash: "m", parents: ["c", "f"])

      let model = CommitGraphGenerator.generate(
          commits: [m, f, c, b, a],
          highlighting: .all,
          headHash: "m"
      )

      XCTAssertEqual(model.dots.count, 5)
      XCTAssertEqual(model.links.count, 1)
      XCTAssertGreaterThanOrEqual(model.laneCount, 2)
  }
  ```

  Run and verify passes.

- [ ] **Step 8: Add octopus merge test**

  ```swift
  func testOctopusMerge() {
      let a = makeCommit(hash: "a")
      let b = makeCommit(hash: "b", parents: ["a"])
      let c = makeCommit(hash: "c", parents: ["a"])
      let d = makeCommit(hash: "d", parents: ["a"])
      let m = makeCommit(hash: "m", parents: ["b", "c", "d"])

      let model = CommitGraphGenerator.generate(
          commits: [m, b, c, d, a],
          highlighting: .all,
          headHash: "m"
      )

      XCTAssertEqual(model.links.count, 2)
      XCTAssertGreaterThanOrEqual(model.laneCount, 3)
  }
  ```

  Run and verify passes.

- [ ] **Step 9: Add current-branch highlighting test**

  ```swift
  func testCurrentBranchOnlyHighlighting() {
      let a = makeCommit(hash: "a")
      let b = makeCommit(hash: "b", parents: ["a"])
      let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
      let f = makeCommit(hash: "f", parents: ["b"])
      let m = makeCommit(hash: "m", parents: ["c", "f"])

      let model = CommitGraphGenerator.generate(
          commits: [m, f, c, b, a],
          highlighting: .currentBranchOnly,
          headHash: "c"
      )

      let highlightedDots = model.dots.filter(\.isHighlighted)
      XCTAssertEqual(highlightedDots.count, 3) // c, b, a
  }
  ```

  Run and verify passes.

- [ ] **Step 10: Add lazy-loading boundary test**

  ```swift
  func testMissingParentDrawsContinuationPath() {
      let a = makeCommit(hash: "a", parents: ["missing"])
      let model = CommitGraphGenerator.generate(
          commits: [a],
          highlighting: .all,
          headHash: "a"
      )

      XCTAssertEqual(model.dots.count, 1)
      XCTAssertEqual(model.paths.count, 1)
      let lastPoint = model.paths.first?.points.last
      XCTAssertEqual(lastPoint?.y, 0.5)
  }
  ```

  Run and verify passes.

- [ ] **Step 11: Add remote branch head test**

  ```swift
  func testRemoteBranchHeadCreatesNewPath() {
      let a = makeCommit(hash: "a")
      let b = makeCommit(hash: "b", parents: ["a"], refs: ["origin/main"])
      let c = makeCommit(hash: "c", parents: ["a"], refs: ["main"])

      let model = CommitGraphGenerator.generate(
          commits: [c, b, a],
          highlighting: .all,
          headHash: "c"
      )

      XCTAssertGreaterThanOrEqual(model.laneCount, 2)
  }
  ```

  Run and verify passes.

- [ ] **Step 12: Commit**

  ```bash
  git mv macgit/Views/History/CommitGraphLayoutEngine.swift macgit/Views/History/CommitGraphGenerator.swift
  git mv macgitTests/CommitGraphLayoutEngineTests.swift macgitTests/CommitGraphGeneratorTests.swift
  git add macgit/Views/History/CommitGraphGenerator.swift macgitTests/CommitGraphGeneratorTests.swift
  git commit -m "feat(graph): port sourcegit CommitGraph generator and tests"
  ```

---

## Task 3: Rewrite BranchGraphCanvas

**Files:**
- Modify: `macgit/Views/History/BranchGraphCanvas.swift`
- Test: `macgitTests/BranchGraphCanvasTests.swift`

**Goal:** Render `CommitGraphModel` with Bézier paths, merge links, and sourcegit-style dots.

- [ ] **Step 1: Update `BranchGraphCanvas` signature and frame**

  ```swift
  struct BranchGraphCanvas: View {
      let model: CommitGraphModel

      let rowHeight: CGFloat = 24
      let laneWidth: CGFloat = 14
      let dotSize: CGFloat = 8
      let graphTrailingPadding: CGFloat = 8

      var body: some View {
          Canvas { context, size in
              drawGraph(in: &context)
          }
          .frame(width: graphWidth, height: CGFloat(model.dots.count) * rowHeight)
          .fixedSize()
      }

      private var graphWidth: CGFloat {
          CGFloat(model.laneCount) * laneWidth + graphTrailingPadding
      }

      private func drawGraph(in context: inout GraphicsContext) { /* ... */ }
  }
  ```

- [ ] **Step 2: Update existing canvas tests to compile**

  Temporarily change `BranchGraphCanvasTests.swift` to use `CommitGraphModel`.

  ```swift
  let model = CommitGraphModel(
      paths: [GraphPath(points: [...], colorIndex: 0, isHighlighted: true)],
      links: [],
      dots: [],
      laneCount: 2,
      commitMetadata: [:]
  )
  ```

- [ ] **Step 3: Implement path drawing**

  Convert sourcegit graph-unit coordinates to points and build the `Path`:

  ```swift
  private func position(for point: CGPoint) -> CGPoint {
      CGPoint(
          x: CGFloat(point.x / 12) * laneWidth + laneWidth / 2,
          y: CGFloat(point.y) * rowHeight + rowHeight / 2
      )
  }

  private func path(for graphPath: GraphPath) -> Path {
      var path = Path()
      let points = graphPath.points
      guard points.count > 1 else { return path }

      var last = position(for: points[0])
      path.move(to: last)

      for i in 1..<points.count {
          let cur = position(for: points[i])
          if points[i].x > points[i - 1].x {
              path.addLine(to: CGPoint(x: last.x, y: cur.y - rowHeight / 2))
              path.addQuadCurve(to: CGPoint(x: cur.x, y: cur.y - rowHeight / 2 + 4), control: CGPoint(x: last.x, y: cur.y - rowHeight / 2))
              path.addLine(to: cur)
          } else if points[i].x < points[i - 1].x {
              let midY = (last.y + cur.y) / 2
              if i < points.count - 1 {
                  path.addCurve(
                      to: cur,
                      control1: CGPoint(x: last.x, y: midY + 4),
                      control2: CGPoint(x: cur.x, y: midY - 4)
                  )
              } else {
                  path.addQuadCurve(to: cur, control: CGPoint(x: last.x, y: cur.y))
              }
          } else {
              path.addLine(to: cur)
          }
          last = cur
      }
      return path
  }
  ```

  Adjust curve control points to match sourcegit's exact geometry.

- [ ] **Step 4: Implement link drawing**

  Draw each `GraphLink` as a quadratic Bézier:

  ```swift
  private func linkPath(for link: GraphLink) -> Path {
      var path = Path()
      let start = position(for: link.start)
      let end = position(for: link.end)
      let control = CGPoint(x: link.control.x / 12 * laneWidth + laneWidth / 2,
                            y: link.control.y * rowHeight + rowHeight / 2)
      path.move(to: start)
      path.addQuadCurve(to: end, control: control)
      return path
  }
  ```

- [ ] **Step 5: Implement dot drawing**

  Use `GraphicsContext` to draw circles and lines:

  ```swift
  private func drawDot(_ dot: GraphDot, in context: inout GraphicsContext) {
      let center = position(for: dot.center)
      let color = GraphPalette.color(for: dot.colorIndex)
      let penColor = dot.isHighlighted ? color : Color.gray.opacity(0.4)
      let fillColor = dot.isHighlighted ? color : Color.gray.opacity(0.4)

      let dotRect = CGRect(x: center.x - dotSize/2, y: center.y - dotSize/2, width: dotSize, height: dotSize)
      let dotPath = Path(ellipseIn: dotRect)

      switch dot.type {
      case .default:
          context.fill(dotPath, with: .color(fillColor))
          context.stroke(dotPath, with: .color(.white), lineWidth: 1.5)
      case .head:
          context.fill(dotPath, with: .color(.white))
          context.stroke(dotPath, with: .color(penColor), lineWidth: 2)
          let inner = Path(ellipseIn: dotRect.insetBy(dx: 3, dy: 3))
          context.fill(inner, with: .color(penColor))
      case .merge:
          context.stroke(dotPath, with: .color(penColor), lineWidth: 2)
          context.stroke(
              Path { p in
                  p.move(to: CGPoint(x: center.x, y: center.y - 3))
                  p.addLine(to: CGPoint(x: center.x, y: center.y + 3))
              },
              with: .color(.white),
              lineWidth: 2
          )
          context.stroke(
              Path { p in
                  p.move(to: CGPoint(x: center.x - 3, y: center.y))
                  p.addLine(to: CGPoint(x: center.x + 3, y: center.y))
              },
              with: .color(.white),
              lineWidth: 2
          )
      }
  }
  ```

- [ ] **Step 6: Update tests for new primitives**

  Replace `BranchGraphCanvasTests.swift` contents with tests for:
  - straight vertical path bounds,
  - lane-changing path with curves,
  - single-point path returns empty,
  - merge link bounds,
  - dot path bounds for default/head/merge.

- [ ] **Step 7: Run canvas tests**

  Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/BranchGraphCanvasTests`
  Expected: all pass.

- [ ] **Step 8: Commit**

  ```bash
  git add macgit/Views/History/BranchGraphCanvas.swift macgitTests/BranchGraphCanvasTests.swift
  git commit -m "feat(graph): rewrite BranchGraphCanvas for sourcegit-style rendering"
  ```

---

## Task 4: Integrate with HistoryView

**Files:**
- Modify: `macgit/Views/History/HistoryView.swift`
- Modify: `macgit/Views/History/CommitRowView.swift` (if GraphNode binding changes)
- Test: `macgitTests/HistoryViewTests.swift`

**Goal:** Drive the new generator from `HistoryView` and keep the UI working.

- [ ] **Step 1: Update graph state type**

  In `HistoryView.swift`:

  ```swift
  @State private var graphModel: CommitGraphModel? = nil
  ```

  Replace usages of `graphLayout` with `graphModel`.

- [ ] **Step 2: Resolve head hash**

  Add a helper:

  ```swift
  private func resolvedHeadHash(from commits: [Commit]) -> String? {
      if let headCommit = commits.first(where: { commit in
          commit.refs.contains { $0.hasPrefix("HEAD -> ") || $0 == "HEAD" }
      }) {
          return headCommit.hash
      }
      return nil
  }
  ```

- [ ] **Step 3: Replace layout call with generator call**

  In `loadHistory`:

  ```swift
  let highlighting: CommitGraphHighlighting = showAllBranches ? .all : .currentBranchOnly
  let headHash = resolvedHeadHash(from: commits) ?? await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
  graphModel = CommitGraphGenerator.generate(
      commits: commits,
      highlighting: highlighting,
      headHash: headHash
  )
  ```

- [ ] **Step 4: Update graph width calculation**

  ```swift
  private var graphWidth: CGFloat {
      CGFloat(graphModel?.laneCount ?? 1) * 14 + 8
  }
  ```

- [ ] **Step 5: Update canvas usage**

  Replace:
  ```swift
  BranchGraphCanvas(
      nodes: layout.nodes,
      paths: layout.paths,
      laneCount: layout.laneCount
  )
  ```
  with:
  ```swift
  BranchGraphCanvas(model: model)
  ```

- [ ] **Step 6: Update commit list iteration**

  `CommitRowView` only needs the commit; the graph dot color is stored in `model.dots`. Iterate commits directly:

  ```swift
  ForEach(Array(commits.enumerated()), id: \.element.hash) { index, commit in
      CommitRowView(
          commit: commit,
          graphWidth: graphWidth,
          isSelected: selectedCommit?.hash == commit.hash,
          // ... other widths
      )
      .id(commit.hash)
      // ...
  }
  ```

  Update `CommitRowView` to accept a `Commit` directly instead of a `GraphNode`.

- [ ] **Step 7: Add HistoryView test for highlighting mode mapping**

  Add a small pure helper on `HistoryView` (or test the mapping inline):

  ```swift
  func testShowAllBranchesMapsToAllHighlighting() {
      let all = HistoryView.highlighting(for: true)
      let current = HistoryView.highlighting(for: false)
      XCTAssertEqual(all, .all)
      XCTAssertEqual(current, .currentBranchOnly)
  }
  ```

  Where `HistoryView.highlighting(for:)` is:

  ```swift
  static func highlighting(for showAllBranches: Bool) -> CommitGraphHighlighting {
      showAllBranches ? .all : .currentBranchOnly
  }
  ```

- [ ] **Step 8: Build and run HistoryView tests**

  Run: `xcodebuild ... test -only-testing:macgitTests/HistoryViewTests`
  Expected: passes.

- [ ] **Step 9: Commit**

  ```bash
  git add macgit/Views/History/HistoryView.swift macgit/Views/History/CommitRowView.swift macgitTests/HistoryViewTests.swift
  git commit -m "feat(graph): integrate sourcegit generator into HistoryView"
  ```

---

## Task 5: Cleanup Old Types and Full Verification

**Files:**
- Modify: `macgit/Views/History/CommitGraphTypes.swift`
- Test: all test targets

**Goal:** Remove obsolete types and ensure the full build + test suite is green.

- [ ] **Step 1: Remove old types from CommitGraphTypes.swift**

  Delete:
  - `GraphNode`
  - old `GraphPath`
  - old `GraphPoint`
  - old `CommitGraphLayout`
  - `LaneColors` (replaced by `GraphPalette`)

  Keep only the new types defined in Task 1 plus `GraphPalette`.

- [ ] **Step 2: Update any remaining references**

  Search for `CommitGraphLayout`, old `GraphPath`, `GraphPoint` across the project and update or remove.

- [ ] **Step 3: Run full build**

  Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
  Expected: succeeds with zero warnings about the removed types.

- [ ] **Step 4: Run full test suite**

  Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`
  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add macgit/Views/History/CommitGraphTypes.swift
  git commit -m "refactor(graph): remove obsolete graph layout types"
  ```

---

## Self-Review Checklist

1. **Spec coverage:**
   - Sourcegit algorithm port → Task 2.
   - Bézier rendering → Task 3.
   - All/Current branch highlighting → Task 2 (tests) + Task 4 (HistoryView wiring).
   - Remote branches → Task 2 (test).
   - Lazy loading → Task 2 (missing-parent test) + Task 4 (regenerate on load).
   - Head/merge dot types → Task 3.

2. **Placeholder scan:** No TBD/TODO/fill-in details.

3. **Type consistency:** `CommitGraphGenerator.generate` returns `CommitGraphModel` everywhere; `BranchGraphCanvas` takes `CommitGraphModel`; `HistoryView` uses `graphModel`.
