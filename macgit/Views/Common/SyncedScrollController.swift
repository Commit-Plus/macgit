import AppKit

final class SyncedScrollController {
    private var scrollViews: [String: WeakScrollView] = [:]
    private var observers: [String: NSObjectProtocol] = [:]
    private var isApplyingSynchronizedScroll = false

    func register(_ scrollView: NSScrollView, id: String) {
        removeReleasedScrollViews()

        if scrollViews[id]?.value === scrollView {
            return
        }

        unregister(id: id)
        scrollViews[id] = WeakScrollView(scrollView)

        scrollView.contentView.postsBoundsChangedNotifications = true
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else { return }
            self.syncScroll(from: id, source: scrollView)
        }
    }

    func unregister(id: String, scrollView: NSScrollView? = nil) {
        if let scrollView, scrollViews[id]?.value !== scrollView {
            return
        }

        if let observer = observers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollViews.removeValue(forKey: id)
    }

    func scrollToTop() {
        scrollToVerticalOffset(0)
    }

    func scrollToVerticalOffset(_ offset: CGFloat) {
        removeReleasedScrollViews()
        isApplyingSynchronizedScroll = true
        for scrollView in scrollViews.values.compactMap(\.value) {
            setVerticalOffset(offset, on: scrollView)
        }
        isApplyingSynchronizedScroll = false
    }

    private func syncScroll(from sourceID: String, source: NSScrollView) {
        guard !isApplyingSynchronizedScroll else { return }
        removeReleasedScrollViews()

        let sourceY = source.contentView.bounds.origin.y
        isApplyingSynchronizedScroll = true

        for (id, weakScrollView) in scrollViews where id != sourceID {
            guard let scrollView = weakScrollView.value else { continue }
            setVerticalOffset(sourceY, on: scrollView)
        }

        isApplyingSynchronizedScroll = false
    }

    private func setVerticalOffset(_ offset: CGFloat, on scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }

        let maximumOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        let clampedOffset = min(max(0, offset), maximumOffset)
        var origin = scrollView.contentView.bounds.origin
        origin.y = clampedOffset

        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func removeReleasedScrollViews() {
        let releasedIDs = scrollViews.compactMap { id, weakScrollView in
            weakScrollView.value == nil ? id : nil
        }

        for id in releasedIDs {
            unregister(id: id)
        }
    }
}

private final class WeakScrollView {
    weak var value: NSScrollView?

    init(_ value: NSScrollView) {
        self.value = value
    }
}
