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

enum GitRuntimeError: LocalizedError, Equatable {
    case missingSystemGit
    case missingEmbeddedGit
    case downloadInProgress
    case downloadFailed(String)
    case invalidArchiveSize(expected: Int, actual: Int)
    case checksumMismatch
    case extractionFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSystemGit:
            return "System Git is not available on this Mac."
        case .missingEmbeddedGit:
            return "Embedded Git is not installed. Open Git Settings to download it."
        case .downloadInProgress:
            return "Embedded Git is already downloading."
        case .downloadFailed(let message):
            return "Embedded Git download failed: \(message)"
        case .invalidArchiveSize:
            return "The Embedded Git download has an unexpected size."
        case .checksumMismatch:
            return "The Embedded Git download failed security verification."
        case .extractionFailed(let message):
            return "Embedded Git installation failed: \(message)"
        case .validationFailed(let path):
            return "Git failed validation at \(path)."
        }
    }
}
