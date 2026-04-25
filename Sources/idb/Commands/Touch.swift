import ArgumentParser
import Foundation

/// Options shared by touch commands
struct DeviceOption: ParsableArguments {
    @Option(name: .shortAndLong, help: "Device name")
    var device: String?

    @Flag(name: .long, help: "Force HTTP path (skip FastTouch)")
    var http = false
}

struct Tap: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Tap at coordinates (WDA points)")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "X coordinate")
    var x: Double

    @Argument(help: "Y coordinate")
    var y: Double

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)

        if !deviceOpt.http {
            let ft = FastTouchClient()
            let host = try extractHost(dev)
            if ft.connect(host: host, port: UInt16(dev.port + 1100)) {
                if ft.tap(Float(x), Float(y)) {
                    return
                }
                ft.disconnect()
            }
        }

        // HTTP fallback
        let wda = try connectWDA(dev)
        try wda.tap(x, y)
    }
}

struct Swipe: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Swipe between coordinates (WDA points)")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "From X")
    var fromX: Double

    @Argument(help: "From Y")
    var fromY: Double

    @Argument(help: "To X")
    var toX: Double

    @Argument(help: "To Y")
    var toY: Double

    @Option(name: .shortAndLong, help: "Duration in seconds")
    var duration: Double = 0.3

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)

        if !deviceOpt.http && duration <= 0.2 {
            let ft = FastTouchClient()
            let host = try extractHost(dev)
            if ft.connect(host: host, port: UInt16(dev.port + 1100)) {
                if ft.swipe(fromX: Float(fromX), fromY: Float(fromY),
                            toX: Float(toX), toY: Float(toY), duration: Float(duration)) {
                    return
                }
                ft.disconnect()
            }
        }

        let wda = try connectWDA(dev)
        try wda.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration)
    }
}

struct Type_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "type", abstract: "Type text on the device")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "Text to type")
    var text: String

    func run() throws {
        let (_, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev)
        try wda.typeKeys(text.map { String($0) })
    }
}

struct Button: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Press a hardware button")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "Button name: home, volumeUp, volumeDown")
    var name: String

    func run() throws {
        let (_, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev)
        try wda.pressButton(name)
    }
}

// MARK: - Helpers

func extractHost(_ dev: Device) throws -> String {
    // Try WDA status for IP
    let result = shell("curl -s --connect-timeout 3 http://localhost:\(dev.port)/status")
    if let data = result.out.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let value = json["value"] as? [String: Any],
       let ios = value["ios"] as? [String: Any],
       let ip = ios["ip"] as? String {
        return ip
    }
    return "localhost"
}

func connectWDA(_ dev: Device) throws -> WDAClient {
    let host = try extractHost(dev)
    let wda = WDAClient(baseURL: "http://\(host):\(dev.port)")
    let _ = try wda.status()
    let _ = try wda.createSession()
    return wda
}
