import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check system health — tools, devices, WDA, signing")

    func run() throws {
        var issues = 0
        let config = IDBConfig.load()

        heading("Tools")
        issues += check("xcodebuild", "xcodebuild -version 2>/dev/null | head -1")
        issues += check("xcrun devicectl", "xcrun devicectl --version 2>/dev/null || echo 'missing'")
        issues += check("pymobiledevice3", "pymobiledevice3 version 2>/dev/null || echo 'missing'")

        // Check Xcode SDK version vs connected device iOS versions
        let xcodeVersion = shell("xcodebuild -version 2>/dev/null | head -1")
        let xcodeVer = xcodeVersion.out.replacingOccurrences(of: "Xcode ", with: "")
        let sdkResult = shell("xcodebuild -showsdks 2>/dev/null | grep iphoneos | tail -1")
        let sdkVer = sdkResult.out.components(separatedBy: "iphoneos").last?.trimmingCharacters(in: .whitespaces) ?? xcodeVer

        do {
            let devices = try DeviceRegistry.load()
            for (name, dev) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                // Compare major.minor: SDK must be >= device iOS
                let sdkParts = sdkVer.split(separator: ".").compactMap { Int($0) }
                let iosParts = dev.ios.split(separator: ".").compactMap { Int($0) }
                if sdkParts.count >= 1 && iosParts.count >= 1 {
                    let sdkMajor = sdkParts[0]
                    let sdkMinor = sdkParts.count > 1 ? sdkParts[1] : 0
                    let iosMajor = iosParts[0]
                    let iosMinor = iosParts.count > 1 ? iosParts[1] : 0
                    if sdkMajor < iosMajor || (sdkMajor == iosMajor && sdkMinor < iosMinor) {
                        fail("\(name): iOS \(dev.ios) requires Xcode SDK >= \(iosMajor).\(iosMinor), have \(sdkVer)")
                        issues += 1
                    }
                }
            }
        } catch {}

        heading("Signing")
        let email = config.signingEmail
        if email.isEmpty {
            warn("signing_email not set in config — skipping signing check")
        } else {
            let sigResult = shell("security find-identity -v -p codesigning 2>/dev/null | grep '\(email)'")
            if sigResult.out.isEmpty {
                fail("Signing identity for \(email) not found")
                issues += 1
            } else {
                let name = sigResult.out.components(separatedBy: "\"").dropFirst().first ?? "?"
                pass("Signing identity: \(name)")
            }
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
            fail("Cannot read devices.toml: \(error)")
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

        heading("Config Paths")
        let wdaDir = NSString(string: config.wdaDir).expandingTildeInPath
        let registryPath = NSString(string: config.registryPath).expandingTildeInPath
        if FileManager.default.fileExists(atPath: wdaDir) {
            pass("wdaDir: \(wdaDir)")
        } else {
            fail("wdaDir not found: \(wdaDir)")
            issues += 1
        }
        if FileManager.default.fileExists(atPath: registryPath) {
            pass("registryPath: \(registryPath)")
        } else {
            fail("registryPath not found: \(registryPath)")
            issues += 1
        }

        heading("Cert Expiry")
        do {
            let devices = try DeviceRegistry.load()
            for (name, _) in devices.sorted(by: { $0.value.port < $1.value.port }) {
                let logPath = config.wdaLogPath(name)
                guard let log = try? String(contentsOfFile: logPath, encoding: .utf8) else {
                    warn("\(name): No WDA log found at \(logPath)")
                    continue
                }
                // Look for "Built at" timestamp in the log
                // Find the LAST "Built at" (most recent build)
                if let range = log.range(of: "Built at ", options: .backwards) {
                    let rest = log[range.upperBound...]
                    let dateLine = rest.prefix(while: { !$0.isNewline })
                    // Take only first 20 chars — "Apr 25 2026 03:07:47"
                    let dateStr = String(dateLine.prefix(20)).trimmingCharacters(in: .whitespaces)
                    // Try common date formats
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    var builtDate: Date?
                    for fmt in ["MMM dd yyyy HH:mm:ss", "MMM d yyyy HH:mm:ss", "MMM d, yyyy HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
                        formatter.dateFormat = fmt
                        if let d = formatter.date(from: dateStr) {
                            builtDate = d
                            break
                        }
                    }
                    if let builtDate = builtDate {
                        let age = Date().timeIntervalSince(builtDate)
                        let days = Int(age / 86400)
                        if days >= 5 {
                            warn("\(name): WDA built \(days) days ago — free dev cert expires at 7 days. Rebuild soon.")
                        } else {
                            pass("\(name): WDA built \(days) day(s) ago")
                        }
                    } else {
                        warn("\(name): Could not parse 'Built at' date: \(dateStr)")
                    }
                } else {
                    warn("\(name): No 'Built at' timestamp in WDA log")
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
