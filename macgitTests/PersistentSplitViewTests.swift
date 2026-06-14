import AppKit
@testable import macgit
import XCTest

final class PersistentSplitViewTests: XCTestCase {
    func testLeftRightSplitUsesHorizontalResizeCursor() {
        XCTAssertIdentical(
            ResizableCursorSplitView.dividerCursor(forSplitViewIsVertical: true),
            NSCursor.resizeLeftRight
        )
    }

    func testTopBottomSplitUsesVerticalResizeCursor() {
        XCTAssertIdentical(
            ResizableCursorSplitView.dividerCursor(forSplitViewIsVertical: false),
            NSCursor.resizeUpDown
        )
    }

    func testDividerHitAreaExpandsAroundThinDivider() {
        let dividerRect = ResizableCursorSplitView.dividerCursorRect(
            for: NSRect(x: 200, y: 0, width: 1, height: 100),
            splitViewIsVertical: true
        )

        XCTAssertGreaterThanOrEqual(dividerRect.width, 8)
        XCTAssertTrue(dividerRect.contains(NSPoint(x: 203, y: 50)))
    }

    func testSplitViewConfigurationUsesNativeAutosaveNameForGlobalPersistence() {
        let splitView = ResizableCursorSplitView()

        configurePersistentSplitView(splitView, autosaveName: "FileStatusMainSplit", isVertical: true)

        XCTAssertEqual(splitView.autosaveName, "FileStatusMainSplit")
        XCTAssertTrue(splitView.isVertical)
        XCTAssertEqual(splitView.dividerStyle, .thin)
        XCTAssertNil(splitView.delegate)
    }
}
