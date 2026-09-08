# Phase 1: Reflog

Implement a Workspace Reflog item, read local Git reflogs with bounded loading, and show action, event, reference, target commit, actor and event date. Support HEAD and all references, search loaded events, refresh and selection preservation. Route commit inspection to History and recovery to the existing branch creation sheet using immutable commit hashes.

Reflogs are local and expire. Do not expose reflog deletion or implicit reset operations.

Validation: build the macOS target, verify parsing and Git behavior using temporary repositories, and check the diff. Do not launch the app.

Completed: macOS build passed; temporary Git repository and standalone Swift parser checks passed. Parser XCTest coverage added but the XCTest runner was not launched, following the build-only instruction. Runtime UI verification remains manual.

Detail layout: selecting an event opens a right-hand panel using the same PersistentHSplit as Pull Requests, with a dedicated autosave key. The close button clears selection; the table uses compact columns while details are open. Full event metadata and recovery actions remain available in the scrollable panel.

Pagination: request 30 events per Git command with --skip, append the next page near the last five visible rows, and prevent overlapping load-more requests. Keep a manual fallback for search. Refresh the existing range in 30-event batches and preserve duplicate event identities across page boundaries.
