import ArgumentParser
import Foundation

extension Devices {
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Enroll a new device")

        @Argument(help: "Device name (short alias, e.g. 'phone')")
        var name: String

        @Option(help: "Device UDID (auto-detected if omitted)")
        var udid: String?

        @Option(help: "WDA port (auto-assigned if omitted)")
        var port: Int?

        @Option(help: "Signing team ID")
        var team: String = "8WLC7943H8"

        @Option(help: "Bundle ID for WDA")
        var bundleId: String = "com.marjan89.WebDriverAgentRunner"

        func run() throws {
            var devices = (try? DeviceRegistry.load()) ?? [:]

            if devices[name] != nil {
                print("Device '\(name)' already enrolled. Remove it first: idb devices remove \(name)")
                throw ExitCode.failure
            }

            // Resolve UDID
            let resolvedUDID: String
            if let udid = udid {
                resolvedUDID = udid
            } else {
                let connected = discoverDevices()
                let unenrolled = connected.filter { conn in
                    !devices.values.contains(where: { $0.udid == conn.udid })
                }
                if unenrolled.isEmpty {
                    print("No unenrolled devices found. Connect a device or specify --udid.")
                    print("\nConnected devices:")
                    for d in connected {
                        let enrolled = devices.values.contains(where: { $0.udid == d.udid })
                        print("  \(d.udid)  \(d.model)  \(enrolled ? "(enrolled)" : "")")
                    }
                    throw ExitCode.failure
                }
                if unenrolled.count == 1 {
                    resolvedUDID = unenrolled[0].udid
                    print("Auto-detected: \(unenrolled[0].model) (\(resolvedUDID))")
                } else {
                    print("Multiple unenrolled devices found. Specify --udid:")
                    for d in unenrolled {
                        print("  \(d.udid)  \(d.model)")
                    }
                    throw ExitCode.failure
                }
            }

            // Get device info
            let info = deviceInfo(udid: resolvedUDID)

            // Assign port
            let resolvedPort: Int
            if let port = port {
                resolvedPort = port
            } else {
                let usedPorts = Set(devices.values.map(\.port))
                resolvedPort = (8100...8199).first(where: { !usedPorts.contains($0) }) ?? 8100
            }

            let device = Device(
                udid: resolvedUDID,
                model: info.model,
                ios: info.ios,
                teamId: team,
                signingIdentity: "Apple Development",
                bundleId: bundleId,
                port: resolvedPort,
                enrolled: ISO8601DateFormatter.string(from: Date(),
                    timeZone: .current, formatOptions: [.withFullDate])
            )

            devices[name] = device
            try DeviceRegistry.save(devices)

            print("Enrolled '\(name)':")
            print("  Model: \(device.model)")
            print("  iOS:   \(device.ios)")
            print("  UDID:  \(device.udid)")
            print("  Port:  \(device.port)")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an enrolled device")

        @Argument(help: "Device name")
        var name: String

        func run() throws {
            var devices = try DeviceRegistry.load()
            guard devices.removeValue(forKey: name) != nil else {
                print("Device '\(name)' not found.")
                throw ExitCode.failure
            }
            try DeviceRegistry.save(devices)
            print("Removed '\(name)'")
        }
    }

    struct Discover: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List connected devices not yet enrolled")

        func run() throws {
            let devices = (try? DeviceRegistry.load()) ?? [:]
            let connected = discoverDevices()

            if connected.isEmpty {
                print("No devices found. Check USB/WiFi connection.")
                return
            }

            let fmt = { (u: String, m: String, s: String) in
                "\(u.padding(toLength: 28, withPad: " ", startingAt: 0))\(m.padding(toLength: 35, withPad: " ", startingAt: 0))\(s)"
            }
            print(fmt("UDID", "MODEL", "STATUS"))
            print(String(repeating: "-", count: 75))
            for d in connected {
                if let enrolled = devices.first(where: { $0.value.udid == d.udid }) {
                    print(fmt(d.udid, d.model, "enrolled as '\(enrolled.key)'"))
                } else {
                    print(fmt(d.udid, d.model, "available"))
                }
            }
        }
    }
}

// MARK: - Helpers

private struct ConnectedDevice {
    let udid: String
    let model: String
    let state: String
}

private struct DeviceInfo {
    let model: String
    let ios: String
}

private func discoverDevices() -> [ConnectedDevice] {
    let result = shell("xcrun devicectl list devices 2>/dev/null")
    var devices: [ConnectedDevice] = []

    for line in result.out.components(separatedBy: "\n") {
        // Skip header lines
        guard line.contains("connected") || line.contains("unavailable") else { continue }
        guard !line.contains("---") else { continue }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Format: Name  Hostname  Identifier  State  Model...
        // Find the UUID (36-char with dashes)
        guard let uuidIdx = parts.firstIndex(where: { $0.count == 36 && $0.contains("-") }) else { continue }

        let identifier = parts[uuidIdx]
        let state = uuidIdx + 1 < parts.count ? parts[uuidIdx + 1] : "unknown"

        // Model is everything after state
        let modelParts = parts.dropFirst(uuidIdx + 2)
        let model = modelParts.joined(separator: " ")

        // We need the UDID, not the CoreDevice identifier — get it from usbmux or pymobiledevice3
        // For now use the identifier
        devices.append(ConnectedDevice(udid: identifier, model: model, state: state))
    }

    return devices
}

private func deviceInfo(udid: String) -> DeviceInfo {
    // Try to get model and iOS version from devicectl
    let result = shell("xcrun devicectl list devices 2>/dev/null")
    for line in result.out.components(separatedBy: "\n") {
        if line.contains(udid) {
            // Extract model from the line
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if let uuidIdx = parts.firstIndex(of: udid) {
                let modelParts = parts.dropFirst(uuidIdx + 2)
                let model = modelParts.joined(separator: " ")
                return DeviceInfo(model: model, ios: "unknown")
            }
        }
    }
    return DeviceInfo(model: "Unknown", ios: "unknown")
}

