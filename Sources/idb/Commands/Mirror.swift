import ArgumentParser
import Foundation

struct Mirror_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mirror", abstract: "Launch ios-mirror for a device")

    @Argument(help: "Device name")
    var device: String

    @Option(name: .long, help: "Window scale factor")
    var scale: Double = 0.5

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(device)
        let host = try extractHost(dev)

        let mirrorPath = "/Users/Shared/projects/device-tools/ios-mirror/.build/release/ios-mirror"
        guard FileManager.default.fileExists(atPath: mirrorPath) else {
            print("ios-mirror not built. Run: cd ../ios-mirror && swift build -c release")
            throw ExitCode.failure
        }

        print("Launching ios-mirror for \(name) at \(host)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: mirrorPath)
        task.arguments = [
            "--wda-host", host,
            "--wda-port", "\(dev.port)",
            "--mjpeg-port", "\(dev.port + 1000)",
            "--touch-port", "\(dev.port + 1100)",
            "--scale", "\(scale)",
        ]
        try task.run()
        task.waitUntilExit()
    }
}
