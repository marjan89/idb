import Foundation

/// Registered device entry
struct Device: Codable {
    let udid: String
    let model: String
    let ios: String
    let teamId: String
    let signingIdentity: String
    let bundleId: String
    let port: Int
    var mjpegPort: Int?
    var fastTouchPort: Int?
    let enrolled: String

    enum CodingKeys: String, CodingKey {
        case udid, model, ios, port, enrolled
        case teamId = "team_id"
        case signingIdentity = "signing_identity"
        case bundleId = "bundle_id"
        case mjpegPort = "mjpeg_port"
        case fastTouchPort = "fast_touch_port"
    }

    /// Resolved MJPEG port — device-specific or global default
    var resolvedMjpegPort: Int { mjpegPort ?? IDBConfig.load().defaultMjpegPort }

    /// Resolved FastTouch port — device-specific or global default
    var resolvedFastTouchPort: Int { fastTouchPort ?? IDBConfig.load().defaultFastTouchPort }
}

/// Reads and manages the device registry (devices.json)
struct DeviceRegistry {
    static var path: String { NSString(string: IDBConfig.load().registryPath).expandingTildeInPath }

    static func load() throws -> [String: Device] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: Device].self, from: data)
    }

    static func save(_ devices: [String: Device]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(devices)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func resolve(_ name: String?) throws -> (name: String, device: Device) {
        let devices = try load()

        if let name = name {
            guard let device = devices[name] else {
                throw IDBError.unknownDevice(name, available: Array(devices.keys).sorted())
            }
            return (name, device)
        }

        if devices.count == 1, let (name, device) = devices.first {
            return (name, device)
        }

        throw IDBError.noDeviceSpecified(available: Array(devices.keys).sorted())
    }

    /// Resolve CoreDevice UUID for an enrolled device (needed for devicectl commands)
    static func coreDeviceUUID(forName name: String) -> String? {
        let result = shell("xcrun devicectl list devices 2>/dev/null")
        for line in result.out.components(separatedBy: "\n") {
            guard line.contains("connected") || line.contains("unavailable") else { continue }
            guard !line.contains("---") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let uuidIdx = parts.firstIndex(where: { $0.count == 36 && $0.contains("-") }) else { continue }
            let nameParts = parts.prefix(max(uuidIdx - 1, 0))
            if nameParts.joined(separator: " ") == name {
                return parts[uuidIdx]
            }
        }
        return nil
    }
}

enum IDBError: Error, CustomStringConvertible {
    case unknownDevice(String, available: [String])
    case noDeviceSpecified(available: [String])
    case wdaNotRunning(String)
    case fastTouchNotAvailable(String, Int)
    case commandFailed(String)

    var description: String {
        switch self {
        case .unknownDevice(let name, let available):
            return "Unknown device '\(name)'. Available: \(available.joined(separator: ", "))"
        case .noDeviceSpecified(let available):
            return "No device specified. Available: \(available.joined(separator: ", ")). Use --device <name>"
        case .wdaNotRunning(let name):
            return "WDA not running on '\(name)'. Run: idb wda start \(name)"
        case .fastTouchNotAvailable(let host, let port):
            return "FastTouch not available at \(host):\(port). Using WDA fork with FBFastTouchServer?"
        case .commandFailed(let msg):
            return msg
        }
    }
}
