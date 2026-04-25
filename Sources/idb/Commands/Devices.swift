import ArgumentParser
import Foundation

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List enrolled devices and their status",
        subcommands: [List_.self, Status.self],
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
            print(String(format: "%-15s %-35s %-6s %s", "NAME", "MODEL", "PORT", "UDID"))
            print(String(repeating: "-", count: 80))
            for (name, dev) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                print(String(format: "%-15s %-35s %-6d %s", name, dev.model, dev.port, dev.udid))
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

                // Check WDA HTTP
                let wdaResult = shell("curl -s --connect-timeout 3 http://localhost:\(dev.port)/status")
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
                let ftResult = shell("python3 -c \"import socket; s=socket.socket(); s.settimeout(2); s.connect(('localhost',\(dev.port + 1100))); s.close(); print('ok')\" 2>/dev/null")
                if ftResult.out == "ok" {
                    print("  FastTouch:  READY on port \(dev.port + 1100)")
                } else {
                    print("  FastTouch:  NOT AVAILABLE")
                }
                print()
            }
        }
    }
}
