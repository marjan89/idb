import ArgumentParser
import Foundation

struct App: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch, terminate, or inspect apps",
        subcommands: [Launch.self, Kill.self, Active.self, Install.self, List_.self]
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

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install an app (.ipa or .app) on a device")
        @OptionGroup var deviceOpt: DeviceOption

        @Argument(help: "Path to .ipa or .app bundle")
        var path: String

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(deviceOpt.device)

            // Resolve CoreDevice UUID from device name via devicectl
            guard let uuid = DeviceRegistry.coreDeviceUUID(forName: name) else {
                // Fall back: try to find by scanning all connected devices
                let fallbackUUID = DeviceRegistry.coreDeviceUUID(forName: name)
                guard let uuid = fallbackUUID else {
                    print("Cannot find CoreDevice UUID for '\(name)'. Is the device connected?")
                    throw ExitCode.failure
                }
                return try installApp(uuid: uuid, path: path)
            }

            try installApp(uuid: uuid, path: path)
        }

        private func installApp(uuid: String, path: String) throws {
            let expandedPath = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                print("File not found: \(expandedPath)")
                throw ExitCode.failure
            }

            print("Installing \(expandedPath)...")
            let result = shell("xcrun devicectl device install app --device \(uuid) \"\(expandedPath)\" 2>&1")
            if result.code == 0 {
                print("Installed successfully.")
                if !result.out.isEmpty { print(result.out) }
            } else {
                print("Install failed:")
                print(result.out.isEmpty ? result.err : result.out)
                throw ExitCode.failure
            }
        }
    }

    struct List_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed apps on a device")
        @OptionGroup var deviceOpt: DeviceOption

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(deviceOpt.device)

            // Resolve CoreDevice UUID from device name via devicectl
            let uuid = DeviceRegistry.coreDeviceUUID(forName: name)
                ?? DeviceRegistry.coreDeviceUUID(forName: name)

            guard let uuid = uuid else {
                print("Cannot find CoreDevice UUID for '\(name)'. Is the device connected?")
                throw ExitCode.failure
            }

            let result = shell("xcrun devicectl device info apps --device \(uuid) 2>&1")
            if result.code == 0 {
                print(result.out)
            } else {
                print("Could not list apps:")
                print(result.out.isEmpty ? result.err : result.out)
                throw ExitCode.failure
            }
        }
    }
}
