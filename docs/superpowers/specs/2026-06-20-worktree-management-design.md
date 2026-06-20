# Worktree Management Feature — Design Spec

**Date:** 2026-06-20
**Status:** Approved (brainstorm phase)
**Author:** brainstorm session

## Purpose

Thêm tính năng quản lý Git worktree vào Commit+ (macgit) để user — đặc biệt khi chạy nhiều AI agent trên nhiều task độc lập — dễ dàng tạo, mở, theo dõi và dọn worktree mà không cần CLI. Tính năng này cho phép nhiều branch được checkout đồng thời tại các path khác nhau, mỗi worktree mở trong một cửa sổ Commit+ riêng.

## Scope (v1)

Tất cả 9 thao tác:

1. **List** — hiển thị tất cả worktree của repo (path, branch, status dirty/clean, label, lock state)
2. **Create** — tạo worktree mới (chọn branch hoặc tạo branch mới + base, editable path, optional label)
3. **Open** — mở worktree trong cửa sổ Commit+ mới
4. **Delete/Remove** — xóa worktree, có guard dirty/locked, force option
5. **Switch/Checkout** — đổi branch của một worktree đang có
6. **Prune** — dọn worktree đã mất path + label mồ côi
7. **Lock/Unlock** — `git worktree lock`/`unlock` (cho AI agent scenario dài hạn)
8. **Rename** — `git worktree move` + cập nhật label sidecar key
9. **Status/Label** — tag worktree với task name tự do; hiển thị label nếu có, không thì branch name

## Approach

**Approach 1: Service extension + sidecar label file** (đã chọn)

- `GitStatusService+Worktree.swift` — extension mới chạy git ops thuần.
- `WorktreeLabelStore.swift` — sidecar `.git/macgit/worktree-labels.json` map `path → label`.
- `WorktreeEntry.swift` — model.
- Sidebar section mới trong `SidebarView`, pattern y hệt STASHES.
- "Open worktree" re-use `AppState.newWindowRepoURL` mechanism.

Lý do: nhất quán 100% với codebase hiện tại (extension + sidecar store + sidebar section), ít rủi ro, đủ chỗ mở rộng (busy detection, agent tracking) sau mà không cần refactor. Approach 2 (WorktreeManager actor) và Approach 3 (Worktree-aware AppState) bị loại vì break pattern và over-engineering cho v1.

## Architecture & Components

```
macgit/
├── Services/
│   ├── GitStatusService+Worktree.swift   [NEW] — git worktree ops (list/add/remove/lock/prune/move/checkout)
│   ├── WorktreeLabelStore.swift          [NEW] — sidecar read/write .git/macgit/worktree-labels.json
│   └── WorktreeEntry.swift               [NEW] — model: path, branch, HEAD, locked, dirtyCount, label
├── Views/
│   └── MainWindow/
│       └── SidebarView.swift             [EDIT] — thêm section WORKTREES (pattern STASHES)
├── App/
│   └── macgitApp.swift                   [EDIT] — menu item Window > Worktrees / Cmd+Shift+W (optional, jump to section)
└── macgitTests/
    ├── WorktreeServiceTests.swift        [NEW] — integration tests git ops
    └── WorktreeLabelStoreTests.swift     [NEW] — integration tests label sidecar
```

**Phân chia trách nhiệm:**

- `GitStatusService+Worktree` — chỉ git ops thuần, trả về `WorktreeEntry` (chưa có label). Không biết sidecar.
- `WorktreeLabelStore` — đọc/ghi sidecar JSON trong `.git/macgit/worktree-labels.json`, map `path → label`. Prune entries mồ côi khi list worktree.
- `SidebarView` — merge `WorktreeEntry` từ git với label từ store, render section. Context menu gọi các service ops.

**Không thay đổi**: `AppState`, window management, `GitStatusService` core. "Open worktree" chỉ là spawn window với `repoURL = worktree.path` — re-use đường mở repo hiện có.

## Data Flow

**Load worktrees (sidebar `.task` + on `.repositoryDidChange`):**

```
SidebarView.task
  ├─ GitStatusService.worktrees(in: repoURL) -> [WorktreeEntry]   (git worktree list --porcelain)
  ├─ WorktreeLabelStore.labels(in: repoURL) -> [Path: String]      (read sidecar)
  ├─ For each entry: entry.label = labels[entry.path]
  └─ SidebarView.worktreeEntries = merged
```

**Create worktree (sheet submit):**

```
1. GitStatusService.addWorktree(path:branch:in:)   → git worktree add <path> <branch>
   ├─ fail → throw GitError, sheet stays, show error
   └─ ok   → continue
2. (if label provided) WorktreeLabelStore.setLabel(path:label:in:)
3. NotificationCenter.post(.repositoryDidChange)   → sidebar reloads
4. (optional toggle) spawn window cho worktree mới
```

**Delete worktree (context menu, confirm):**

```
1. Guard: entry.dirtyCount == 0  → else alert "worktree has uncommitted changes, force?"
2. GitStatusService.removeWorktree(path:force:in:)  → git worktree remove [--force] <path>
3. WorktreeLabelStore.removeLabel(path:in:)          → cleanup sidecar
4. .repositoryDidChange
```

**Lock/Unlock, Rename, Prune** — tương tự: gọi service op → (label update nếu rename) → `.repositoryDidChange`.

**Open in Terminal** — re-use `NSWorkspace`/`open -a Terminal` pattern hiện có với `worktree.path`.

**Window spawn cho "Open worktree"** — re-use `AppState.newWindowRepoURL` mechanism: set `appState.newWindowRepoURL = worktree.path`, `macgitApp` handle `.onChange` mở `MainWindowView` mới.

**Refresh strategy**: mọi mutation post `.repositoryDidChange`, sidebar subscribe reload list (giống BRANCHES/STASHES). Không polling.

## Git Worktree Commands

| Operation | Git command | Parse / ghi chú |
|-----------|-------------|------------------|
| **list** | `git worktree list --porcelain` | Parse blocks: `worktree <path>`, `HEAD <sha>`, `branch <ref>`, `locked` (line hiện diện = true). Dirty count: chạy thêm `git status --porcelain` trong từng worktree path (song song via `withTaskGroup`). |
| **add** | `git worktree add <path> <branch>` | Branch phải tồn tại; để tạo branch mới: `git worktree add -b <new> <path> [<base>]` (sheet có option "new branch from base"). |
| **remove** | `git worktree remove [--force] <path>` | `--force` khi dirty hoặc locked. |
| **prune** | `git worktree prune` | Dọn entry đã mất path. |
| **lock** | `git worktree lock <path> --reason "<text>"` | Reason optional (AI agent scenario). |
| **unlock** | `git worktree unlock <path>` | |
| **move** | `git worktree move <old> <new>` | Rename = move. Update label sidecar path key. |
| **checkout** (switch branch trong worktree) | `git -C <worktree-path> checkout <branch>` | Không phải `worktree` subcommand; dùng `-C` để chạy trong worktree path. |

**WorktreeEntry fields:**

```swift
struct WorktreeEntry: Identifiable, Equatable {
    let id = UUID()
    let path: URL
    let head: String          // short sha
    let branch: String?       // nil khi detached
    let isLocked: Bool
    let dirtyCount: Int       // -1 nếu không đọc được status
    var label: String?        // từ WorktreeLabelStore, merged sau
}
```

**Edge cases cần xử lý:**

- Worktree chính (repo gốc) cũng xuất hiện trong `git worktree list` — đánh dấu là "main" trong UI (italic/grey, disable remove).
- Detached HEAD worktree (không có branch) — `branch = nil`, hiển thị `HEAD <sha>`.
- Locked worktree — icon khóa, disable remove.
- `dirtyCount` chạy song song cho tất cả worktree via `withTaskGroup` (pattern đã dùng ở `loadBranches` cho sync status).

## UI & Sidebar

Section mới `WORKTREES` trong sidebar, pattern theo STASHES.

**Row rendering:**

- **Main worktree** (repo gốc) — dấu ● màu accent, tên *italic*, badge `(this)`, không có context menu remove/lock.
- **Worktree thường** — icon 📁, tên = label nếu có, không thì branch name.
- **Locked** — icon 🔒.
- **Detached** — tên "detached" + short sha.
- **Dirty badge** — số file thay đổi, màu cam (như badge ahead/behind hiện có).
- **Label hiển thị** — label ưu tiên branch name; nếu không có label, hiện branch.

**Interactions:**

- **Single click** — select (giống branch row).
- **Double click** — open worktree trong window mới.
- **Context menu** — Open / Open in Terminal / Set Label… / Rename… / Lock… / Unlock / Switch Branch… / Remove / Prune (section header).
- **Section header** — collapse/expand; nút `+` để tạo worktree mới (hoặc context menu trên header).

**Create Worktree sheet:**

- `Branch` — picker (existing branches) *hoặc* "new branch" textfield + base commit field.
- `Path` — textfield, default `<repo>/.worktrees/<name>`, editable.
- `Label` — textfield optional.
- `Open after create` — checkbox (mặc định on).
- Buttons: Create / Cancel. Error alert inline nếu git fail.

## Error Handling & Guards

Destructive operations có guards (pattern Git Undo):

| Operation | Guard | Behavior khi guard fail |
|-----------|-------|------------------------|
| **remove** | `dirtyCount == 0 && !isLocked` | Alert: "Worktree có N uncommitted changes. Force remove?" → nếu yes, `--force`. |
| **remove main worktree** | luôn chặn | Row disable, context menu không hiện Remove. |
| **remove locked** | `!isLocked` | Alert: "Worktree is locked. Unlock first or force?" |
| **move** | target path chưa tồn tại | Alert inline trong sheet rename. |
| **checkout (switch branch)** | worktree clean hoặc `--force` | Alert confirm nếu dirty (giống checkout branch hiện có). |
| **prune** | an toàn, không guard | Chỉ dọn entry đã mất path + sidecar label mồ côi. |

**Lỗi git (network, permission, invalid state):**

- Dùng `GitError` hiện có, `throw` từ service.
- Sidebar bắt lỗi trong `do/catch`, set `errorMessage` + `showingError` alert (pattern hiện có).
- Create/Rename sheet: lỗi inline trong sheet, sheet không dismiss.

**Label sidecar robustness:**

- File `.git/macgit/worktree-labels.json` có thể thiếu/corrupt → store return `[:]`, ghi đè khi set.
- Entry mồ côi (worktree bị xóa bằng CLI): `WorktreeLabelStore.prune(validPaths:)` được gọi sau mỗi `list`, xóa key không còn trong `git worktree list`.
- Label trùng path giữa các repo không conflict — sidecar nằm trong `.git/` của từng repo.

**Concurrency:**

- `GitStatusService` là actor (hoặc async methods) → git ops serialize tự nhiên.
- Dirty count song song via `withTaskGroup` — mỗi task chạy `git status --porcelain` trong một worktree path, fail nhẹ thì `dirtyCount = -1` (hiện badge `?`).

## Testing

**Integration tests với temp Git repo thật** (pattern `StashServiceTests`, `SidebarTreeBuilderTests` hiện có):

| Test group | Cases |
|------------|-------|
| **WorktreeListTests** | list empty (chỉ main), list 1 worktree, list multiple, parse locked, parse detached HEAD, parse branch ref |
| **WorktreeAddTests** | add with existing branch, add with new branch + base, add to custom path, add fail (path exists), add fail (branch missing) |
| **WorktreeRemoveTests** | remove clean, remove dirty → fail without force, remove dirty with force, remove locked without force → fail, remove main → guard chặn |
| **WorktreeLockTests** | lock with reason, unlock, list shows locked |
| **WorktreeMoveTests** | move to new path, label sidecar key updated, move fail (target exists) |
| **WorktreePruneTests** | prune after manual dir delete, prune cleans sidecar orphan |
| **WorktreeLabelStoreTests** | set/get/remove label, read missing file → `[:]`, corrupt JSON → `[:]`, prune orphans, label persists across list |
| **WorktreeCheckoutTests** | switch branch in worktree (clean), switch with dirty → fail without force |
| **SidebarMergeTests** (nếu feasible) | entry + label merge đúng, main worktree flagged |

**Test setup helper** (thêm trong `macgitTests/`):

- Tạo temp repo với `git init`, tạo vài commit + branch.
- `git worktree add` bằng CLI để setup state, rồi gọi `GitStatusService` methods để verify parse.
- Cleanup temp dir sau mỗi test.

**Không test**: UI rendering (SwiftUI view), window spawn (cần app runtime). Những thứ này verify thủ công khi chạy app.

**Vị trí**: `macgitTests/WorktreeServiceTests.swift` + `macgitTests/WorktreeLabelStoreTests.swift` (2 file, tách service và store).

## Out of Scope (v1)

- Busy indicator / process detection trong worktree — phức tạp và dễ sai, để phase sau.
- Auto-create from template ("New worktree for agent") — có thể thêm sau.
- Tab trong cùng window — giữ pattern "mỗi repo một window".
- Sync status across worktrees — chưa cần.
- Undo entries cho worktree ops (Git Undo roadmap) — phase riêng, không thuộc v1 này.
