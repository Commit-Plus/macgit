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

struct WelcomeView: View {
    @ObservedObject private var store = RecentRepositoriesStore.shared
    @State private var model = WelcomeDashboardModel()
    @State private var showingUnavailableRepository = false
    @State private var forceRefresh = false
    @State private var refreshID = UUID()
    let accountDisplayName: String?
    let onRepositoryOpened: (URL) -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                RepoPickerView(isDashboardSidebar: true, onRepositoryOpened: onRepositoryOpened)
                    .frame(width: min(420, max(340, geometry.size.width * 0.32)))
                Divider()
                WelcomeDashboardContent(
                    model: model, accountDisplayName: accountDisplayName, repositoryCount: store.repositories.count,
                    onRefresh: refreshImmediately, onRepositoryOpened: openRepository
                )
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("Repository Unavailable", isPresented: $showingUnavailableRepository) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use the repository list to locate its folder or remove it from recents.")
        }
        .task(id: refreshID) {
            let force = forceRefresh
            forceRefresh = false
            await model.refresh(repositories: store.repositories, force: force)
        }
        .onChange(of: store.repositories.map { "\($0.url.path)|\($0.lastOpened.timeIntervalSince1970)" }) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in refresh() }
    }

    private func refreshImmediately() {
        forceRefresh = true
        refresh()
    }

    private func refresh() { refreshID = UUID() }

    private func openRepository(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            showingUnavailableRepository = true
            refresh()
            return
        }
        store.add(url)
        onRepositoryOpened(url)
    }
}
