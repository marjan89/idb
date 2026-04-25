import ArgumentParser
import Foundation

struct Syslog: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Tail device syslog via pymobiledevice3")

    @Argument(help: "Device name")
    var device: String

    @Option(name: .shortAndLong, help: "Filter by process name")
    var process: String?

    func run() throws {
        let (_, dev) = try DeviceRegistry.resolve(device)
        var cmd = "pymobiledevice3 syslog live --udid \(dev.udid)"
        if let proc = process {
            cmd += " --match '\(proc)'"
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", cmd]
        task.standardOutput = FileHandle.standardOutput
        task.standardError = FileHandle.standardError
        try task.run()
        task.waitUntilExit()
    }
}
