//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026 Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  This program is distributed WITHOUT ANY WARRANTY; without even the implied
//  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See <https://www.gnu.org/licenses/> for the license.
//

import AppKit

/// Reserves space inside the document for Generate without moving the scroller.
final class PullRequestDescriptionTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = max(1, newSize.width - 60)
        if textContainer?.containerSize.width != width {
            textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
    }
}

