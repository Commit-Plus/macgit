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
import SQLite3

/// All database work runs on this actor, outside the UI executor.
actor RepositoryAIChatHistoryStore {
    static let shared = RepositoryAIChatHistoryStore()
    private let databaseURL: URL

    init(databaseURL: URL = URL.applicationSupportDirectory
        .appending(path: "Commit+/RepositoryAI/history.sqlite")) {
        self.databaseURL = databaseURL
    }

    func save(_ conversation: RepositoryAIConversation) throws {
        guard !conversation.messages.isEmpty else { return }
        let payload = String(decoding: try JSONEncoder().encode(conversation), as: UTF8.self)
        let searchText = ([conversation.title] + conversation.messages.map(\.text))
            .joined(separator: "\n").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let preview = String((conversation.messages.last(where: { $0.role != .toolActivity })?.text ?? "").prefix(200))
        try withDatabase { db in
            try query(db, sql: """
                INSERT INTO conversations (id, repository, title, preview, updated, search_text, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title, preview=excluded.preview,
                updated=excluded.updated, search_text=excluded.search_text, payload=excluded.payload
                """, values: [conversation.id, conversation.repositoryPath, conversation.title,
                              preview, String(conversation.updatedAt.timeIntervalSince1970), searchText, payload]) { _ in }
        }
    }

    func search(repositoryPath: String, query search: String) throws -> [RepositoryAIConversationSummary] {
        let normalized = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return try withDatabase { db in
            var result: [RepositoryAIConversationSummary] = []
            try query(db, sql: """
                SELECT id, title, preview, updated FROM conversations
                WHERE repository = ? AND instr(search_text, ?) > 0 ORDER BY updated DESC, id
                """, values: [repositoryPath, normalized]) { statement in
                result.append(RepositoryAIConversationSummary(
                    id: column(statement, 0), title: column(statement, 1), preview: column(statement, 2),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                ))
            }
            return result
        }
    }

    func load(id: String, repositoryPath: String) throws -> RepositoryAIConversation? {
        try withDatabase { db in
            var result: RepositoryAIConversation?
            try query(db, sql: "SELECT payload FROM conversations WHERE id = ? AND repository = ?",
                      values: [id, repositoryPath]) { statement in
                result = try JSONDecoder().decode(RepositoryAIConversation.self, from: Data(column(statement, 0).utf8))
            }
            return result
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        let status = sqlite3_open(databaseURL.path, &connection)
        guard let db = connection else { throw failure("Could not open chat history.") }
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK else { throw failure(String(cString: sqlite3_errmsg(db))) }
        sqlite3_busy_timeout(db, 3_000)
        try query(db, sql: """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY, repository TEXT NOT NULL, title TEXT NOT NULL,
                preview TEXT NOT NULL, updated REAL NOT NULL, search_text TEXT NOT NULL, payload TEXT NOT NULL
            )
            """) { _ in }
        try query(db, sql: "CREATE INDEX IF NOT EXISTS conversations_repository_updated ON conversations(repository, updated DESC)") { _ in }
        return try operation(db)
    }

    private func query(_ db: OpaquePointer, sql: String, values: [String] = [], row: (OpaquePointer) throws -> Void) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw failure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw failure(String(cString: sqlite3_errmsg(db))) }
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try row(statement)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure(String(cString: sqlite3_errmsg(db))) }
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "RepositoryAIChatHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
