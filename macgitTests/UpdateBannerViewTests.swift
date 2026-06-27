import XCTest
@testable import macgit

@MainActor
final class UpdateBannerViewTests: XCTestCase {
    func testIdleStateHasNoBannerModel() {
        XCTAssertNil(UpdateBannerView.Model.make(for: .idle))
    }

    func testCheckingStateHasNoBannerModel() {
        XCTAssertNil(UpdateBannerView.Model.make(for: .checking))
    }

    func testAvailableStateShowsUpdateTitle() {
        let model = UpdateBannerView.Model.make(for: .available)

        XCTAssertEqual(model?.title, "Update")
        XCTAssertEqual(model?.isEnabled, true)
    }

    func testDownloadingStateShowsDisabledDownloadingTitle() {
        let model = UpdateBannerView.Model.make(for: .downloading)

        XCTAssertEqual(model?.title, "Downloading…")
        XCTAssertEqual(model?.isEnabled, false)
    }
}
