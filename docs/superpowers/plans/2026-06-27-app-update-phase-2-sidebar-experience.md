# Direct App Update Phase 2: Sidebar Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a shared `Update` button at the top of repository sidebars when a newer app version is available, and change it to `Downloading…` while Sparkle is downloading.

**Architecture:** Add a presentation-only `UpdateBannerView` that reads `AppUpdateState` and forwards user intent back to `AppUpdateController`. `SidebarView` hosts the banner above the existing `List` so it stays anchored while sidebar contents scroll.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## File Structure

- Create `macgit/Views/MainWindow/UpdateBannerView.swift`: compact banner UI.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: place the banner above `List`.
- Modify `macgit/Views/MainWindow/ContentView.swift`: inherit the injected environment object without extra ownership.
- Create `macgitTests/UpdateBannerViewTests.swift`: view-policy tests.

## Task 1: Add Failing Sidebar Banner Tests

**Files:**
- Create: `macgitTests/UpdateBannerViewTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `macgitTests/UpdateBannerViewTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/UpdateBannerViewTests test
```

Expected: build fails because `UpdateBannerView` does not exist yet.

## Task 2: Build The Banner View

**Files:**
- Create: `macgit/Views/MainWindow/UpdateBannerView.swift`

- [ ] **Step 3: Create the view model surface**

Create `macgit/Views/MainWindow/UpdateBannerView.swift`:

```swift
import SwiftUI

struct UpdateBannerView: View {
    struct Model: Equatable {
        let title: String
        let isEnabled: Bool
        let showsProgress: Bool

        static func make(for state: AppUpdateState) -> Self? {
            switch state {
            case .idle, .checking:
                return nil
            case .available:
                return .init(title: "Update", isEnabled: true, showsProgress: false)
            case .downloading:
                return .init(title: "Downloading…", isEnabled: false, showsProgress: true)
            }
        }
    }

    let model: Model
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button(model.title, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(!model.isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
```

- [ ] **Step 4: Run the focused test and verify green**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/UpdateBannerViewTests test
```

Expected: `** TEST SUCCEEDED **`

## Task 3: Place The Banner In SidebarView

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

- [ ] **Step 5: Add the controller environment and anchor the banner above the list**

Update the top of `SidebarView`:

```swift
    @EnvironmentObject private var appUpdateController: AppUpdateController
```

Wrap the existing list in a `VStack`:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if let model = UpdateBannerView.Model.make(for: appUpdateController.state) {
                UpdateBannerView(model: model) {
                    appUpdateController.openUpdateWindow()
                }
            }

            List(selection: $selection) {
                // existing sections unchanged
            }
        }
    }
```

- [ ] **Step 6: Run the full test suite**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit the phase work**

Run:

```bash
git add macgit/Views/MainWindow/UpdateBannerView.swift macgit/Views/MainWindow/SidebarView.swift macgitTests/UpdateBannerViewTests.swift docs/superpowers/plans/2026-06-27-app-update-roadmap.md
git commit -m "feat: add sidebar app update banner"
```

Expected: a clean commit on `codex/app-update-phase-2-sidebar-experience`.
