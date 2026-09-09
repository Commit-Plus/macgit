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

// Standalone integration check; never launches Commit+ or displays a window.
// Compile together with HistoryTableScrollCoordinator.swift, then invoke the
// executable with `write <unique-suite>` and `read <same-suite>` in two processes.
import AppKit
import SwiftUI

@MainActor
private enum Fixture {
    static let suite = "dev.thanhtran.history-width-test.\(CommandLine.arguments[2])"
    static let defaults = UserDefaults(suiteName: suite)!
    static let widthsKey = "history.tableColumnWidths"
}

private struct Row: Identifiable {
    let id: Int
}

@MainActor
private struct CheckTable: View {
    @AppStorage("columns", store: Fixture.defaults) private var columns = TableColumnCustomization<Row>()
    @State private var selection: Set<Int> = []
    @State private var coordinator = HistoryTableScrollCoordinator(defaults: Fixture.defaults)

    var body: some View {
        GeometryReader { proxy in
            Table(of: Row.self, selection: $selection, columnCustomization: $columns) {
                TableColumn("Message") { _ in
                    Text("Message").background {
                        HistoryTableIntrospectionView(coordinator: coordinator)
                    }
                }
                .width(min: 120, ideal: proxy.size.width * 0.45, max: .infinity)
                .customizationID("message")
                .disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn("Author") { _ in Text("Author") }
                    .width(min: 140, ideal: proxy.size.width * 0.25, max: .infinity)
                    .customizationID("author")
                TableColumn("Date") { _ in Text("Date") }
                    .width(min: 100, ideal: proxy.size.width * 0.18, max: .infinity)
                    .customizationID("date")
                TableColumn("Commit") { _ in Text("Commit") }
                    .width(min: 72, ideal: proxy.size.width * 0.12, max: .infinity)
                    .customizationID("commit")
            } rows: {
                ForEach((0..<10).map { Row(id: $0) }) { row in TableRow(row) }
            }
            .tableStyle(.bordered)
            .controlSize(.small)
        }
    }
}

@main
private struct HistoryColumnWidthCheck {
    @MainActor
    static func main() {
        precondition(CommandLine.arguments.count == 3, "Usage: check write|read unique-suite")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        if CommandLine.arguments[1] == "read" {
            defer { Fixture.defaults.removePersistentDomain(forName: Fixture.suite) }
            let expected = Fixture.defaults.dictionary(forKey: "expectedWidths") as! [String: Double]
            assertWidths(snapshot(mount(window)), expected, "fresh process")
            print("PASS: restored widths in a fresh process")
            return
        }

        precondition(CommandLine.arguments[1] == "write")
        Fixture.defaults.removePersistentDomain(forName: Fixture.suite)
        var table = mount(window)
        precondition(table is NSOutlineView, "The fixture must exercise SwiftUI's outline-backed Table")
        for (index, delta) in [(0, -40.0), (1, 30.0), (2, -25.0), (3, -20.0)] {
            let before = snapshot(table)
            dragHeader(table, column: index, delta: delta, window: window)
            pump(window)
            let expected = snapshot(table)
            precondition(before != expected, "Header drag must resize column \(index)")
            assertWidths(savedWidths(), expected, "capture column \(index)")
            table = remount(window)
            assertWidths(snapshot(table), expected, "remount after resizing column \(index)")
            print("PASS: header drag, save and remount for column \(index)")
        }

        let expected = savedWidths()
        table.moveColumn(1, toColumn: 3)
        pump(window)
        table = remount(window)
        assertWidths(snapshot(table), expected, "reordered columns")

        // Programmatic layout must not replace the user's saved preferences.
        table.tableColumns[0].width += 25
        pump(window)
        assertWidths(savedWidths(), expected, "ignore layout changes")
        table = remount(window)
        assertWidths(snapshot(table), expected, "restore after layout changes")
        print("PASS: reordered columns and programmatic layout")

        Fixture.defaults.set(expected, forKey: "expectedWidths")
        Fixture.defaults.synchronize()
    }

    @MainActor
    private static func pump(_ window: NSWindow) {
        let end = Date().addingTimeInterval(0.3)
        repeat {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < end
    }

    @MainActor
    private static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable(in: $0) }.first
    }

    @MainActor
    private static func mount(_ window: NSWindow) -> NSTableView {
        window.contentView = NSHostingView(rootView: CheckTable())
        pump(window)
        return findTable(in: window.contentView!)!
    }

    @MainActor
    private static func remount(_ window: NSWindow) -> NSTableView {
        window.contentView = NSView()
        pump(window)
        return mount(window)
    }

    @MainActor
    private static func snapshot(_ table: NSTableView) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.title.lowercased(), Double($0.width)) })
    }

    @MainActor
    private static func savedWidths() -> [String: Double] {
        Fixture.defaults.dictionary(forKey: Fixture.widthsKey) as? [String: Double] ?? [:]
    }

    private static func assertWidths(_ actual: [String: Double], _ expected: [String: Double], _ context: String) {
        precondition(actual.count == expected.count && expected.allSatisfy { key, value in
            actual[key].map { abs($0 - value) < 0.5 } ?? false
        }, "\(context): expected \(expected), got \(actual)")
    }

    @MainActor
    private static func dragHeader(_ table: NSTableView, column: Int, delta: CGFloat, window: NSWindow) {
        let header = table.headerView!
        let start = header.convert(
            NSPoint(x: header.headerRect(ofColumn: column).maxX - 1, y: header.bounds.midY), to: nil
        )
        let end = NSPoint(x: start.x + delta, y: start.y)
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
        }
        // These events go only to this hidden fixture window's tracking loop.
        NSApp.postEvent(event(.leftMouseDragged, end), atStart: false)
        NSApp.postEvent(event(.leftMouseUp, end), atStart: false)
        header.mouseDown(with: event(.leftMouseDown, start))
    }
}
