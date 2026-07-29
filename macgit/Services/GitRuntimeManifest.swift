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

struct GitRuntimeManifest: Equatable, Sendable {
    let version: String
    let platform: String
    let url: URL
    let sha256: String
    let archiveSize: Int

    static let current: GitRuntimeManifest = {
        #if arch(arm64)
        GitRuntimeManifest(
            version: "2.53.0",
            platform: "macos-arm64",
            url: URL(
                string: "https://github.com/desktop/dugite-native/releases/download/v2.53.0-3/dugite-native-v2.53.0-f49d009-macOS-arm64.tar.gz"
            )!,
            sha256: "e561cfc80c755e6f3e938653e81efcd025c9827a5b76dd42778b1159b3fab437",
            archiveSize: 60_191_347
        )
        #elseif arch(x86_64)
        GitRuntimeManifest(
            version: "2.53.0",
            platform: "macos-x64",
            url: URL(
                string: "https://github.com/desktop/dugite-native/releases/download/v2.53.0-3/dugite-native-v2.53.0-f49d009-macOS-x64.tar.gz"
            )!,
            sha256: "caf27c36b8834969550535bcd5e58186f970e080d1e175e76d9c1de3aac409ed",
            archiveSize: 63_387_151
        )
        #else
        #error("Embedded Git is only supported on macOS arm64 and x86_64.")
        #endif
    }()
}
