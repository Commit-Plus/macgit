//
//  View+ClickInteraction.swift
//  macgit
//

import SwiftUI

struct ClickInteractionModifier: ViewModifier {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    
    func body(content: Content) -> some View {
        content.overlay(
            InteractionHostingView(
                onLeftClick: onLeftClick,
                onRightClick: onRightClick
            )
        )
    }
}

struct InteractionHostingView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    
    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }
    
    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

class InteractionNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { false }
    
    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
        nextResponder?.mouseDown(with: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
        nextResponder?.rightMouseDown(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

extension View {
    func onClick(left: @escaping () -> Void, right: @escaping () -> Void) -> some View {
        modifier(ClickInteractionModifier(onLeftClick: left, onRightClick: right))
    }
}
