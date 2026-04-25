import ArgumentParser
import Foundation

struct Home: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Press the home button")

    @OptionGroup var deviceOpt: DeviceOption

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        try wda.pressButton("home")
    }
}

struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Swipe from left edge to go back")

    @OptionGroup var deviceOpt: DeviceOption

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        let size = try wda.windowSize()
        try wda.swipe(fromX: 0, fromY: size.height / 2,
                      toX: size.width * 0.5, toY: size.height / 2,
                      duration: 0.3)
    }
}

struct Scroll_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "scroll", abstract: "Scroll in a direction from screen center")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "Direction: up, down, left, right")
    var direction: String

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        let size = try wda.windowSize()

        let cx = size.width / 2
        let cy = size.height / 2
        let dist = 150.0

        let (fromX, fromY, toX, toY): (Double, Double, Double, Double)
        switch direction.lowercased() {
        case "up":
            (fromX, fromY, toX, toY) = (cx, cy + dist, cx, cy - dist)
        case "down":
            (fromX, fromY, toX, toY) = (cx, cy - dist, cx, cy + dist)
        case "left":
            (fromX, fromY, toX, toY) = (cx + dist, cy, cx - dist, cy)
        case "right":
            (fromX, fromY, toX, toY) = (cx - dist, cy, cx + dist, cy)
        default:
            throw IDBError.commandFailed("Unknown direction '\(direction)'. Use: up, down, left, right")
        }

        try wda.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: 0.3)
    }
}
