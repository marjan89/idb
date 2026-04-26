import AppKit
import Foundation

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

/// Interactive mirror window — handles mouse, scroll, keyboard input
class MirrorWindow: NSWindow {
    private let wda: MirrorWDABridge
    let mirrorView = MirrorView()
    private let wdaSize: (width: CGFloat, height: CGFloat)
    private var lastScrollTime: TimeInterval = 0
    private let scrollThrottle: TimeInterval = 0.15

    init(wda: MirrorWDABridge, wdaSize: (CGFloat, CGFloat), imageSize: NSSize?, scale: CGFloat) {
        self.wda = wda
        self.wdaSize = wdaSize

        let baseW: CGFloat = imageSize?.width ?? wdaSize.0 * 3
        let baseH: CGFloat = imageSize?.height ?? wdaSize.1 * 3
        let winW = baseW * scale
        let winH = baseH * scale

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - winW - 20
        let y = screenFrame.midY - winH / 2

        super.init(contentRect: NSRect(x: x, y: y, width: winW, height: winH),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)

        title = "idb mirror"
        contentView = mirrorView
        mirrorView.frame = NSRect(x: 0, y: 0, width: winW, height: winH)
        minSize = NSSize(width: 150, height: 300)
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
    private var tapThreshold: CGFloat { mirrorView.bounds.width * 0.015 }
    private var dragThreshold: CGFloat { mirrorView.bounds.width * 0.03 }

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
        let speed = dt > 0 ? dist / CGFloat(dt) : 500

        let (fx, fy) = toWDA(prev)
        let (tx, ty) = toWDA(pt)
        let wdaDx = tx - fx, wdaDy = ty - fy
        let wdaDist = sqrt(wdaDx * wdaDx + wdaDy * wdaDy)
        let mult = min(max(speed / 300, 1.0), 4.0)
        let nx = wdaDx / wdaDist, ny = wdaDy / wdaDist
        let endX = fx + nx * wdaDist * mult
        let endY = fy + ny * wdaDist * mult

        wda.swipe(fx, fy, endX, endY, max(0.05 / mult, 0.01))
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
                wda.swipe(fx, fy, tx, ty, 0.2)
            }
        }
        mouseDownPoint = nil; prevDragPoint = nil; dragging = false
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        if event.momentumPhase != [] { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScrollTime >= scrollThrottle else { return }

        let loc = mirrorView.convert(event.locationInWindow, from: nil)
        let (cx, cy) = toWDA(loc)
        let d: CGFloat = 150

        if abs(event.scrollingDeltaY) > 2 {
            lastScrollTime = now
            if event.scrollingDeltaY > 0 {
                wda.swipe(cx, max(cy - d/2, 10), cx, min(cy + d/2, wdaSize.1 - 10), 0.2)
            } else {
                wda.swipe(cx, min(cy + d/2, wdaSize.1 - 10), cx, max(cy - d/2, 10), 0.2)
            }
        } else if abs(event.scrollingDeltaX) > 2 {
            lastScrollTime = now
            if event.scrollingDeltaX > 0 {
                wda.swipe(max(cx - d/2, 10), cy, min(cx + d/2, wdaSize.0 - 10), cy, 0.2)
            } else {
                wda.swipe(min(cx + d/2, wdaSize.0 - 10), cy, max(cx - d/2, 10), cy, 0.2)
            }
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil) }
            return
        }
        // Option+Backspace = back
        if event.keyCode == 51 && event.modifierFlags.contains(.option) {
            wda.swipe(0, wdaSize.1 / 2, wdaSize.0 * 0.5, wdaSize.1 / 2, 0.3)
            return
        }
        switch event.keyCode {
        case 53: wda.pressButton("home")
        case 51: wda.typeKeys([String(UnicodeScalar(8))])  // plain backspace = delete key
        case 48: wda.swipe(wdaSize.0 / 2, wdaSize.1 - 5, wdaSize.0 / 2, wdaSize.1 * 0.4, 0.5)
        case 36: wda.typeKeys(["\n"])
        default:
            if let chars = event.characters, !chars.isEmpty {
                wda.typeKeys(chars.map { String($0) })
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
