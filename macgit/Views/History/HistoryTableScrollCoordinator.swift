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
import QuartzCore
import SwiftUI

@MainActor
final class HistoryTableScrollCoordinator {
    private weak var tableView: NSTableView?
    private let defaults: UserDefaults
    private let widthsKey = "history.tableColumnWidths"
    private var columnResizeObserver: NSObjectProtocol?
    private var restoreWidthsTask: Task<Void, Never>?
    private var isRestoringWidths = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        restoreWidthsTask?.cancel()
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
    }

    @discardableResult
    func attach(from view: NSView) -> Bool {
        var candidate = view.superview
        while let current = candidate {
            if let tableView = current as? NSTableView {
                if self.tableView !== tableView {
                    self.tableView = tableView
                    observeColumnResizing(of: tableView)
                    restoreSavedWidths()
                }
                return true
            }
            candidate = current.superview
        }
        return false
    }

    private func observeColumnResizing(of tableView: NSTableView) {
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
        columnResizeObserver = NotificationCenter.default.addObserver(
            forName: tableView is NSOutlineView
                ? NSOutlineView.columnDidResizeNotification
                : NSTableView.columnDidResizeNotification,
            object: tableView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      !self.isRestoringWidths,
                      let tableView = self.tableView,
                      let headerView = tableView.headerView,
                      headerView.resizedColumn >= 0 else { return }

                // resizedColumn is valid during AppKit's tracking loop. Reading
                // currentEvent later can miss the drag or see a different event.
                self.restoreWidthsTask?.cancel()
                var widths = self.defaults.dictionary(forKey: self.widthsKey) ?? [:]
                for column in tableView.tableColumns where !column.isHidden {
                    guard let key = Self.columnKey(column),
                          column.width.isFinite, column.width > 0 else { continue }
                    widths[key] = Double(column.width)
                }
                self.defaults.set(widths, forKey: self.widthsKey)
            }
        }
    }

    private func restoreSavedWidths() {
        restoreWidthsTask?.cancel()
        let widths = defaults.dictionary(forKey: widthsKey) as? [String: Double] ?? [:]
        guard !widths.isEmpty else { return }

        restoreWidthsTask = Task { @MainActor [weak self] in
            // Cells can attach before SwiftUI finishes configuring the native
            // columns. Verify the widths across subsequent layout passes.
            var stablePasses = 0
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled, let self, let tableView = self.tableView else { return }
                guard tableView.window != nil,
                      let scrollView = tableView.enclosingScrollView,
                      scrollView.contentView.bounds.width > 0 else { continue }

                self.isRestoringWidths = true
                tableView.layoutSubtreeIfNeeded()
                let columns = tableView.tableColumns.compactMap { column -> (NSTableColumn, CGFloat)? in
                    guard !column.isHidden,
                          let key = Self.columnKey(column),
                          let width = widths[key], width.isFinite, width > 0 else { return nil }
                    return (column, min(column.maxWidth, max(column.minWidth, CGFloat(width))))
                }
                let matches = !columns.isEmpty && columns.allSatisfy { abs($0.0.width - $0.1) < 0.5 }
                if matches {
                    stablePasses += 1
                } else {
                    stablePasses = 0
                    // Otherwise each assignment can resize the other columns,
                    // so the final widths no longer match the saved snapshot.
                    let autoresizingStyle = tableView.columnAutoresizingStyle
                    tableView.columnAutoresizingStyle = .noColumnAutoresizing
                    for (column, width) in columns {
                        column.width = width
                    }
                    tableView.columnAutoresizingStyle = autoresizingStyle
                }
                self.isRestoringWidths = false
                if stablePasses >= 2 { return }
            }
        }
    }

    private static func columnKey(_ column: NSTableColumn) -> String? {
        // SwiftUI's native identifiers are fresh UUIDs on every mount. Header
        // titles remain stable even when the user reorders or hides columns.
        let key = column.title.lowercased()
        return ["message", "author", "date", "commit"].contains(key) ? key : nil
    }

    func scrollToRowWhenReady(_ row: Int) async {
        for _ in 0..<30 {
            if scrollToRow(row) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @discardableResult
    private func scrollToRow(_ row: Int) -> Bool {
        guard let tableView,
              tableView.numberOfRows > row,
              row >= 0,
              let scrollView = tableView.enclosingScrollView else {
            return false
        }

        let rowRect = tableView.rect(ofRow: row)
        let clipView = scrollView.contentView
        guard !clipView.bounds.intersects(rowRect) else { return true }

        let maximumY = max(0, tableView.bounds.height - clipView.bounds.height)
        let targetY = min(
            maximumY,
            max(0, rowRect.midY - clipView.bounds.height / 2)
        )
        let targetOrigin = CGPoint(x: clipView.bounds.origin.x, y: targetY)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(targetOrigin)
        }
        return true
    }
}

struct HistoryTableIntrospectionView: NSViewRepresentable {
    let coordinator: HistoryTableScrollCoordinator

    func makeNSView(context: Context) -> HistoryTableIntrospectionNSView {
        HistoryTableIntrospectionNSView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: HistoryTableIntrospectionNSView, context: Context) {
        nsView.coordinator = coordinator
        nsView.attachIfPossible()
    }
}

final class HistoryTableIntrospectionNSView: NSView {
    weak var coordinator: HistoryTableScrollCoordinator?
    private var attachRetryCount = 0

    init(coordinator: HistoryTableScrollCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfPossible()
    }

    func attachIfPossible() {
        guard let coordinator else { return }
        if coordinator.attach(from: self) {
            attachRetryCount = 0
        } else if attachRetryCount < 30 {
            attachRetryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.attachIfPossible()
            }
        }
    }
}
