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

import Combine
import Foundation

enum RepositoryBookmarkError: LocalizedError {
    case noRemote
    case unsupportedRemote
    case folderDoesNotMatch

    var errorDescription: String? {
        switch self {
        case .noRemote:
            "This repository has no Git remote to bookmark."
        case .unsupportedRemote:
            "The repository remote URL could not be recognized."
        case .folderDoesNotMatch:
            "The selected folder belongs to a different repository."
        }
    }
}

@MainActor
final class RepositoryBookmarkController: ObservableObject {
    @Published private(set) var bookmarks: [RepositoryBookmark]
    @Published private(set) var syncingBookmarkIDs: Set<String> = []
    @Published private(set) var errorMessage: String?

    private let cloudStore: RepositoryBookmarkCloudStore?
    private let userDefaults: UserDefaults
    private let bookmarksKey: String
    private let localPathsKey: String
    private let pendingUploadsKey: String
    private let pendingDeletesKey: String

    @Published private(set) var localPaths: [String: String]
    private var pendingUploads: Set<String>
    private var pendingDeletes: Set<String>
    private var activeUID: String?
    private var observation: ObservationToken?

    init(
        cloudStore: RepositoryBookmarkCloudStore?,
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "dev.thanhtran.macgit.repositoryBookmarks"
    ) {
        self.cloudStore = cloudStore
        self.userDefaults = userDefaults
        bookmarksKey = "\(keyPrefix).items"
        localPathsKey = "\(keyPrefix).localPaths"
        pendingUploadsKey = "\(keyPrefix).pendingUploads"
        pendingDeletesKey = "\(keyPrefix).pendingDeletes"

        if let data = userDefaults.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([RepositoryBookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }
        localPaths = userDefaults.dictionary(forKey: localPathsKey) as? [String: String] ?? [:]
        pendingUploads = Set(userDefaults.stringArray(forKey: pendingUploadsKey) ?? [])
        pendingDeletes = Set(userDefaults.stringArray(forKey: pendingDeletesKey) ?? [])
    }

    deinit {
        observation?.cancel()
    }

    func updateAccount(_ account: AccountSnapshot?) async {
        let uid = account?.uid
        guard uid != activeUID else { return }

        observation?.cancel()
        observation = nil
        activeUID = uid
        guard let uid, let cloudStore else { return }

        await flushPendingChanges(uid: uid, cloudStore: cloudStore)

        do {
            let cloudBookmarks = try await cloudStore.bookmarks(uid: uid)
            guard activeUID == uid else { return }
            applyCloudBookmarks(cloudBookmarks)
            observation = cloudStore.observe(uid: uid) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.activeUID == uid else { return }
                    switch result {
                    case .success(let bookmarks):
                        self.applyCloudBookmarks(bookmarks)
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            guard activeUID == uid else { return }
            errorMessage = error.localizedDescription
        }
    }

    func bookmark(forID id: String) -> RepositoryBookmark? {
        bookmarks.first { $0.id == id }
    }

    func bookmark(remoteURLString: String) -> RepositoryBookmark? {
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString) else {
            return nil
        }
        return bookmarks.first { $0.canonicalKey == identity.canonicalKey }
    }

    func localURL(for bookmark: RepositoryBookmark) -> URL? {
        guard let path = localPaths[bookmark.id] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func bookmarkID(linkedTo url: URL) -> String? {
        localPaths.first { $0.value == url.path }?.key
    }

    func addBookmark(for repositoryURL: URL) async throws -> RepositoryBookmark {
        let remoteURLString = try await bookmarkRemoteURL(in: repositoryURL)
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString) else {
            throw RepositoryBookmarkError.unsupportedRemote
        }

        if let existing = bookmarks.first(where: { $0.canonicalKey == identity.canonicalKey }) {
            link(existing, to: repositoryURL)
            return existing
        }

        let bookmark = RepositoryBookmark(identity: identity)
        bookmarks.append(bookmark)
        localPaths[bookmark.id] = repositoryURL.path
        pendingDeletes.remove(bookmark.id)
        pendingUploads.insert(bookmark.id)
        persist()
        await upload(bookmark)
        return bookmark
    }

    func removeBookmark(_ bookmark: RepositoryBookmark) async {
        bookmarks.removeAll { $0.id == bookmark.id }
        localPaths.removeValue(forKey: bookmark.id)
        pendingUploads.remove(bookmark.id)
        pendingDeletes.insert(bookmark.id)
        persist()

        guard let uid = activeUID, let cloudStore else { return }
        syncingBookmarkIDs.insert(bookmark.id)
        do {
            try await cloudStore.delete(bookmarkID: bookmark.id, uid: uid)
            pendingDeletes.remove(bookmark.id)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
        syncingBookmarkIDs.remove(bookmark.id)
    }

    func link(_ bookmark: RepositoryBookmark, to repositoryURL: URL) {
        localPaths[bookmark.id] = repositoryURL.path
        persist()
    }

    func validateAndLink(_ bookmark: RepositoryBookmark, to repositoryURL: URL) async throws {
        let remoteURLString = try await bookmarkRemoteURL(in: repositoryURL)
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString),
              identity.canonicalKey == bookmark.canonicalKey else {
            throw RepositoryBookmarkError.folderDoesNotMatch
        }
        link(bookmark, to: repositoryURL)
    }

    func unlinkLocalFolder(for bookmark: RepositoryBookmark) {
        localPaths.removeValue(forKey: bookmark.id)
        persist()
    }

    func clearError() {
        errorMessage = nil
    }

    private func bookmarkRemoteURL(in repositoryURL: URL) async throws -> String {
        let origin = await GitStatusService.shared.remoteURL(remote: "origin", in: repositoryURL)
        if !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return origin
        }

        for remote in await GitStatusService.shared.remotes(in: repositoryURL) {
            let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            if !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return remoteURL
            }
        }
        throw RepositoryBookmarkError.noRemote
    }

    private func upload(_ bookmark: RepositoryBookmark) async {
        guard let uid = activeUID, let cloudStore else { return }
        syncingBookmarkIDs.insert(bookmark.id)
        do {
            try await cloudStore.save(bookmark, uid: uid)
            pendingUploads.remove(bookmark.id)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
        syncingBookmarkIDs.remove(bookmark.id)
    }

    private func flushPendingChanges(
        uid: String,
        cloudStore: RepositoryBookmarkCloudStore
    ) async {
        for bookmarkID in pendingDeletes {
            do {
                try await cloudStore.delete(bookmarkID: bookmarkID, uid: uid)
                pendingDeletes.remove(bookmarkID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        for bookmark in bookmarks where pendingUploads.contains(bookmark.id) {
            do {
                try await cloudStore.save(bookmark, uid: uid)
                pendingUploads.remove(bookmark.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        persist()
    }

    private func applyCloudBookmarks(_ cloudBookmarks: [RepositoryBookmark]) {
        let pendingLocal = bookmarks.filter { pendingUploads.contains($0.id) }
        var merged = Dictionary(uniqueKeysWithValues: cloudBookmarks.map { ($0.id, $0) })
        for bookmark in pendingLocal {
            merged[bookmark.id] = bookmark
        }
        for deletedID in pendingDeletes {
            merged.removeValue(forKey: deletedID)
        }
        bookmarks = merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let validIDs = Set(bookmarks.map(\.id))
        localPaths = localPaths.filter { validIDs.contains($0.key) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: bookmarksKey)
        }
        userDefaults.set(localPaths, forKey: localPathsKey)
        userDefaults.set(Array(pendingUploads), forKey: pendingUploadsKey)
        userDefaults.set(Array(pendingDeletes), forKey: pendingDeletesKey)
    }
}
