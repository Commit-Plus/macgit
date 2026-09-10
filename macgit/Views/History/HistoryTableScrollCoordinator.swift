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
    private weak var observedClipView: NSClipView?
    private let defaults: UserDefaults
    private let ratiosKey = "history.tableColumnRatios"
    private var columnRatios: [String: Double]
    private var viewportObservers: [NSObjectProtocol] = []
    private var lastViewportWidth: CGFloat = 0
    private var lastVisibleColumns: [String] = []
    private var appliedWidths: [String: CGFloat] = [:]
    private var columnResizeObserver: NSObjectProtocol?
    private var restoreWidthsTask: Task<Void, Never>?
    private var isRestoringWidths = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial = ["message": 0.45, "author": 0.25, "date": 0.18, "commit": 0.12]
        let saved = defaults.dictionary(forKey: ratiosKey) as? [String: Double]
        let legacy = defaults.dictionary(forKey: "history.tableColumnWidths") as? [String: Double]
        let valid = (saved ?? legacy ?? initial).filter {
            initial[$0.key] != nil && $0.value.isFinite && $0.value > 0
        }
        let total = valid.values.reduce(0, +)
        columnRatios = initial.merging(valid.mapValues { $0 / max(total, 1e-9) }) { _, saved in saved }
    }

    deinit {
        restoreWidthsTask?.cancel()
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
        for observer in viewportObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    func attach(from view: NSView) -> Bool {
        var candidate = view.superview
        while let current = candidate {
            if let tableView = current as? NSTableView {
                if self.tableView !== tableView {
                    self.tableView = tableView
                    lastViewportWidth = 0
                    lastVisibleColumns = []
                    appliedWidths = [:]
                    tableView.columnAutoresizingStyle = .noColumnAutoresizing
                    observeColumnResizing(of: tableView)
                    restoreSavedWidths()
                }
                observeViewport(of: tableView)
                resizeForViewportIfNeeded()
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

                self.restoreWidthsTask?.cancel()
                self.captureColumnResize(in: tableView, index: headerView.resizedColumn)
            }
        }
    }

    private func observeViewport(of tableView: NSTableView) {
        let clipView = tableView.enclosingScrollView?.contentView
        guard observedClipView !== clipView else { return }
        observedClipView = clipView
        for observer in viewportObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        viewportObservers = []
        guard let clipView else { return }
        clipView.postsFrameChangedNotifications = true
        clipView.postsBoundsChangedNotifications = true
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            viewportObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: clipView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resizeForViewportIfNeeded()
                }
            })
        }
    }

    private var visibleColumns: [NSTableColumn] {
        tableView?.tableColumns.filter { !$0.isHidden && Self.columnKey($0) != nil } ?? []
    }

    private func availableWidth(for columns: [NSTableColumn]) -> CGFloat {
        guard let tableView, let clipView = tableView.enclosingScrollView?.contentView else { return 0 }
        // AppKit includes an intercell gap in each column's horizontal extent.
        return max(0, clipView.bounds.width - CGFloat(columns.count) * tableView.intercellSpacing.width)
    }

    private func resizeForViewportIfNeeded() {
        guard !isRestoringWidths, let tableView,
              let clipView = tableView.enclosingScrollView?.contentView,
              clipView.bounds.width > 0 else { return }
        let keys = visibleColumns.compactMap(Self.columnKey)
        guard abs(lastViewportWidth - clipView.bounds.width) > 0.01 || keys != lastVisibleColumns else { return }
        applyColumnRatios()
    }

    private func applyColumnRatios() {
        let columns = visibleColumns
        guard !columns.isEmpty, availableWidth(for: columns) > 0 else { return }
        let weights = columns.map { CGFloat(columnRatios[Self.columnKey($0)!] ?? 1) }
        var widths = Array(repeating: CGFloat.zero, count: columns.count)
        var remaining = max(availableWidth(for: columns), columns.reduce(0) { $0 + $1.minWidth })
        var pending = Array(columns.indices)
        // Pin columns that reach their minimum, then redistribute the remaining
        // space proportionally. Window resizing never overwrites user ratios.
        while !pending.isEmpty {
            let totalWeight = pending.reduce(CGFloat.zero) { $0 + weights[$1] }
            let constrained = pending.filter { remaining * weights[$0] / totalWeight < columns[$0].minWidth }
            if constrained.isEmpty {
                for index in pending {
                    widths[index] = remaining * weights[index] / totalWeight
                }
                break
            }
            for index in constrained {
                widths[index] = columns[index].minWidth
                remaining -= widths[index]
            }
            pending.removeAll { constrained.contains($0) }
        }
        setWidths(widths, for: columns)
    }

    private func captureColumnResize(in tableView: NSTableView, index: Int) {
        guard tableView.tableColumns.indices.contains(index) else { return }
        let columns = visibleColumns
        guard let active = columns.firstIndex(where: { $0 === tableView.tableColumns[index] }) else { return }
        var widths = columns.map { appliedWidths[Self.columnKey($0)!] ?? $0.width }
        widths[active] = max(columns[active].minWidth, columns[active].width)
        let target = max(availableWidth(for: columns), columns.reduce(0) { $0 + $1.minWidth })
        var excess = widths.reduce(0, +) - target
        // Prefer the next visible column, then the nearest remaining neighbors.
        let neighbors = Array(columns.indices.dropFirst(active + 1)) + Array(columns.indices.prefix(active).reversed())
        for neighbor in neighbors {
            let adjustment = max(columns[neighbor].minWidth - widths[neighbor], -excess)
            widths[neighbor] += adjustment
            excess += adjustment
            if abs(excess) < 0.01 { break }
        }
        widths[active] = max(columns[active].minWidth, widths[active] - excess)
        setWidths(widths, for: columns)
        let total = widths.reduce(0, +)
        guard total > 0 else { return }
        let visibleWeight = columns.reduce(0.0) { $0 + (columnRatios[Self.columnKey($1)!] ?? 0) }
        for (column, width) in zip(columns, widths) {
            columnRatios[Self.columnKey(column)!] = Double(width / total) * max(visibleWeight, 1e-9)
        }
        defaults.set(columnRatios, forKey: ratiosKey)
    }

    private func setWidths(_ widths: [CGFloat], for columns: [NSTableColumn]) {
        guard let tableView else { return }
        isRestoringWidths = true
        defer { isRestoringWidths = false }
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        for (column, width) in zip(columns, widths) {
            if abs(column.width - width) > 0.01 {
                column.width = width
            }
            appliedWidths[Self.columnKey(column)!] = column.width
        }
        tableView.tile()
        lastViewportWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? 0
        lastVisibleColumns = columns.compactMap(Self.columnKey)
    }

    private func restoreSavedWidths() {
        restoreWidthsTask?.cancel()
        restoreWidthsTask = Task { @MainActor [weak self] in
            // SwiftUI can configure columns after cells first attach.
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled, let self, let tableView = self.tableView else { return }
                guard tableView.window != nil else { continue }
                tableView.layoutSubtreeIfNeeded()
                self.observeViewport(of: tableView)
                self.applyColumnRatios()
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
