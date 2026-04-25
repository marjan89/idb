import ArgumentParser
import Foundation

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List, enroll, and manage devices",
        subcommands: [List_.self, Status.self, Add.self, Remove.self, Discover.self],
        defaultSubcommand: List_.self
    )

    struct List_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List enrolled devices")

        func run() throws {
            let devices = try DeviceRegistry.load()
            if devices.isEmpty {
                print("No devices enrolled. Add devices to \(DeviceRegistry.path)")
                return
            }
            let fmt = { (n: String, m: String, p: String, u: String) in
                "\(n.padding(toLength: 15, withPad: " ", startingAt: 0))\(m.padding(toLength: 35, withPad: " ", startingAt: 0))\(p.padding(toLength: 8, withPad: " ", startingAt: 0))\(u)"
            }
            print(fmt("NAME", "MODEL", "PORT", "UDID"))
            print(String(repeating: "-", count: 80))
            for (name, dev) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                print(fmt(name, dev.model, "\(dev.port)", dev.udid))
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check device connectivity and WDA status")

        @Argument(help: "Device name (optional, checks all if omitted)")
        var device: String?

        func run() throws {
            let devices = try DeviceRegistry.load()
            let targets: [(String, Device)]

            if let name = device {
                let (n, d) = try DeviceRegistry.resolve(name)
                targets = [(n, d)]
            } else {
                targets = devices.sorted(by: { $0.value.port < $1.value.port }).map { ($0.key, $0.value) }
            }

            for (name, dev) in targets {
                print("== \(name) (\(dev.udid)) port=\(dev.port) ==")

                // Check WDA HTTP — try WiFi IP from wda log, fall back to localhost
                let ip = extractHostFromLog(name) ?? "localhost"
                let wdaResult = shell("curl -s --connect-timeout 3 http://\(ip):\(dev.port)/status")
                if wdaResult.code == 0, wdaResult.out.contains("ready") {
                    // Extract IP
                    if let data = wdaResult.out.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let value = json["value"] as? [String: Any],
                       let ios = value["ios"] as? [String: Any],
                       let ip = ios["ip"] as? String {
                        print("  WDA:        READY at http://\(ip):\(dev.port)")
                    } else {
                        print("  WDA:        READY")
                    }
                } else {
                    print("  WDA:        NOT RESPONDING")
                }

                // Check FastTouch
                let ftPort = dev.resolvedFastTouchPort
                let ftResult = shell("python3 -c \"import socket; s=socket.socket(); s.settimeout(2); s.connect(('\(ip)',\(ftPort))); s.close(); print('ok')\" 2>/dev/null")
                if ftResult.out == "ok" {
                    print("  FastTouch:  READY on port \(ftPort)")
                } else {
                    print("  FastTouch:  NOT AVAILABLE")
                }
                print()
            }
        }
    }
}

/// Extract device IP from WDA log
func extractHostFromLog(_ deviceName: String) -> String? {
    let logPath = IDBConfig.load().wdaLogPath(deviceName)
    guard let log = try? String(contentsOfFile: logPath, encoding: .utf8) else { return nil }
    // Look for "ServerURLHere->http://IP:PORT<-ServerURLHere"
    guard let range = log.range(of: "ServerURLHere->http://"),
          let endRange = log.range(of: "<-ServerURLHere", range: range.upperBound..<log.endIndex) else { return nil }
    let url = String(log[range.upperBound..<endRange.lowerBound])
    // Extract host from "IP:PORT"
    return url.components(separatedBy: ":").first
}
