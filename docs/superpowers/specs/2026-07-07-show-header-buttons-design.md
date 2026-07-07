# Show Header Buttons — Design

## Summary

Add a new **Show Header Buttons** submenu under the **View** menu that lets users toggle the visibility of six header toolbar buttons:

- Branch
- Merge
- Stash
- Remote
- Finder
- Terminal

The visibility choices are global app settings, persisted locally in `UserDefaults`, and synced to Firebase when settings sync is enabled. Hidden buttons disappear completely — both from the main toolbar and from the **More** overflow menu.

## Requirements

1. A `Menu("Show Header Buttons")` inside the existing **View** menu group (`CommandGroup(before: .toolbar)`).
2. Six `Toggle` items, one per button.
3. Default state for all six toggles is **on**.
4. When a toggle is off, its button is hidden everywhere in the main window toolbar:
   - Right-side toolbar items (Remote, Finder, Terminal).
   - Left-side toolbar items (Branch, Merge, Stash).
   - The **More** overflow menu (Branch, Merge, Stash).
5. Settings are global and apply to every repository window.
6. Settings participate in the existing Firebase settings sync (`AppSettingsSnapshot` → `FirestoreSettingsStore`).
7. `firestore.rules` must allow the six new boolean fields while remaining backward-compatible with existing documents.
8. Update unit tests and Firestore rules tests.
9. If `firestore.rules` changes, run `firebase deploy --only firestore:rules`.

## Data Model

Add six new boolean properties to `AppState` and `AppSettingsSnapshot`:

| Setting | UserDefaults key | Snapshot field |
|---|---|---|
| Show Branch button | `showHeaderBranchButton` | `showHeaderBranchButton` |
| Show Merge button | `showHeaderMergeButton` | `showHeaderMergeButton` |
| Show Stash button | `showHeaderStashButton` | `showHeaderStashButton` |
| Show Remote button | `showHeaderRemoteButton` | `showHeaderRemoteButton` |
| Show Finder button | `showHeaderFinderButton` | `showHeaderFinderButton` |
| Show Terminal button | `showHeaderTerminalButton` | `showHeaderTerminalButton` |

All default to `true`.

### Backward compatibility

`AppSettingsSnapshot.decode` treats the six new fields as optional. If any field is missing, the value defaults to `true`. This lets older cloud documents continue to work without forcing a schema version bump.

## UI Changes

### View menu (`macgitApp.swift`)

Inside the existing `CommandGroup(before: .toolbar)`:

```swift
Menu("Show Header Buttons") {
    Toggle("Branch", isOn: $appState.showHeaderBranchButton)
    Toggle("Merge", isOn: $appState.showHeaderMergeButton)
    Toggle("Stash", isOn: $appState.showHeaderStashButton)
    Toggle("Remote", isOn: $appState.showHeaderRemoteButton)
    Toggle("Finder", isOn: $appState.showHeaderFinderButton)
    Toggle("Terminal", isOn: $appState.showHeaderTerminalButton)
}
```

### Toolbar (`MainWindowView.swift`)

- Wrap each right-side `ToolbarItem` (Remote, Finder, Terminal) in an `if appState.showHeaderXButton` condition.
- In `leftToolbar`, conditionally include Branch, Merge, and Stash based on their flags.
- In `moreMenu`, conditionally include Branch, Merge, and Stash based on their flags.

The **Commit**, **Pull**, **Push**, **Fetch**, **Undo**, and **Settings** buttons are not affected.

## Sync Wiring

- `AccountSessionController.bindSettingsSync` currently observes `showToolbarButtonText`, `showSubmodules`, and `showSubtrees` with `CombineLatest3`. Extend the observation to include the six new booleans.
- `ManageAccountSheet` and `SettingsSyncConflictSheet` display the new settings in the sync conflict comparison view.
- `FirestoreSettingsStore.CloudSettingsDocument` encodes/decodes the six new fields, defaulting to `true` when absent.

## Firebase Rules

Keep `schemaVersion` at `1` to avoid a breaking change. Update `validAppSettings()` in `firestore.rules`:

- `hasOnly` must include the six new keys.
- `hasAll` remains unchanged (still requires the original five keys) so existing documents are not rejected.
- For each new key, validate `!('key' in data) || data.key is bool`.

This preserves backward compatibility while allowing new writes to include the extra fields.

## Tests

- `CloudSettingsDocumentTests`: round-trip with all six fields; missing-field fallback defaults to `true`.
- `SettingsSyncServiceTests`: update fixture snapshots to include the new fields.
- `AppSettingsSnapshotTests`: update expected snapshot keys.
- `firestore.rules.test.mjs`:
  - Accept settings with the six new booleans.
  - Reject wrong types for the new fields.
  - Confirm existing documents without the new fields still pass.
- `xcodebuild build` and targeted tests pass.

## Deployment

After updating `firestore.rules` and confirming rules tests pass, run:

```bash
firebase deploy --only firestore:rules
```

## Out of Scope

- Per-repository visibility.
- Customizable button order or additional buttons beyond the six listed.
- Toolbar customization via drag-and-drop.
