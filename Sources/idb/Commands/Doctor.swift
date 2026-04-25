import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check system health — tools, devices, WDA, signing")

    func run() throws {
        var issues = 0

        heading("Tools")
        issues += check("xcodebuild", "xcodebuild -version 2>/dev/null | head -1")
        issues += check("xcrun devicectl", "xcrun devicectl --version 2>/dev/null || echo 'missing'")
        issues += check("pymobiledevice3", "pymobiledevice3 version 2>/dev/null || echo 'missing'")
        issues += check("nosandbox", "test -x ~/.claude/bin/nosandbox && echo 'ok' || echo 'missing'")
        issues += check("ios-mirror", "test -x /Users/Shared/projects/device-tools/ios-mirror/.build/release/ios-mirror && echo 'ok' || echo 'not built'")

        heading("Signing")
        let sigResult = shell("security find-identity -v -p codesigning 2>/dev/null | grep 'marjan89@gmail.com'")
        if sigResult.out.isEmpty {
            fail("Signing identity for marjan89@gmail.com not found")
            issues += 1
        } else {
            let name = sigResult.out.components(separatedBy: "\"").dropFirst().first ?? "?"
            pass("Signing identity: \(name)")
        }

        heading("WDA Fork")
        let wdaPath = "/Users/Shared/projects/device-tools/WebDriverAgent"
        if FileManager.default.fileExists(atPath: wdaPath + "/WebDriverAgentLib/Utilities/FBFastTouchServer.m") {
            pass("WDA fork with FBFastTouchServer")
        } else {
            fail("WDA fork not found or missing FBFastTouchServer at \(wdaPath)")
            issues += 1
        }

        heading("Device Registry")
        do {
            let devices = try DeviceRegistry.load()
            pass("\(devices.count) device(s) enrolled")
            for (name, dev) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                print("  \(name): \(dev.model) port=\(dev.port)")
            }
        } catch {
            fail("Cannot read devices.json: \(error)")
            issues += 1
        }

        heading("Device Connectivity")
        let devicesResult = shell("xcrun devicectl list devices 2>/dev/null")
        let connectedCount = devicesResult.out.components(separatedBy: "\n")
            .filter { $0.contains("connected") && !$0.contains("unavailable") }.count
        if connectedCount > 0 {
            pass("\(connectedCount) device(s) connected")
        } else {
            warn("No devices connected (check USB/WiFi)")
        }

        heading("WDA Status")
        do {
            let devices = try DeviceRegistry.load()
            for (name, dev) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                let ip = extractHostFromLog(name) ?? "localhost"
                let wdaCheck = shell("curl -s --connect-timeout 3 http://\(ip):\(dev.port)/status")
                if wdaCheck.code == 0, wdaCheck.out.contains("ready") {
                    pass("\(name): WDA ready at \(ip):\(dev.port)")

                    let ftPort = dev.resolvedFastTouchPort
                    let ftCheck = shell("python3 -c \"import socket; s=socket.socket(); s.settimeout(2); s.connect(('\(ip)',\(ftPort))); s.close(); print('ok')\" 2>/dev/null")
                    if ftCheck.out == "ok" {
                        pass("\(name): FastTouch ready on port \(ftPort)")
                    } else {
                        warn("\(name): FastTouch not available (port \(ftPort))")
                    }
                } else {
                    warn("\(name): WDA not responding (tried \(ip):\(dev.port))")
                }
            }
        } catch {}

        heading("Disk Space")
        let dfResult = shell("df -h / | tail -1")
        let parts = dfResult.out.split(separator: " ").map(String.init)
        if let avail = parts.dropFirst(3).first {
            if avail.hasSuffix("Mi") || avail.hasSuffix("M") {
                let mb = Int(avail.filter(\.isNumber)) ?? 0
                if mb < 500 {
                    fail("Low disk space: \(avail) available")
                    issues += 1
                } else {
                    pass("Disk: \(avail) available")
                }
            } else {
                pass("Disk: \(avail) available")
            }
        }

        print()
        if issues == 0 {
            print("All checks passed.")
        } else {
            print("\(issues) issue(s) found.")
        }
    }

    private func heading(_ title: String) {
        print("\n\(title)")
        print(String(repeating: "-", count: 40))
    }

    private func pass(_ msg: String) { print("  OK  \(msg)") }
    private func fail(_ msg: String) { print("  FAIL  \(msg)") }
    private func warn(_ msg: String) { print("  WARN  \(msg)") }

    @discardableResult
    private func check(_ name: String, _ cmd: String) -> Int {
        let result = shell(cmd)
        let out = result.out.isEmpty ? "not found" : result.out
        if out.contains("missing") || out.contains("not found") || out.contains("not built") {
            fail("\(name): \(out)")
            return 1
        }
        pass("\(name): \(out)")
        return 0
    }
}
