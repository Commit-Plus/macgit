# Welcome dashboard implementation

1. Reuse the repository picker in a compact sidebar, preserving sorting, filtering, bookmarks, opening and cloning. Add creation of a new local repository.
2. Scan the seven most recently opened repositories locally for the last thirty calendar days. Match each repository's configured author email; count locally available commits by commit date. Show unavailable identity/history explicitly.
3. Display overview cards, a per-repository daily heatmap, and actionable local conflict / cached upstream-behind notifications. Keep an explicit future-notifications placeholder.
4. Adapt cards to available width and provide independent scrolling. Set a useful default/minimum welcome window size.
5. Build without launching the app. Add focused service tests for identity, date bucketing, local status and safe creation; follow the user's build-only verification instruction.

## Result

Implemented on `codex/welcome-dashboard`. Welcome defaults to 1180 × 780 with a 900 × 620 minimum. Cards use four or two columns; repository list and dashboard scroll independently. The new-tab picker retains its existing layout.

`xcodebuild build` and `xcodebuild build-for-testing` succeeded. Tests were not executed and the app was not launched. Runtime layout and interaction verification remain manual.

Activity refinement: seven repository rows and thirty daily columns, 12 pt squares with 4 pt gaps, weekly date labels, horizontal scrolling at narrow widths, and no explanatory Git identity paragraph. Overview uses the same thirty-day window.

Cache refinement: center the heatmap within its viewport, retaining horizontal scrolling on narrow windows. Persist the complete per-repository activity locally for six hours, invalidating on day/timezone boundary changes. Reordering recents reuses entries; new repositories are scanned individually. Explicit Refresh bypasses the cache. Cache decoding/write failures fall back to local scanning/in-memory storage.
