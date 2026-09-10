# Terminal repository opening roadmap

- [completed] [CLI, URL routing, installation and verification](2026-09-10-terminal-open-implementation.md)

Authorized behavior: `commit`, `commit .`, or `commit <folder>` validates a Git working tree in Terminal before asking Commit+ to open it. Invalid folders return stderr and nonzero status without launching the app. The app revalidates incoming URLs. Existing repository windows are focused; otherwise use the receiving empty window or open another window.

- [completed] [Launch setup tip and automatic shell PATH configuration](2026-09-10-terminal-open-implementation.md#launch-setup-tip-and-automatic-path-configuration).
