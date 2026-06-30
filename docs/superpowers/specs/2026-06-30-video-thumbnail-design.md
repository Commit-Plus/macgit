# Video thumbnail preview in diff pane

## Goal
When a video file is selected in the file-status diff pane, Commit+ should show a static thumbnail frame instead of the empty "No diff to display" view.

## Scope
- **In scope:** Static thumbnail for working-tree video files in the status diff pane.
- **Out of scope:** Inline playback, audio, staged/HEAD video blobs, history/commit diff video previews, non-video binary previews.

## Approach
Use `AVFoundation.AVAssetImageGenerator` to extract a single frame from the file on disk and render it as an `NSImage`.

- It is the standard macOS API and supports the common formats users are likely to commit (mp4, mov, mkv, avi, webm, etc.).
- A static frame is enough to confirm the file contents at a glance, matching the existing image-preview behavior.
- Working-tree only avoids the complexity of extracting Git blobs to temporary files.

## Data model changes
Add a computed `isVideo` property to `StatusFile` in `macgit/Services/GitStatus.swift`:

```swift
var isVideo: Bool {
    ["mp4", "mov", "mkv", "avi", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp"]
        .contains(fileExtension)
}
```

This list intentionally overlaps with the existing `isBinary` list so that video files are no longer treated as un-previewable.

## UI changes

### New view: `VideoThumbnailView`
- Location: `macgit/Views/Common/VideoThumbnailView.swift`
- Input: `fileURL: URL`
- Behavior:
  - Loads the thumbnail asynchronously via `.task(id: fileURL)` so generation is cancelled when the selection changes.
  - Uses `AVAssetImageGenerator` with `appliesPreferredTrackTransform = true`.
  - Requests a frame at 1 second; falls back to time zero on failure.
  - Renders the generated `NSImage` with the same aspect-fit/scrollable layout used by `imagePreview`.
  - On failure, shows an `EmptyStateView(icon: "film", message: "Unable to preview video", detail: file.path)`.

### Update `FileStatusView.diffPanel`
Change the preview branching in `macgit/Views/FileStatus/FileStatusView.swift`:

1. `file.isImage` → existing image preview
2. `file.isVideo` → new `VideoThumbnailView`
3. otherwise → existing `DiffView`

## Project changes
Link `AVFoundation.framework` in the main `macgit` target so the new code compiles.

## Error handling and performance
- Async `.task` cancellation prevents stale thumbnail work from piling up when the user clicks through many files.
- Thumbnail generation errors are swallowed and a placeholder is shown, so a corrupt or unsupported video does not break the UI.
- No audio decoding is performed.

## Testing
- Add a unit test verifying `StatusFile.isVideo` returns `true` for video extensions and `false` for non-video extensions.
- Run the full `macgitTests` suite after implementation to ensure no regressions.
