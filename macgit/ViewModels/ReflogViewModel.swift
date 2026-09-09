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

import Foundation
import Observation

@MainActor @Observable
final class ReflogViewModel {
    var entries: [ReflogEntry] = []
    var selection: ReflogEntry.ID?
    var query = ""
    var allReferences = false
    var isLoading = false
    var errorMessage: String?
    var hasMore = false
    private let pageSize = 100
    private var generation = UUID()

    var filteredEntries: [ReflogEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter {
            [$0.hash, $0.reference, $0.actor, $0.email, $0.message].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedEntry: ReflogEntry? { filteredEntries.first { $0.id == selection } }

    func loadMoreIfNeeded(for entry: ReflogEntry, in repositoryURL: URL) async {
        guard query.isEmpty, errorMessage == nil,
              entries.suffix(5).contains(where: { $0.id == entry.id }) else { return }
        await load(in: repositoryURL, more: true)
    }

    func load(in repositoryURL: URL, reset: Bool = false, more: Bool = false) async {
        if more && (isLoading || !hasMore) { return }
        if reset { entries = []; selection = nil; hasMore = false }
        let request = UUID()
        generation = request
        isLoading = true
        errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            // Refresh the loaded range in bounded batches; scrolling fetches only
            // the next page, rather than re-reading the entire loaded prefix.
            let targetCount = more ? entries.count + pageSize : max(pageSize, entries.count)
            var updated = more ? entries : []
            var canLoadMore = true
            repeat {
                let page = try await GitStatusService.shared.reflog(
                    in: repositoryURL, allReferences: allReferences,
                    limit: pageSize, skip: updated.count
                )
                guard generation == request, !Task.isCancelled else { return }
                updated = ReflogEntry.appending(page, to: updated)
                canLoadMore = page.count == pageSize
            } while !more && canLoadMore && updated.count < targetCount
            entries = updated
            hasMore = canLoadMore
            if !entries.contains(where: { $0.id == selection }) { selection = nil }
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
