import SwiftUI
import AppKit

/// Enter native full screen on Start. Leaving native full screen never exposes an alternate editor.
struct WindowImmersionBridge: NSViewRepresentable {
    let isImmersed: Bool
    func makeNSView(context: Context) -> ImmersionWindowObserver { ImmersionWindowObserver() }
    func updateNSView(_ view: ImmersionWindowObserver, context: Context) { view.setImmersed(isImmersed) }
}
@MainActor final class ImmersionWindowObserver: NSView {
    private var immersed = false
    private var enteredByApp = false
    private var applied = false
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyIfNeeded() }
    func setImmersed(_ value: Bool) {
        if immersed != value { immersed = value; applied = false }
        applyIfNeeded()
    }
    private func applyIfNeeded() {
        guard !applied, let window else { return }
        applied = true
        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            if self.immersed {
                if !window.styleMask.contains(.fullScreen) { self.enteredByApp = true; window.toggleFullScreen(nil) }
            } else if self.enteredByApp {
                self.enteredByApp = false
                if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            }
        }
    }
}
