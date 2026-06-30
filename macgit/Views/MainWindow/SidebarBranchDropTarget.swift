//
//  SidebarBranchDropTarget.swift
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
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarBranchDropTarget: NSViewRepresentable {
    let onTap: () -> Void
    let onTargetedChange: (Bool) -> Void
    let fallbackPayload: () -> GitDragPayload?
    let dragPayload: () -> GitDragPayload?
    let dragTitle: () -> String
    let onDragEnded: (GitDragPayload) -> Void
    let onDrop: (GitDragPayload) -> Bool

    func makeNSView(context: Context) -> DropTargetView {
        DropTargetView(
            onTap: onTap,
            onTargetedChange: onTargetedChange,
            fallbackPayload: fallbackPayload,
            dragPayload: dragPayload,
            dragTitle: dragTitle,
            onDragEnded: onDragEnded,
            onDrop: onDrop
        )
    }

    func updateNSView(_ nsView: DropTargetView, context: Context) {
        nsView.onTap = onTap
        nsView.onTargetedChange = onTargetedChange
        nsView.fallbackPayload = fallbackPayload
        nsView.dragPayload = dragPayload
        nsView.dragTitle = dragTitle
        nsView.onDragEnded = onDragEnded
        nsView.onDrop = onDrop
    }

    static func dismantleNSView(_ nsView: DropTargetView, coordinator: ()) {
        nsView.clearTargeted()
        nsView.unregisterDraggedTypes()
    }

    final class DropTargetView: NSView, NSDraggingSource {
        private static let payloadIdentifier = UTType.macgitGitDragPayload.identifier
        private static let payloadType = NSPasteboard.PasteboardType(payloadIdentifier)

        var onTap: () -> Void
        var onTargetedChange: (Bool) -> Void
        var fallbackPayload: () -> GitDragPayload?
        var dragPayload: () -> GitDragPayload?
        var dragTitle: () -> String
        var onDragEnded: (GitDragPayload) -> Void
        var onDrop: (GitDragPayload) -> Bool

        private var isTargeted = false
        private var dragStartEvent: NSEvent?
        private var activeDragPayload: GitDragPayload?

        init(
            onTap: @escaping () -> Void,
            onTargetedChange: @escaping (Bool) -> Void,
            fallbackPayload: @escaping () -> GitDragPayload?,
            dragPayload: @escaping () -> GitDragPayload?,
            dragTitle: @escaping () -> String,
            onDragEnded: @escaping (GitDragPayload) -> Void,
            onDrop: @escaping (GitDragPayload) -> Bool
        ) {
            self.onTap = onTap
            self.onTargetedChange = onTargetedChange
            self.fallbackPayload = fallbackPayload
            self.dragPayload = dragPayload
            self.dragTitle = dragTitle
            self.onDragEnded = onDragEnded
            self.onDrop = onDrop
            super.init(frame: .zero)
            registerForDraggedTypes([Self.payloadType])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            dragStartEvent = event
            onTap()
        }

        override func mouseDragged(with event: NSEvent) {
            guard activeDragPayload == nil,
                  dragStartEvent != nil,
                  let payload = dragPayload(),
                  let item = Self.pasteboardItem(for: payload)
            else {
                return
            }

            activeDragPayload = payload

            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let image = Self.dragImage(title: dragTitle())
            let frame = NSRect(
                x: 0,
                y: max(0, bounds.midY - image.size.height / 2),
                width: image.size.width,
                height: image.size.height
            )
            dragItem.setDraggingFrame(frame, contents: image)
            beginDraggingSession(with: [dragItem], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartEvent = nil
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            dragStartEvent = nil
            if let activeDragPayload {
                onDragEnded(activeDragPayload)
            }
            activeDragPayload = nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard canReadPayload(from: sender.draggingPasteboard) else {
                return []
            }

            setTargeted(true)
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard canReadPayload(from: sender.draggingPasteboard) else {
                setTargeted(false)
                return []
            }

            setTargeted(true)
            return .copy
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            canReadPayload(from: sender.draggingPasteboard)
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            setTargeted(false)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            setTargeted(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { setTargeted(false) }

            guard let payload = payload(from: sender.draggingPasteboard) ?? fallbackPayload() else {
                return false
            }

            return onDrop(payload)
        }

        func clearTargeted() {
            setTargeted(false)
        }

        private func setTargeted(_ targeted: Bool) {
            guard isTargeted != targeted else { return }

            isTargeted = targeted
            onTargetedChange(targeted)
        }

        private func canReadPayload(from pasteboard: NSPasteboard) -> Bool {
            if pasteboard.canReadItem(withDataConformingToTypes: [Self.payloadIdentifier]) {
                return true
            }

            if pasteboard.availableType(from: [Self.payloadType]) != nil {
                return true
            }

            return pasteboard.pasteboardItems?.contains { item in
                item.availableType(from: [Self.payloadType]) != nil
            } ?? false
        }

        private func payload(from pasteboard: NSPasteboard) -> GitDragPayload? {
            for item in pasteboard.pasteboardItems ?? [] {
                guard let data = item.data(forType: Self.payloadType),
                      let payload = try? GitDragPayload.decodeTransferData(data)
                else {
                    continue
                }

                return payload
            }

            guard let data = pasteboard.data(forType: Self.payloadType) else {
                return nil
            }

            return try? GitDragPayload.decodeTransferData(data)
        }

        static func pasteboardItem(for payload: GitDragPayload) -> NSPasteboardItem? {
            guard let data = try? GitDragPayload.encodeTransferData(payload) else {
                return nil
            }

            let item = NSPasteboardItem()
            item.setData(data, forType: payloadType)
            return item
        }

        private static func dragImage(title: String) -> NSImage {
            let displayTitle = title.isEmpty ? "Branch" : title
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            let text = NSString(string: displayTitle)
            let textSize = text.size(withAttributes: attributes)
            let imageSize = NSSize(
                width: max(96, textSize.width + 28),
                height: 28
            )
            let image = NSImage(size: imageSize)

            image.lockFocus()
            NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
            NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: imageSize),
                xRadius: 6,
                yRadius: 6
            ).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(
                roundedRect: NSRect(x: 0.5, y: 0.5, width: imageSize.width - 1, height: imageSize.height - 1),
                xRadius: 6,
                yRadius: 6
            ).stroke()
            text.draw(
                at: NSPoint(x: 14, y: (imageSize.height - textSize.height) / 2),
                withAttributes: attributes
            )
            image.unlockFocus()

            return image
        }
    }
}
