import Foundation

/// Bridge between MirrorWindow input events and WDA/FastTouch
/// Keeps the mirror window decoupled from WDA/FastTouch internals
class MirrorWDABridge {
    private let httpClient: WDAClient
    private let fastTouch: FastTouchClient?
    private let cmdQueue = MirrorCommandQueue()

    init(httpClient: WDAClient, fastTouch: FastTouchClient?) {
        self.httpClient = httpClient
        self.fastTouch = fastTouch
    }

    func tap(_ x: CGFloat, _ y: CGFloat) {
        if let ft = fastTouch {
            ft.tap(Float(x), Float(y))
        } else {
            cmdQueue.trySubmit("tap") {
                try? self.httpClient.tap(Double(x), Double(y))
            }
        }
    }

    func swipe(_ fx: CGFloat, _ fy: CGFloat, _ tx: CGFloat, _ ty: CGFloat, _ duration: Double) {
        if let ft = fastTouch, duration <= 0.2 {
            ft.swipe(fromX: Float(fx), fromY: Float(fy), toX: Float(tx), toY: Float(ty), duration: Float(duration))
        } else {
            cmdQueue.trySubmit("swipe") {
                try? self.httpClient.swipe(fromX: Double(fx), fromY: Double(fy),
                                           toX: Double(tx), toY: Double(ty), duration: duration)
            }
        }
    }

    func pinch(_ cx: CGFloat, _ cy: CGFloat, scale: Double) {
        cmdQueue.trySubmit("pinch") {
            try? self.httpClient.pinch(centerX: Double(cx), centerY: Double(cy), scale: scale)
        }
    }

    func pressButton(_ name: String) {
        cmdQueue.trySubmit("button") {
            try? self.httpClient.pressButton(name)
        }
    }

    func typeKeys(_ keys: [String]) {
        cmdQueue.trySubmit("type") {
            try? self.httpClient.typeKeys(keys)
        }
    }
}

/// Command queue with latest-wins pending for mirror interactions
class MirrorCommandQueue {
    private let queue = DispatchQueue(label: "mirror.commands")
    private var busy = false
    private var pending: (label: String, block: () -> Void)?

    @discardableResult
    func trySubmit(_ label: String, _ block: @escaping () -> Void) -> Bool {
        var accepted = false
        queue.sync {
            if !busy { busy = true; accepted = true }
            else { pending = (label, block) }
        }
        if accepted { execute(label, block) }
        return accepted
    }

    private func execute(_ label: String, _ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            block()
            var next: (label: String, block: () -> Void)?
            self.queue.sync {
                next = self.pending
                self.pending = nil
                if next == nil { self.busy = false }
            }
            if let next = next { self.execute(next.label, next.block) }
        }
    }
}
