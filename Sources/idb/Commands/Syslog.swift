import ArgumentParser
import Foundation

struct Syslog: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stream device logs (requires pymobiledevice3)")

    @Argument(help: "Device name")
    var device: String

    @Option(name: .shortAndLong, help: "Filter by process name")
    var process: String?

    func run() throws {
        // Check pymobiledevice3 is available
        let check = shell("which pymobiledevice3 2>/dev/null")
        if check.out.isEmpty {
            print("pymobiledevice3 not found. Install: pipx install pymobiledevice3")
            throw ExitCode.failure
        }

        let (_, dev) = try DeviceRegistry.resolve(device)
        var args = ["syslog", "live", "--udid", dev.udid]
        if let proc = process {
            args += ["--match", proc]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: check.out)
        task.arguments = args
        task.standardOutput = FileHandle.standardOutput
        task.standardError = FileHandle.standardError

        signal(SIGINT, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler { task.terminate() }
        src.resume()

        try task.run()
        task.waitUntilExit()
    }
}
