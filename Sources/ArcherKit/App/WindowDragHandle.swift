import AppKit
import SwiftUI

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragHandleView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point), let type = NSApp.currentEvent?.type else { return nil }
            switch type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
                return self
            default:
                return nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.performZoom(nil)
                return
            }
            // `window.isMovable` is `false` globally so tab DnD wins; flip it
            // for this single drag and restore on exit.
            let wasMovable = window.isMovable
            window.isMovable = true
            defer { window.isMovable = wasMovable }
            window.performDrag(with: event)
        }
    }
}
