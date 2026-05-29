//
//  MainWindowView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainWindowView: View {
    let repositoryURL: URL
    @State private var selectedItem: SidebarItem? = .fileStatus
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            Group {
                switch selectedItem {
                case .fileStatus:
                    FileStatusView(repositoryURL: repositoryURL)
                case .history:
                    HistoryView(repositoryURL: repositoryURL)
                case .search:
                    SearchView(repositoryURL: repositoryURL)
                case .none:
                    EmptyStateView(message: "Select an item from the sidebar")
                }
            }
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(key: WindowWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(WindowWidthKey.self) { newWidth in
            windowWidth = newWidth
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                leftToolbar
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image("code-branch")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                    Text(repositoryURL.lastPathComponent)
                        .font(.headline)
                }
                .padding(.horizontal, 12)
            }

            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "network", label: "Remote", action: {})
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "folder", label: "Finder", action: {})
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "terminal", label: "Terminal", action: {})
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "gear", label: "Settings", action: {})
            }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var leftToolbar: some View {
        if windowWidth > 1000 {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: {})
                toolbarButton(icon: "arrow.down.to.line", label: "Pull", action: {})
                toolbarButton(icon: "arrow.up.to.line", label: "Push", action: {})
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", action: {})
                toolbarButton(icon: "arrow.triangle.branch", label: "Branch", action: {})
                toolbarButton(icon: "arrow.triangle.merge", label: "Merge", action: {})
                toolbarButton(icon: "archivebox", label: "Stash", action: {})
            }
        } else if windowWidth > 800 {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: {})
                toolbarButton(icon: "arrow.down.to.line", label: "Pull", action: {})
                toolbarButton(icon: "arrow.up.to.line", label: "Push", action: {})
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", action: {})
                moreMenu
            }
        } else {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: {})
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if windowWidth <= 800 {
                Button("Pull", action: {})
                Button("Push", action: {})
                Button("Fetch", action: {})
            }
            if windowWidth <= 1000 {
                Button("Branch", action: {})
                Button("Merge", action: {})
                Button("Stash", action: {})
            }
        } label: {
            ToolbarButtonLabel(icon: "ellipsis", label: "More")
        }
        .help("More Actions")
    }
}

struct ToolbarButtonLabel: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
            Text(label)
                .font(.system(size: 9))
        }
        .frame(minWidth: 44)
    }
}

func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ToolbarButtonLabel(icon: icon, label: label)
    }
    .help(label)
}

struct FileStatusView: View {
    let repositoryURL: URL

    var body: some View {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            message: "File status will appear here",
            detail: repositoryURL.path
        )
    }
}

struct HistoryView: View {
    let repositoryURL: URL

    var body: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            message: "Commit history will appear here",
            detail: repositoryURL.path
        )
    }
}

struct SearchView: View {
    let repositoryURL: URL

    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            message: "Search across commits, files, and branches",
            detail: repositoryURL.path
        )
    }
}

struct EmptyStateView: View {
    var icon: String = "rectangle.dashed"
    var message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3)
                .foregroundStyle(.primary)
            if let detail = detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
