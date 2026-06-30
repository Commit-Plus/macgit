//
//  VideoThumbnailView.swift
//  macgit
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
import AVFoundation

struct VideoThumbnailView: View {
    let fileURL: URL
    let filePath: String?

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image {
                imageDisplayView(image)
            } else if failed {
                EmptyStateView(
                    icon: "film",
                    message: "Unable to preview video",
                    detail: filePath ?? fileURL.lastPathComponent
                )
            } else {
                ProgressView("Loading preview…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        image = nil
        failed = false

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            failed = true
            return
        }

        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let requestedTime = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let cgImage = try await generateCGImage(generator: generator, for: requestedTime)
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            image = NSImage(cgImage: cgImage, size: size)
        } catch {
            let zeroTime = CMTime.zero
            do {
                let cgImage = try await generateCGImage(generator: generator, for: zeroTime)
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                image = NSImage(cgImage: cgImage, size: size)
            } catch {
                failed = true
            }
        }
    }

    private func generateCGImage(generator: AVAssetImageGenerator, for time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: ThumbnailError.noImage)
                }
            }
        }
    }

    private enum ThumbnailError: Error {
        case noImage
    }

    private func imageDisplayView(_ nsImage: NSImage) -> some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        maxWidth: max(geo.size.width, CGFloat(nsImage.size.width)),
                        maxHeight: max(geo.size.height, CGFloat(nsImage.size.height))
                    )
            }
        }
    }
}
