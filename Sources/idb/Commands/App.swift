import ArgumentParser
import Foundation

struct App: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch, terminate, or inspect apps",
        subcommands: [Launch.self, Kill.self, Active.self]
    )

    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch an app by bundle ID")
        @OptionGroup var deviceOpt: DeviceOption
        @Argument(help: "Bundle ID (e.g. com.apple.Preferences)")
        var bundleId: String

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
            let wda = try connectWDA(dev, name: name)
            try wda.launch(bundleId: bundleId)
            print("Launched \(bundleId)")
        }
    }

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Terminate an app by bundle ID")
        @OptionGroup var deviceOpt: DeviceOption
        @Argument(help: "Bundle ID")
        var bundleId: String

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
            let wda = try connectWDA(dev, name: name)
            try wda.terminate(bundleId: bundleId)
            print("Terminated \(bundleId)")
        }
    }

    struct Active: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the active (foreground) app")
        @OptionGroup var deviceOpt: DeviceOption

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
            let wda = try connectWDA(dev, name: name)
            let info = try wda.activeApp()
            if let bid = info["bundleId"] as? String { print("Bundle: \(bid)") }
            if let pid = info["pid"] as? Int { print("PID:    \(pid)") }
        }
    }
}
