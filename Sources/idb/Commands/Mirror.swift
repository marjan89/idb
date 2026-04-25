import AppKit
import ArgumentParser
import Foundation

struct Mirror_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mirror", abstract: "Mirror device screen with interactive input")

    @Argument(help: "Device name")
    var device: String?

    @Option(name: .long, help: "Window scale factor")
    var scale: Double = 0.5

    @Option(name: .long, help: "MJPEG stream port (overrides device/global default)")
    var mjpegPort: Int?

    @Option(name: .long, help: "FastTouch binary port (overrides device/global default)")
    var touchPort: Int?

    func run() throws {
        // Resolve device — list available if none specified
        let name: String
        let dev: Device
        do {
            (name, dev) = try DeviceRegistry.resolve(device)
        } catch {
            print(error)
            // Show available devices with WDA status
            if let devices = try? DeviceRegistry.load() {
                print("\nAvailable devices:")
                for (n, d) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                    let ip = extractHostFromLog(n) ?? "localhost"
                    let wdaCheck = shell("curl -s --connect-timeout 2 http://\(ip):\(d.port)/status")
                    let status = wdaCheck.out.contains("ready") ? "WDA ready" : "WDA not running"
                    print("  \(n.padding(toLength: 15, withPad: " ", startingAt: 0)) \(status)")
                }
            }
            throw ExitCode.failure
        }

        let host = resolveHost(name, dev)

        // Connect WDA HTTP
        let wda = WDAClient(baseURL: "http://\(host):\(dev.port)")
        do {
            let status = try wda.status()
            let os = status["os"] as? [String: Any]
            fputs("[mirror] Device: \(os?["name"] ?? "?") \(os?["version"] ?? "?")\n", stderr)
            let _ = try wda.createSession()
        } catch {
            print("Cannot connect to WDA at \(host):\(dev.port). Run: idb wda start \(name)")
            throw ExitCode.failure
        }

        // Boost MJPEG
        wda.configureMJPEG(fps: 60, quality: 40, scalingFactor: 50)

        // Get window size
        let winSize = try wda.windowSize()

        // Connect FastTouch
        let ft = FastTouchClient()
        let ftPort = UInt16(touchPort ?? dev.resolvedFastTouchPort)
        if ft.connect(host: host, port: ftPort) {
            fputs("[mirror] FastTouch connected (\(host):\(ftPort))\n", stderr)
        } else {
            fputs("[mirror] FastTouch not available, using HTTP fallback\n", stderr)
        }

        let bridge = MirrorWDABridge(httpClient: wda, fastTouch: ft.connected ? ft : nil)

        // Start MJPEG
        let resolvedMjpegPort = mjpegPort ?? dev.resolvedMjpegPort
        let mjpegURL = URL(string: "http://\(host):\(resolvedMjpegPort)")!
        let stream = MJPEGStream(url: mjpegURL)
        let firstFrameSem = DispatchSemaphore(value: 0)
        var gotFirst = false
        stream.onFrame = { _ in
            if !gotFirst { gotFirst = true; firstFrameSem.signal() }
        }
        stream.start()

        if firstFrameSem.wait(timeout: .now() + 10) == .timedOut {
            print("No MJPEG frames received. Check device connection.")
            throw ExitCode.failure
        }

        // Launch AppKit window on main thread
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = MirrorAppDelegate(
            bridge: bridge, stream: stream,
            wdaSize: (CGFloat(winSize.width), CGFloat(winSize.height)),
            imageSize: stream.imagePixelSize, scale: CGFloat(scale)
        )
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)

        fputs("[mirror] Ready — click=tap, drag=swipe, scroll=scroll, ESC=home, Cmd+Q=quit\n", stderr)
        app.run()

        ft.disconnect()
        stream.stop()
    }
}

private class MirrorAppDelegate: NSObject, NSApplicationDelegate {
    let bridge: MirrorWDABridge
    let stream: MJPEGStream
    let wdaSize: (CGFloat, CGFloat)
    let imageSize: NSSize?
    let scale: CGFloat
    var window: MirrorWindow?

    init(bridge: MirrorWDABridge, stream: MJPEGStream, wdaSize: (CGFloat, CGFloat), imageSize: NSSize?, scale: CGFloat) {
        self.bridge = bridge
        self.stream = stream
        self.wdaSize = wdaSize
        self.imageSize = imageSize
        self.scale = scale
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let win = MirrorWindow(wda: bridge, wdaSize: wdaSize, imageSize: imageSize, scale: scale)
        self.window = win
        stream.onFrame = { [weak win] image in win?.updateImage(image) }
        if let img = stream.latestImage { win.updateImage(img) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
