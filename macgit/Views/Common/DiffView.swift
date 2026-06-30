//
//  DiffView.swift
//  macgit
//

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

struct DiffView: View {
    let hunks: [DiffHunk]
    let file: StatusFile?
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    let onRefresh: () -> Void
    let onError: (String) -> Void
    let filePath: String?
    let gitRef: String?

    init(
        hunks: [DiffHunk],
        file: StatusFile? = nil,
        repositoryURL: URL? = nil,
        undoManager: GitUndoManager? = nil,
        onRefresh: @escaping () -> Void = {},
        onError: @escaping (String) -> Void = { _ in },
        filePath: String? = nil,
        gitRef: String? = nil
    ) {
        self.hunks = hunks
        self.file = file
        self.repositoryURL = repositoryURL
        self.undoManager = undoManager
        self.onRefresh = onRefresh
        self.onError = onError
        self.filePath = filePath
        self.gitRef = gitRef
    }

    @State private var selectedLineIDs: Set<UUID> = []
    @State private var lastSelectedLineID: UUID?
    @State private var loadedImage: NSImage?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp",
        "tiff", "tif", "ico", "heic", "heif", "raw",
        "cr2", "nef", "arw", "dng"
    ]

    private var isImageFile: Bool {
        if let file = file { return file.isImage }
        guard let path = filePath else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    var body: some View {
        if hunks.isEmpty && isImageFile {
            imagePreview
        } else if hunks.isEmpty {
            EmptyStateView(message: "No diff to display", detail: "Select a file to see changes")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(hunks) { hunk in
                        HunkView(
                            hunk: hunk,
                            file: file,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            selectedLineIDs: $selectedLineIDs,
                            lastSelectedLineID: $lastSelectedLineID,
                            onRefresh: onRefresh,
                            onError: onError
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let file = file, let url = repositoryURL {
            let fileURL = url.appendingPathComponent(file.path)
            diskImagePreview(fileURL: fileURL, filePath: file.path)
        } else if let ref = gitRef, let url = repositoryURL, let path = filePath {
            gitImagePreview(ref: ref, url: url, path: path)
        } else {
            EmptyStateView(icon: "photo", message: "Unable to preview image")
        }
    }

    private func diskImagePreview(fileURL: URL, filePath: String) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: fileURL) {
                imageDisplayView(nsImage)
            } else {
                EmptyStateView(icon: "photo", message: "Unable to preview image", detail: filePath)
            }
        }
    }

    private func gitImagePreview(ref: String, url: URL, path: String) -> some View {
        Group {
            if let image = loadedImage {
                imageDisplayView(image)
            } else {
                ProgressView("Loading image…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadImageFromGit(ref: ref, url: url, path: path)
        }
    }

    private func loadImageFromGit(ref: String, url: URL, path: String) async {
        do {
            let data = try await GitStatusService.shared.showFile(at: path, ref: ref, in: url)
            if let image = NSImage(data: data) {
                loadedImage = image
            }
        } catch {
            onError("Failed to load image: \(error.localizedDescription)")
        }
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

struct HunkView: View {
    let hunk: DiffHunk
    let file: StatusFile?
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    @Binding var selectedLineIDs: Set<UUID>
    @Binding var lastSelectedLineID: UUID?
    let onRefresh: () -> Void
    let onError: (String) -> Void

    private var isStaged: Bool {
        guard let file = file else { return false }
        return file.status == .staged || file.status == .added || file.status == .renamed
    }

    private var isUntracked: Bool {
        file?.status == .untracked
    }

    private var isConflict: Bool {
        file?.status == .conflict
    }

    private var canInteract: Bool {
        !isUntracked && !isConflict && file != nil && repositoryURL != nil
    }

    private var hasSelectedLines: Bool {
        !selectedLineIDs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header
            HStack(spacing: 10) {
                Text(hunk.header)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if canInteract {
                    if isStaged {
                        Button("Unstage") {
                            unstageHunk()
                        }
                        .buttonStyle(GlassButtonStyle(tint: .yellow, fontSize: 10))
                    } else {
                        Button("Stage") {
                            stageHunk()
                        }
                        .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 10))

                        Button("Discard") {
                            let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                            performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                        .buttonStyle(GlassButtonStyle(tint: .red, fontSize: 10))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.06))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
            .contextMenu {
                hunkContextMenu
            }

            // Lines
            ScrollView([.horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunk.lines.enumerated()), id: \.element.id) { index, line in
                        DiffLineView(
                            line: line,
                            isSelected: selectedLineIDs.contains(line.id)
                        )
                        .onTapGesture {
                            handleLineTap(at: index)
                        }
                        .contextMenu {
                            lineContextMenu(for: line)
                        }
                    }
                }
                .background(.background)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var hunkContextMenu: some View {
        Group {
            if canInteract {
                if isStaged {
                    Button("Unstage Hunk") {
                        unstageHunk()
                    }
                    if hasSelectedLines {
                        Divider()
                        Button("Unstage Selected Lines") {
                            unstageSelectedLines()
                        }
                    }
                } else {
                    Button("Stage Hunk") {
                        stageHunk()
                    }
                    Button("Discard Hunk") {
                        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                        performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                    }

                    if hasSelectedLines {
                        Divider()
                        Button("Stage Selected Lines") {
                            stageSelectedLines()
                        }
                        Button("Discard Selected Lines") {
                            let lines = expandedSelectedLines(for: hunk)
                            let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file!.path)
                            performPatchAction(label: "Discard selected lines in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                    }
                }
            }
        }
    }

    private func lineContextMenu(for line: DiffLine) -> some View {
        Group {
            if canInteract {
                if isStaged {
                    Button("Unstage Hunk") {
                        unstageHunk()
                    }
                    if selectedLineIDs.contains(line.id) && hasSelectedLines {
                        Divider()
                        Button("Unstage Selected Lines") {
                            unstageSelectedLines()
                        }
                    }
                } else {
                    Button("Stage Hunk") {
                        stageHunk()
                    }
                    Button("Discard Hunk") {
                        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                        performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                    }

                    if selectedLineIDs.contains(line.id) && hasSelectedLines {
                        Divider()
                        Button("Stage Selected Lines") {
                            stageSelectedLines()
                        }
                        Button("Discard Selected Lines") {
                            let lines = expandedSelectedLines(for: hunk)
                            let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file!.path)
                            performPatchAction(label: "Discard selected lines in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                    }
                }
            }
            Divider()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.text, forType: .string)
            }
        }
    }

    private func handleLineTap(at index: Int) {
        let line = hunk.lines[index]
        guard line.type == .added || line.type == .removed else { return }

        let flags = NSEvent.modifierFlags
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)

        if isShift {
            guard let lastID = lastSelectedLineID,
                  let lastIndex = hunk.lines.firstIndex(where: { $0.id == lastID }) else {
                selectedLineIDs = [line.id]
                lastSelectedLineID = line.id
                return
            }
            let start = min(lastIndex, index)
            let end = max(lastIndex, index)
            let rangeIDs = Set(hunk.lines[start...end].filter { $0.type == .added || $0.type == .removed }.map(\.id))
            if isCommand {
                selectedLineIDs.formSymmetricDifference(rangeIDs)
            } else {
                selectedLineIDs = rangeIDs
            }
            lastSelectedLineID = line.id
        } else if isCommand {
            if selectedLineIDs.contains(line.id) {
                selectedLineIDs.remove(line.id)
            } else {
                selectedLineIDs.insert(line.id)
            }
            lastSelectedLineID = line.id
        } else {
            selectedLineIDs = [line.id]
            lastSelectedLineID = line.id
        }
    }

    private func expandedSelectedLines(for hunk: DiffHunk) -> [DiffLine] {
        var blocks: [Set<UUID>] = []
        var currentBlock = Set<UUID>()

        for line in hunk.lines {
            switch line.type {
            case .added, .removed:
                currentBlock.insert(line.id)
            case .context, .header, .conflictMarker:
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                    currentBlock = []
                }
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        var expandedIDs = Set<UUID>()
        for block in blocks {
            if !block.isDisjoint(with: selectedLineIDs) {
                expandedIDs.formUnion(block)
            }
        }

        return hunk.lines.filter { expandedIDs.contains($0.id) }
    }

    private func stageHunk() {
        guard let file else { return }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        performPatchAction(
            label: "Stage hunk in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: false
        )
    }

    private func unstageHunk() {
        guard let file else { return }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        performPatchAction(
            label: "Unstage hunk in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: true
        )
    }

    private func stageSelectedLines() {
        guard let file else { return }
        let lines = expandedSelectedLines(for: hunk)
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        performPatchAction(
            label: "Stage selected lines in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: false
        )
    }

    private func unstageSelectedLines() {
        guard let file else { return }
        let lines = expandedSelectedLines(for: hunk)
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        performPatchAction(
            label: "Unstage selected lines in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: true
        )
    }

    private func performPatchAction(
        label: String,
        patch: String,
        cached: Bool,
        reverse: Bool
    ) {
        guard let repositoryURL else { return }
        perform {
            try await GitStatusService.shared.applyPatch(
                patch,
                in: repositoryURL,
                cached: cached,
                reverse: reverse
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.applyPatch(
                        repositoryURL: repositoryURL,
                        label: label,
                        patch: patch,
                        cached: cached,
                        reverse: reverse
                    )
                )
            }
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                await MainActor.run {
                    selectedLineIDs.removeAll()
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine
    let isSelected: Bool

    var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        switch line.type {
        case .added:
            return Color.green.opacity(0.08)
        case .removed:
            return Color.red.opacity(0.08)
        case .context:
            return Color.clear
        case .header:
            return Color.clear
        case .conflictMarker:
            return Color.purple.opacity(0.10)
        }
    }

    var textColor: Color {
        switch line.type {
        case .added:
            return Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.18, alpha: 1.0))
        case .removed:
            return Color(nsColor: NSColor(calibratedRed: 0.75, green: 0.18, blue: 0.18, alpha: 1.0))
        case .context:
            return .primary
        case .header:
            return .secondary
        case .conflictMarker:
            return Color.purple
        }
    }

    var prefix: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        case .header: return ""
        case .conflictMarker: return "!"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // New line number
            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // Prefix
            if !prefix.isEmpty {
                Text(prefix)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.7))
                    .frame(width: 14, alignment: .center)
            }

            // Content
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(backgroundColor)
    }
}
