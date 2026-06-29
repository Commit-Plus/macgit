import CoreTransferable
import Foundation

nonisolated enum GitDragPayloadItemProviderLoader {
    @discardableResult
    static func load(
        from provider: NSItemProvider,
        completionHandler: @escaping @Sendable (Result<GitDragPayload, Error>) -> Void
    ) -> Progress {
        provider.loadTransferable(
            type: GitDragPayload.self,
            completionHandler: completionHandler
        )
    }
}
