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
    let enrolled: String

    enum CodingKeys: String, CodingKey {
        case udid, model, ios, port, enrolled
        case teamId = "team_id"
        case signingIdentity = "signing_identity"
        case bundleId = "bundle_id"
    }
}

/// Reads and manages the device registry (devices.json)
struct DeviceRegistry {
    static var path: String { NSString(string: IDBConfig.load().registryPath).expandingTildeInPath }

    static func load() throws -> [String: Device] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: Device].self, from: data)
    }

    static func resolve(_ name: String?) throws -> (name: String, device: Device) {
        let devices = try load()

        if let name = name {
            guard let device = devices[name] else {
                throw IDBError.unknownDevice(name, available: Array(devices.keys).sorted())
            }
            return (name, device)
        }

        // Auto-select if only one device
        if devices.count == 1, let (name, device) = devices.first {
            return (name, device)
        }

        throw IDBError.noDeviceSpecified(available: Array(devices.keys).sorted())
    }

    /// Get WDA base URL for a device
    static func wdaURL(for device: Device) throws -> String {
        // Try to get the device's WiFi IP from WDA status
        let url = URL(string: "http://localhost:\(device.port)/status")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["value"] as? [String: Any],
               let ios = value["ios"] as? [String: Any],
               let ip = ios["ip"] as? String {
                result = "http://\(ip):\(device.port)"
            }
            sem.signal()
        }.resume()
        sem.wait()

        if let result = result { return result }

        // Fallback: try the device IP from wda log
        let logPath = "/tmp/wda-\(device.udid.prefix(8)).log"
        if let log = try? String(contentsOfFile: logPath),
           let range = log.range(of: "ServerURLHere->"),
           let endRange = log.range(of: "<-ServerURLHere", range: range.upperBound..<log.endIndex) {
            return String(log[range.upperBound..<endRange.lowerBound])
        }

        return "http://localhost:\(device.port)"
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
