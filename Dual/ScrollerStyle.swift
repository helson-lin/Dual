//
//  ScrollerStyle.swift
//  Dual
//
//  SwiftUI has no scrollbar styling on macOS 12, so reach the enclosing
//  NSScrollView and configure it directly.
//

import SwiftUI

struct ScrollerStyle: NSViewRepresentable {
    var isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view)
        }
    }

    // `enclosingScrollView` is nil until the view is actually in the
    // hierarchy, hence the async hop in both make and update.
    private func configure(_ view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.verticalScroller?.knobStyle = isDark ? .light : .dark
    }
}
