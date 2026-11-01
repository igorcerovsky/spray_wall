import SwiftUI
#if os(macOS)
import AppKit

/// AppKit scroll-wheel zoom event handler for macOS.
/// Intercepts Ctrl + scroll wheel over the attached SwiftUI view to perform focal zooming.
struct ScrollWheelZoomModifier: NSViewRepresentable {
    var onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ZoomWheelNSView {
        let view = ZoomWheelNSView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: ZoomWheelNSView, context: Context) {
        nsView.onZoom = onZoom
    }
}

final class ZoomWheelNSView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    private nonisolated(unsafe) var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, let win = self.window, event.window == win else {
                    return event
                }

                if event.modifierFlags.contains(.control) {
                    let pointInWindow = event.locationInWindow
                    let pointInView = self.convert(pointInWindow, from: nil)

                    if self.bounds.contains(pointInView) {
                        let swiftUIPoint = CGPoint(x: pointInView.x, y: self.bounds.height - pointInView.y)
                        let delta: CGFloat
                        if event.hasPreciseScrollingDeltas {
                            delta = event.scrollingDeltaY * 0.005
                        } else {
                            let step: CGFloat = 0.12
                            if event.scrollingDeltaY != 0 {
                                delta = event.scrollingDeltaY > 0 ? step : -step
                            } else if event.deltaY != 0 {
                                delta = event.deltaY > 0 ? step : -step
                            } else {
                                delta = 0
                            }
                        }
                        self.onZoom?(delta, swiftUIPoint)
                        return nil
                    }
                }
                return event
            }
        } else if window == nil, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}
#endif

