# Video Thumbnail Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (inline) or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a static thumbnail preview for working-tree video files in the file-status diff pane.

**Architecture:** Add a `StatusFile.isVideo` flag, create a reusable `VideoThumbnailView` backed by `AVAssetImageGenerator`, and branch the existing diff-panel preview logic to use it for video files. Link `AVFoundation` via `OTHER_LDFLAGS`.

**Tech Stack:** Swift, SwiftUI, AVFoundation, XCTest

---

## Task 1: Add failing test for `StatusFile.isVideo`

**Files:**
- Create: `macgitTests/StatusFileTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
import XCTest
@testable import macgit

@MainActor
final class StatusFileTests: XCTestCase {
    func testVideoExtensionsAreRecognized() {
        for ext in ["mp4", "mov", "mkv", "avi", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp"] {
            let file = StatusFile(path: "clip.\(ext)", status: .modified, originalPath: nil)
            XCTAssertTrue(file.isVideo, ".\(ext) should be recognized as video")
        }
    }

    func testNonVideoExtensionsAreNotVideo() {
        for ext in ["png", "jpg", "txt", "pdf", "mp3", "zip"] {
            let file = StatusFile(path: "file.\(ext)", status: .modified, originalPath: nil)
            XCTAssertFalse(file.isVideo, ".\(ext) should not be recognized as video")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/StatusFileTests
```

Expected: **TEST FAILED** with `Value of type 'StatusFile' has no member 'isVideo'`.

---

## Task 2: Add `StatusFile.isVideo`

**Files:**
- Modify: `macgit/Services/GitStatus.swift:73-75`

- [ ] **Step 1: Insert the `isVideo` property after `isImage`**

```swift
    var isVideo: Bool {
        ["mp4", "mov", "mkv", "avi", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp"]
            .contains(fileExtension)
    }
```

- [ ] **Step 2: Run the test to verify it passes**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/StatusFileTests
```

Expected: **TEST SUCCEEDED**.

---

## Task 3: Link `AVFoundation`

**Files:**
- Modify: `macgit.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add `OTHER_LDFLAGS` to the main target Debug configuration**

Locate the `6A843CB62FC534310031F230 /* Debug */` build settings block (main target) and add the following line after `LD_RUNPATH_SEARCH_PATHS = (...);`:

```
                OTHER_LDFLAGS = "$(inherited) -framework AVFoundation";
```

- [ ] **Step 2: Add `OTHER_LDFLAGS` to the main target Release configuration**

Locate the `6A843CB72FC534310031F230 /* Release */` build settings block and add the same line after its `LD_RUNPATH_SEARCH_PATHS = (...);`.

- [ ] **Step 3: Build to verify the linker flag is accepted**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: Build succeeds (no code uses AVFoundation yet, so this just confirms the flag is valid).

---

## Task 4: Create `VideoThumbnailView`

**Files:**
- Create: `macgit/Views/Common/VideoThumbnailView.swift`

- [ ] **Step 1: Write the view**

```swift
//
//  VideoThumbnailView.swift
//  macgit
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
import AVFoundation

struct VideoThumbnailView: View {
    let fileURL: URL
    let filePath: String?

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image {
                imageDisplayView(image)
            } else if failed {
                EmptyStateView(
                    icon: "film",
                    message: "Unable to preview video",
                    detail: filePath ?? fileURL.lastPathComponent
                )
            } else {
                ProgressView("Loading preview…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        image = nil
        failed = false

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            failed = true
            return
        }

        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let requestedTime = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let cgImage = try await generateCGImage(generator: generator, for: requestedTime)
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            image = NSImage(cgImage: cgImage, size: size)
        } catch {
            // Fallback to time zero if the 1-second frame fails
            let zeroTime = CMTime.zero
            do {
                let cgImage = try await generateCGImage(generator: generator, for: zeroTime)
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                image = NSImage(cgImage: cgImage, size: size)
            } catch {
                failed = true
            }
        }
    }

    private func generateCGImage(generator: AVAssetImageGenerator, for time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: ThumbnailError.noImage)
                }
            }
        }
    }

    private enum ThumbnailError: Error {
        case noImage
    }

    private func imageDisplayView(_ nsImage: NSImage) -> some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        maxWidth: max(geo.size.width, CGFloat(nsImage.size.width)),
                        maxHeight: max(geo.size.height, CGFloat(nsImage.size.height))
                    )
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: Build succeeds.

---

## Task 5: Wire video preview into `FileStatusView`

**Files:**
- Modify: `macgit/Views/FileStatus/FileStatusView.swift:565-583`

- [ ] **Step 1: Replace the preview branch with video support**

Current code:
```swift
                    if file.isImage {
                        imagePreview(file: file)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: file,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            onRefresh: {
                                Task {
                                    await loadStatus()
                                }
                            },
                            onError: { message in
                                errorMessage = message
                                showingError = true
                            }
                        )
                    }
```

New code:
```swift
                    if file.isImage {
                        imagePreview(file: file)
                    } else if file.isVideo {
                        videoPreview(file: file)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: file,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            onRefresh: {
                                Task {
                                    await loadStatus()
                                }
                            },
                            onError: { message in
                                errorMessage = message
                                showingError = true
                            }
                        )
                    }
```

- [ ] **Step 2: Add the `videoPreview(file:)` helper after `imagePreview(file:)`**

```swift
    private func videoPreview(file: StatusFile) -> some View {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        return VideoThumbnailView(fileURL: fileURL, filePath: file.path)
    }
```

- [ ] **Step 3: Build and run the new tests**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/StatusFileTests
```

Expected: **TEST SUCCEEDED**.

---

## Task 6: Full regression test

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: **TEST SUCCEEDED**.

- [ ] **Step 2: Build the app**

Run:
```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: Build succeeds with no new warnings.

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| Static thumbnail for working-tree video files | Task 4 + Task 5 |
| `StatusFile.isVideo` data model | Task 2 |
| AVFoundation linked | Task 3 |
| Error/placeholder handling | Task 4 |
| Cancellation on selection change | Task 4 (`.task(id: fileURL)`) |
| Tests for `isVideo` | Task 1 |
| No regressions | Task 6 |
