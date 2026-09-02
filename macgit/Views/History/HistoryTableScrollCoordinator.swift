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
    private weak var observedTableView: NSTableView?
    private var columnResizeObserver: NSObjectProtocol?
    private var applyColumnRatiosTask: Task<Void, Never>?
    private var isApplyingColumnRatios = false

    var onColumnResize: (([String: CGFloat], CGFloat) -> Void)?
    var desiredColumnRatios: [String: Double] = [:]

    deinit {
        applyColumnRatiosTask?.cancel()
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
    }

    @discardableResult
    func attach(from view: NSView) -> Bool {
        var candidate = view.superview
        while let current = candidate {
            if let tableView = current as? NSTableView {
                let isNewTableView = self.tableView !== tableView
                self.tableView = tableView
                observeColumnResizing(of: tableView)
                if isNewTableView {
                    scheduleApplyingColumnRatios()
                }
                return true
            }
            candidate = current.superview
        }
        return false
    }

    private func scheduleApplyingColumnRatios() {
        applyColumnRatiosTask?.cancel()
        applyColumnRatiosTask = Task { @MainActor [weak self] in
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if self?.applyColumnRatios() == true {
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    @discardableResult
    private func applyColumnRatios() -> Bool {
        guard let tableView,
              !desiredColumnRatios.isEmpty,
              let scrollView = tableView.enclosingScrollView else {
            return false
        }

        tableView.layoutSubtreeIfNeeded()
        let availableWidth = scrollView.contentView.bounds.width
        guard availableWidth > 0 else { return false }

        let visibleColumns = tableView.tableColumns.enumerated().compactMap { index, column -> (NSTableColumn, Double)? in
            guard let key = Self.columnKey(for: column, fallbackIndex: index),
                  let ratio = desiredColumnRatios[key],
                  ratio > 0 else {
                return nil
            }
            return (column, ratio)
        }
        let totalRatio = visibleColumns.reduce(0) { $0 + $1.1 }
        guard totalRatio > 0 else { return false }

        isApplyingColumnRatios = true
        defer { isApplyingColumnRatios = false }
        for (column, ratio) in visibleColumns {
            let targetWidth = availableWidth * CGFloat(ratio / totalRatio)
            column.width = min(column.maxWidth, max(column.minWidth, targetWidth))
        }
        return true
    }

    private func observeColumnResizing(of tableView: NSTableView) {
        guard observedTableView !== tableView else { return }

        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
        observedTableView = tableView
        columnResizeObserver = NotificationCenter.default.addObserver(
            forName: NSTableView.columnDidResizeNotification,
            object: tableView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureColumnWidths()
            }
        }
    }

    private func captureColumnWidths() {
        guard !isApplyingColumnRatios,
              let tableView else { return }
        let columns = tableView.tableColumns
        let totalWidth = columns.reduce(CGFloat.zero) { $0 + $1.width }
        guard totalWidth > 0 else { return }

        var widths: [String: CGFloat] = [:]
        for (index, column) in columns.enumerated() {
            guard let key = Self.columnKey(for: column, fallbackIndex: index) else { continue }
            widths[key] = column.width
        }
        onColumnResize?(widths, totalWidth)
    }

    private static func columnKey(
        for column: NSTableColumn,
        fallbackIndex: Int? = nil
    ) -> String? {
        let knownKeys = Set(["message", "author", "date", "commit"])
        let identifier = column.identifier.rawValue.lowercased()
        if knownKeys.contains(identifier) {
            return identifier
        }

        let titles = [column.title.lowercased(), column.headerCell.stringValue.lowercased()]
        if let title = titles.first(where: knownKeys.contains) {
            return title
        }

        guard let fallbackIndex,
              knownKeys.count > fallbackIndex else { return nil }
        return ["message", "author", "date", "commit"][fallbackIndex]
    }

    func scrollToRowWhenReady(_ row: Int) async {
        for _ in 0..<30 {
            if scrollToRow(row) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func persistCurrentColumnWidths() {
        captureColumnWidths()
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
    let desiredColumnRatios: [String: Double]
    let onColumnResize: (([String: CGFloat], CGFloat) -> Void)?

    func makeNSView(context: Context) -> HistoryTableIntrospectionNSView {
        coordinator.desiredColumnRatios = desiredColumnRatios
        coordinator.onColumnResize = onColumnResize
        return HistoryTableIntrospectionNSView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: HistoryTableIntrospectionNSView, context: Context) {
        coordinator.desiredColumnRatios = desiredColumnRatios
        coordinator.onColumnResize = onColumnResize
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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            coordinator?.persistCurrentColumnWidths()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
