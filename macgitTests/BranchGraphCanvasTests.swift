import XCTest
@testable import macgit

@MainActor
final class BranchGraphCanvasTests: XCTestCase {
    func testStraightVerticalPathReachesEnd() {
        let graphPath = SourceGit.GraphPath(
            points: [
                CGPoint(x: 10, y: 0.5),
                CGPoint(x: 10, y: 2.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.midX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 50, accuracy: 0.001)
    }

    func testLaneChangingPathUsesCurveAndReachesTarget() {
        let graphPath = SourceGit.GraphPath(
            points: [
                CGPoint(x: 10, y: 0.5),
                CGPoint(x: 22, y: 1.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.minX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 15, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 30, accuracy: 0.001)
    }

    func testSinglePointPathIsEmpty() {
        let graphPath = SourceGit.GraphPath(
            points: [CGPoint(x: 10, y: 0.5)],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        XCTAssertTrue(path.boundingRect.isEmpty)
    }

    func testMergeLinkUsesQuadraticCurve() {
        let link = SourceGit.GraphLink(
            start: CGPoint(x: 10, y: 0.5),
            control: CGPoint(x: 22, y: 0.5),
            end: CGPoint(x: 22, y: 1),
            colorIndex: 1,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.linkPath(
            for: link,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.minX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 15, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 20, accuracy: 0.001)
    }

    func testDotPathsUseSourceGitStyleSizes() {
        let center = CGPoint(x: 10, y: 0.5)

        for (type, expectedSize) in [
            (SourceGit.GraphDotType.default, 8.0),
            (.head, 12.0),
            (.merge, 12.0),
        ] {
            let dot = SourceGit.GraphDot(
                center: center,
                lane: 0,
                type: type,
                colorIndex: 0,
                isHighlighted: true
            )

            let path = BranchGraphCanvas.dotPath(
                for: dot,
                rowHeight: 20,
                laneWidth: 10,
                dotSize: 8
            )

            XCTAssertEqual(path.boundingRect.width, expectedSize, accuracy: 0.001)
            XCTAssertEqual(path.boundingRect.height, expectedSize, accuracy: 0.001)
        }
    }
}
