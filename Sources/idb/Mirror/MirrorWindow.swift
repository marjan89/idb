import AppKit
import Foundation

// MARK: - Constants

private enum Mirror {
    /// Fraction of window width — mouse must move this far to distinguish tap from drag
    static let tapThresholdRatio: CGFloat = 0.015
    /// Fraction of window width — minimum drag movement to trigger a velocity swipe pulse
    static let dragThresholdRatio: CGFloat = 0.03
    /// Retina scale factor estimate when MJPEG frame size is unknown
    static let defaultScaleFactor: CGFloat = 3
    /// Screen edge padding for initial window placement (points)
    static let windowEdgePadding: CGFloat = 20
    /// Minimum window dimensions
    static let minWindowSize = NSSize(width: 150, height: 300)
    /// Fallback screen size when NSScreen.main is nil
    static let fallbackScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    enum Scroll {
        /// Minimum seconds between scroll events
        static let throttle: TimeInterval = 0.15
        /// Minimum scrollingDelta to register
        static let deadzone: CGFloat = 2
        /// Swipe distance in WDA points per scroll tick
        static let distance: CGFloat = 150
        /// Swipe duration for scroll gestures
        static let duration: Double = 0.2
        /// Screen edge margin for scroll swipe clamping
        static let edgeMargin: CGFloat = 10
    }

    enum Pinch {
        static let zoomInScale: Double = 1.5
        static let zoomOutScale: Double = 0.67
    }

    enum Drag {
        /// Baseline mouse speed (px/s) — speeds above this get amplified
        static let baseSpeed: CGFloat = 300
        /// Maximum speed multiplier
        static let maxMultiplier: CGFloat = 4.0
        /// Minimum swipe duration (fast drag)
        static let minDuration: Double = 0.01
        /// Duration divisor — lower = shorter duration at high speed
        static let durationBase: Double = 0.05
    }

    enum Gesture {
        /// Duration for iOS back swipe (left-edge)
        static let backDuration: Double = 0.3
        /// Duration for task switcher swipe
        static let taskSwitcherDuration: Double = 0.5
        /// How far across the screen the back swipe goes (fraction)
        static let backSwipeRatio: CGFloat = 0.5
        /// Where the task switcher swipe ends (fraction from top)
        static let taskSwitcherEndRatio: CGFloat = 0.4
        /// Start offset from bottom for task switcher
        static let taskSwitcherBottomOffset: CGFloat = 5
        /// Swipe duration for non-drag mouse release
        static let releaseDuration: Double = 0.2
    }
}

// MARK: - View

class MirrorView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = image else {
            NSColor.black.setFill()
            dirtyRect.fill()
            return
        }
        image.draw(in: bounds)
    }
}

// MARK: - Window

class MirrorWindow: NSWindow {
    private let wda: MirrorWDABridge
    let mirrorView = MirrorView()
    private let wdaSize: (width: CGFloat, height: CGFloat)
    private var lastScrollTime: TimeInterval = 0

    init(wda: MirrorWDABridge, wdaSize: (CGFloat, CGFloat), imageSize: NSSize?, scale: CGFloat) {
        self.wda = wda
        self.wdaSize = wdaSize

        let baseW = imageSize?.width ?? wdaSize.0 * Mirror.defaultScaleFactor
        let baseH = imageSize?.height ?? wdaSize.1 * Mirror.defaultScaleFactor
        let winW = baseW * scale
        let winH = baseH * scale

        let screenFrame = NSScreen.main?.visibleFrame ?? Mirror.fallbackScreen
        let x = screenFrame.maxX - winW - Mirror.windowEdgePadding
        let y = screenFrame.midY - winH / 2

        super.init(contentRect: NSRect(x: x, y: y, width: winW, height: winH),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)

        title = "idb mirror"
        contentView = mirrorView
        mirrorView.frame = NSRect(x: 0, y: 0, width: winW, height: winH)
        minSize = Mirror.minWindowSize
        aspectRatio = NSSize(width: baseW, height: baseH)
        makeKeyAndOrderFront(nil)
    }

    func updateImage(_ image: NSImage) {
        DispatchQueue.main.async { self.mirrorView.image = image }
    }

    private func toWDA(_ point: NSPoint) -> (CGFloat, CGFloat) {
        let b = mirrorView.bounds
        return (point.x / b.width * wdaSize.0, point.y / b.height * wdaSize.1)
    }

    // MARK: - Mouse

    private var mouseDownPoint: NSPoint?
    private var prevDragPoint: NSPoint?
    private var prevDragTime: TimeInterval = 0
    private var dragging = false
    private var tapThreshold: CGFloat { mirrorView.bounds.width * Mirror.tapThresholdRatio }
    private var dragThreshold: CGFloat { mirrorView.bounds.width * Mirror.dragThresholdRatio }

    override func mouseDown(with event: NSEvent) {
        let pt = mirrorView.convert(event.locationInWindow, from: nil)
        mouseDownPoint = pt
        prevDragPoint = pt
        prevDragTime = ProcessInfo.processInfo.systemUptime
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let prev = prevDragPoint else { return }
        let pt = mirrorView.convert(event.locationInWindow, from: nil)
        let now = ProcessInfo.processInfo.systemUptime
        let dx = pt.x - prev.x, dy = pt.y - prev.y
        let dist = sqrt(dx * dx + dy * dy)
        if dist < dragThreshold { return }

        dragging = true
        let dt = now - prevDragTime
        let speed = dt > 0 ? dist / CGFloat(dt) : Mirror.Drag.baseSpeed

        let (fx, fy) = toWDA(prev)
        let (tx, ty) = toWDA(pt)
        let wdaDx = tx - fx, wdaDy = ty - fy
        let wdaDist = sqrt(wdaDx * wdaDx + wdaDy * wdaDy)
        let mult = min(max(speed / Mirror.Drag.baseSpeed, 1.0), Mirror.Drag.maxMultiplier)
        let nx = wdaDx / wdaDist, ny = wdaDy / wdaDist
        let endX = fx + nx * wdaDist * mult
        let endY = fy + ny * wdaDist * mult

        wda.swipe(fx, fy, endX, endY, max(Mirror.Drag.durationBase / mult, Mirror.Drag.minDuration))
        prevDragPoint = pt
        prevDragTime = now
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let end = mirrorView.convert(event.locationInWindow, from: nil)
        if !dragging {
            let dist = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
            if dist <= tapThreshold {
                let (x, y) = toWDA(end)
                wda.tap(x, y)
            } else {
                let (fx, fy) = toWDA(start)
                let (tx, ty) = toWDA(end)
                wda.swipe(fx, fy, tx, ty, Mirror.Gesture.releaseDuration)
            }
        }
        mouseDownPoint = nil; prevDragPoint = nil; dragging = false
    }

    // MARK: - Scroll & Pinch

    override func scrollWheel(with event: NSEvent) {
        if event.momentumPhase != [] { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScrollTime >= Mirror.Scroll.throttle else { return }

        let loc = mirrorView.convert(event.locationInWindow, from: nil)
        let (cx, cy) = toWDA(loc)

        // Option+scroll = pinch
        if event.modifierFlags.contains(.option) {
            guard abs(event.scrollingDeltaY) > Mirror.Scroll.deadzone else { return }
            lastScrollTime = now
            let scale = event.scrollingDeltaY > 0 ? Mirror.Pinch.zoomInScale : Mirror.Pinch.zoomOutScale
            wda.pinch(cx, cy, scale: scale)
            return
        }

        let d = Mirror.Scroll.distance
        let edge = Mirror.Scroll.edgeMargin
        let dur = Mirror.Scroll.duration

        if abs(event.scrollingDeltaY) > Mirror.Scroll.deadzone {
            lastScrollTime = now
            if event.scrollingDeltaY > 0 {
                wda.swipe(cx, max(cy - d/2, edge), cx, min(cy + d/2, wdaSize.1 - edge), dur)
            } else {
                wda.swipe(cx, min(cy + d/2, wdaSize.1 - edge), cx, max(cy - d/2, edge), dur)
            }
        } else if abs(event.scrollingDeltaX) > Mirror.Scroll.deadzone {
            lastScrollTime = now
            if event.scrollingDeltaX > 0 {
                wda.swipe(max(cx - d/2, edge), cy, min(cx + d/2, wdaSize.0 - edge), cy, dur)
            } else {
                wda.swipe(min(cx + d/2, wdaSize.0 - edge), cy, max(cx - d/2, edge), cy, dur)
            }
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "q": NSApp.terminate(nil)
            case "v": // Cmd+V — push Mac clipboard to iPhone
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    wda.setPasteboard(text)
                    fputs("[mirror] Pasted to device (\(text.count) chars)\n", stderr)
                }
            case "c": // Cmd+C — pull iPhone clipboard to Mac
                if let text = wda.getPasteboard(), !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    fputs("[mirror] Copied from device: \(String(text.prefix(60)))\n", stderr)
                }
            default: break
            }
            return
        }

        let kb = IDBConfig.load().keybindings

        if matches(event, kb.back) {
            wda.swipe(0, wdaSize.1 / 2,
                      wdaSize.0 * Mirror.Gesture.backSwipeRatio, wdaSize.1 / 2,
                      Mirror.Gesture.backDuration)
            return
        }
        if matches(event, kb.home) {
            wda.pressButton("home")
            return
        }
        if matches(event, kb.taskSwitcher) {
            wda.swipe(wdaSize.0 / 2, wdaSize.1 - Mirror.Gesture.taskSwitcherBottomOffset,
                      wdaSize.0 / 2, wdaSize.1 * Mirror.Gesture.taskSwitcherEndRatio,
                      Mirror.Gesture.taskSwitcherDuration)
            return
        }

        switch event.keyCode {
        case 51: wda.typeKeys([String(UnicodeScalar(8))])
        case 36: wda.typeKeys(["\n"])
        default:
            if let chars = event.characters, !chars.isEmpty {
                wda.typeKeys(chars.map { String($0) })
            }
        }
    }

    /// Match a key event against a binding string like "esc", "opt+backspace"
    private func matches(_ event: NSEvent, _ binding: String) -> Bool {
        let parts = binding.lowercased().split(separator: "+").map(String.init)
        let key = parts.last ?? ""
        let mods = Set(parts.dropLast())

        let needsOpt = mods.contains("opt") || mods.contains("option") || mods.contains("alt")
        let needsShift = mods.contains("shift")
        let needsCtrl = mods.contains("ctrl") || mods.contains("control")

        guard needsOpt == event.modifierFlags.contains(.option),
              needsShift == event.modifierFlags.contains(.shift),
              needsCtrl == event.modifierFlags.contains(.control) else { return false }

        let keyCodeMap: [String: UInt16] = [
            "esc": 53, "escape": 53, "backspace": 51, "delete": 51,
            "tab": 48, "return": 36, "enter": 36, "space": 49,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]

        if let expected = keyCodeMap[key] { return event.keyCode == expected }
        if key.count == 1 { return event.charactersIgnoringModifiers?.lowercased() == key }
        return false
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
