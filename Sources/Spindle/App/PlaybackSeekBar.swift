import AppKit
import SwiftUI

private struct SeekBarLive: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// Whether a `PlaybackSeekBar` here takes clicks (see `SeekView.live`).
    var seekBarLive: Bool {
        get { self[SeekBarLive.self] }
        set { self[SeekBarLive.self] = newValue }
    }
}

/// Native event capture keeps seeking stable while playback updates redraw the panel.
struct PlaybackSeekBar: NSViewRepresentable {
    var position: Double
    var duration: Double
    var enabled: Bool
    var tint: NSColor = .white
    var preview: (Double) -> Void
    var commit: (Double) -> Void

    func makeNSView(context: Context) -> SeekView { SeekView() }
    func updateNSView(_ view: SeekView, context: Context) {
        view.live = context.environment.seekBarLive
        view.position = position
        view.duration = duration
        view.enabled = enabled
        view.tint = tint
        view.preview = preview
        view.commit = commit
        view.needsDisplay = true
    }

    final class SeekView: NSView {
        var position = 0.0, duration = 0.0
        var enabled = false, hovered = false, dragging = false
        /// False where the bar is only a picture of itself (the player card drawn into its pill): an AppKit view takes
        /// clicks in its frame whatever SwiftUI has done to it since, so a faded or moved copy must take none.
        var live = true
        override func hitTest(_ point: NSPoint) -> NSView? { live ? super.hitTest(point) : nil }
        var tint = NSColor.white
        private var hoverAmount: CGFloat = 0
        private var hoverTimer: Timer?
        private func animateHover() {
            hoverTimer?.invalidate()
            let from = hoverAmount
            let to: CGFloat = hovered || dragging ? 1 : 0
            let began = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let t = min((CACurrentMediaTime() - began) / 0.18, 1)
                let ease = CGFloat(t * t * (3 - 2 * t))
                self.hoverAmount = from + (to - from) * ease
                self.needsDisplay = true
                if t >= 1 {
                    timer.invalidate()
                    self.hoverTimer = nil
                }
            }
            hoverTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                hoverTimer?.invalidate()
                hoverTimer = nil
            }
        }
        var preview: (Double) -> Void = { _ in }
        var commit: (Double) -> Void = { _ in }
        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) {
            hovered = true
            animateHover()
        }
        override func mouseExited(with event: NSEvent) {
            hovered = false
            animateHover()
        }
        private func target(_ event: NSEvent) -> Double {
            let x = convert(event.locationInWindow, from: nil).x
            return min(max(Double(x / max(bounds.width, 1)), 0), 1) * duration
        }
        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            dragging = true
            animateHover()
            window?.makeFirstResponder(self)
            preview(target(event))
            needsDisplay = true
        }
        override func mouseDragged(with event: NSEvent) {
            if dragging {
                preview(target(event))
                needsDisplay = true
            }
        }
        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            dragging = false
            animateHover()
            commit(target(event))
            needsDisplay = true
        }
        override func keyDown(with event: NSEvent) {
            guard enabled, event.keyCode == 123 || event.keyCode == 124 else {
                super.keyDown(with: event)
                return
            }
            let value = min(max(position + (event.keyCode == 124 ? 5 : -5), 0), duration)
            preview(value)
            commit(value)
        }
        override func draw(_ dirtyRect: NSRect) {
            let height: CGFloat = 3 + hoverAmount * 3
            let track = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            var fill = track
            fill.size.width *= fraction
            // (The played part is the album's colour, lifted enough to read against the track.)
            (tint.blended(withFraction: 0.35, of: .white) ?? tint).setFill()
            NSBezierPath(roundedRect: fill, xRadius: height / 2, yRadius: height / 2).fill()
            if #available(macOS 26.0, *), LiquidGlass.on {
                placeGlassKnob(at: fill.width)
            } else if enabled && hoverAmount > 0 {
                NSColor.white.withAlphaComponent(hoverAmount).setFill()
                NSBezierPath(
                    ovalIn: NSRect(
                        x: min(max(fill.width - 4.5, 0), max(bounds.width - 9, 0)), y: (bounds.height - 9) / 2,
                        width: 9, height: 9)
                ).fill()
            }
        }

        /// The knob, in Liquid Glass (owner, 2026-10-17): a small capsule of glass where the played part ends, there while
        /// the pointer is over the bar and a little larger while it is being dragged, as the system's own sliders are.
        private var glassKnob: NSView?
        @available(macOS 26.0, *)
        private func placeGlassKnob(at x: CGFloat) {
            let knob: NSGlassEffectView
            if let made = glassKnob as? NSGlassEffectView {
                knob = made
            } else {
                knob = NSGlassEffectView()
                knob.contentView = NSView()
                addSubview(knob)
                glassKnob = knob
            }
            let grow: CGFloat = dragging ? 1.15 : 1
            let wide = 22 * grow
            let high = 14 * grow
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knob.frame = NSRect(
                x: (min(max(x - wide / 2, 0), max(bounds.width - wide, 0))).rounded(),
                y: ((bounds.height - high) / 2).rounded(), width: wide.rounded(), height: high.rounded())
            knob.cornerRadius = knob.frame.height / 2
            knob.alphaValue = enabled ? hoverAmount : 0
            CATransaction.commit()
        }
    }
}
