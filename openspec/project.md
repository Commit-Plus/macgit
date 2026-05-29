# Project Context

## Purpose
macgit is a native macOS Git client built with SwiftUI. It provides a GUI for common Git operations (status, diff, commit, branch switching) on local repositories.

## Tech Stack
- Swift 5.0
- SwiftUI + AppKit (for file picker bridges)
- Core Data (for persistence)
- Xcode 26.2+ (with PBXFileSystemSynchronizedRootGroup support)
- Git CLI (via Process invocation)

## Project Conventions

### Code Style
- Swift standard naming (PascalCase types, camelCase members)
- Views in SwiftUI use `@State`, `@Binding`, `@ObservableObject` as appropriate
- Service classes isolate Git CLI logic from UI
- Prefer `async/await` over completion handlers for new code

### Architecture Patterns
- **Layer-based folder structure** under `macgit/`:
  - `App/` — App entry point (`macgitApp.swift`)
  - `Views/` — SwiftUI views (feature UI components)
  - `Services/` — Business logic, data stores, Git CLI wrappers
  - `Resources/` — Assets, Core Data model
- Single-module app (no separate frameworks)
- Views depend on Services; Services do not depend on Views

### Testing Strategy
- No formal test suite yet; validate via `xcodebuild` builds
- Manual testing via Xcode previews and live app runs

### Git Workflow
- Main branch: direct commits acceptable for small changes
- Use `git add -A` after structural changes (folder moves) to keep index in sync

## Domain Context
- Git operations executed via `/usr/bin/git` through `Process`
- Diff parsing performed in Swift (custom `DiffParser`)
- Recent repositories stored via `UserDefaults` (through `RecentRepositoriesStore`)
- Core Data model: `Item` entity (default template, currently unused for Git data)

## Important Constraints
- macOS-only (minimum deployment target 26.2)
- Sandboxing disabled (`ENABLE_APP_SANDBOX = NO`) to allow Git CLI access
- Hardened runtime enabled
- No App Sandbox = careful with file system access outside selected repo

## External Dependencies
- Git CLI (system-installed `/usr/bin/git`)
- No external Swift packages or CocoaPods/SPM dependencies
