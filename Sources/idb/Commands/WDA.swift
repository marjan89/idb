import ArgumentParser
import Foundation

struct WDA: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage WebDriverAgent lifecycle",
        subcommands: [Start.self, Stop.self, Status.self, Build.self, BuildAll.self, Serve.self, InstallService.self, Log_.self]
    )

    // MARK: - Shared helpers

    static var config: IDBConfig { IDBConfig.load() }

    static func logPath(_ name: String) -> String { config.wdaLogPath(name) }
    static func pidPath(_ name: String) -> String { "\(config.logDir)/wda-\(name).pid" }
    static func derivedDataPath(_ name: String) -> String { config.derivedDataPath(name) }

    static func isWDARunning(_ name: String) -> Bool {
        guard let pidStr = try? String(contentsOfFile: pidPath(name), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return false }
        return kill(pid, 0) == 0
    }

    static func wdaPID(_ name: String) -> Int32? {
        guard let pidStr = try? String(contentsOfFile: pidPath(name), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return nil }
        return kill(pid, 0) == 0 ? pid : nil
    }

    static func killWDA(_ name: String) {
        if let pid = wdaPID(name) {
            kill(pid, SIGTERM)
            usleep(500_000)
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        // Also kill any xcodebuild targeting this device
        let devices = try? DeviceRegistry.load()
        if let dev = devices?[name] {
            shell("pkill -f 'xcodebuild.*\(dev.udid)' 2>/dev/null")
        }
        try? FileManager.default.removeItem(atPath: pidPath(name))
    }

    static func launchXcodebuild(name: String, dev: Device, wdaDir: String) -> Process {
        let ddPath = derivedDataPath(name)
        let log = logPath(name)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "test-without-building",
            "-project", "\(wdaDir)/WebDriverAgent.xcodeproj",
            "-scheme", "WebDriverAgentRunner",
            "-destination", "id=\(dev.udid)",
            "-derivedDataPath", ddPath,
            "DEVELOPMENT_TEAM=\(dev.teamId)",
            "CODE_SIGN_IDENTITY=\(dev.signingIdentity)",
            "PRODUCT_BUNDLE_IDENTIFIER=\(dev.bundleId)",
            "USE_PORT=\(dev.port)",
        ]

        let logHandle = FileHandle(forWritingAtPath: log) ?? {
            FileManager.default.createFile(atPath: log, contents: nil)
            return FileHandle(forWritingAtPath: log)!
        }()
        logHandle.seekToEndOfFile()
        process.standardOutput = logHandle
        process.standardError = logHandle

        return process
    }

    static func waitForReady(name: String, dev: Device, timeout: Int = 30) -> String? {
        for _ in 0..<timeout {
            sleep(1)
            // Check log for ServerURL
            if let log = try? String(contentsOfFile: logPath(name), encoding: .utf8),
               let range = log.range(of: "ServerURLHere->"),
               let endRange = log.range(of: "<-ServerURLHere", range: range.upperBound..<log.endIndex) {
                return String(log[range.upperBound..<endRange.lowerBound])
            }
        }
        return nil
    }

    // MARK: - Start

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start WDA on a device (foreground, single run)")

        @Argument(help: "Device name")
        var device: String

        @Option(help: "WDA source directory")
        var wdaDir: String = IDBConfig.load().resolvedWdaDir

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(device)

            // Kill existing
            WDA.killWDA(name)

            // Clear log
            FileManager.default.createFile(atPath: WDA.logPath(name), contents: nil)

            print("Starting WDA on \(name) (port \(dev.port))...")
            let process = WDA.launchXcodebuild(name: name, dev: dev, wdaDir: wdaDir)
            try process.run()

            // Save PID
            try "\(process.processIdentifier)".write(toFile: WDA.pidPath(name), atomically: true, encoding: .utf8)

            // Wait for ready
            if let url = WDA.waitForReady(name: name, dev: dev) {
                print("WDA ready at \(url)")
            } else {
                print("WDA started (PID \(process.processIdentifier)) but not responding yet. Check: idb wda log \(name)")
            }
        }
    }

    // MARK: - Stop

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop WDA on a device")

        @Argument(help: "Device name")
        var device: String

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(device)
            if WDA.isWDARunning(name) {
                WDA.killWDA(name)
                print("Stopped \(name)")
            } else {
                print("\(name): not running")
            }
        }
    }

    // MARK: - Status

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check WDA status")

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
                let pid = WDA.wdaPID(name)
                let ip = extractHostFromLog(name) ?? "localhost"
                let wdaCheck = shell("curl -s --connect-timeout 3 http://\(ip):\(dev.port)/status")
                let ready = wdaCheck.code == 0 && wdaCheck.out.contains("ready")

                print("== \(name) port=\(dev.port) ==")
                print("  Process:    \(pid != nil ? "RUNNING (PID \(pid!))" : "NOT RUNNING")")
                if ready {
                    print("  WDA:        READY at http://\(ip):\(dev.port)")
                } else {
                    print("  WDA:        NOT RESPONDING")
                }
                print()
            }
        }
    }

    // MARK: - Build

    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build WDA fork for deployment")

        @Argument(help: "Device name")
        var device: String

        @Flag(help: "Clean build (remove derived data first)")
        var clean = false

        @Option(help: "WDA source directory")
        var wdaDir: String = IDBConfig.load().resolvedWdaDir

        @Option(help: "Derived data path")
        var derivedData: String?

        @Flag(help: "Start WDA after building")
        var start = false

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(device)
            let ddPath = derivedData ?? WDA.derivedDataPath(name)

            if clean {
                print("Cleaning derived data...")
                shell("rm -rf \(ddPath)")
            }

            print("Building WDA...")
            let buildResult = shell("""
                cd \(wdaDir) && \
                xcodebuild build-for-testing \
                    -project WebDriverAgent.xcodeproj \
                    -scheme WebDriverAgentRunner \
                    -destination 'generic/platform=iOS' \
                    -allowProvisioningUpdates \
                    -derivedDataPath \(ddPath)
                """, timeout: 300)

            if buildResult.code != 0 {
                print("BUILD FAILED")
                for line in (buildResult.out + "\n" + buildResult.err).split(separator: "\n") where line.contains("error:") {
                    print("  \(line)")
                }
                throw ExitCode.failure
            }
            print("BUILD SUCCEEDED")

            if start {
                try Start.parse([name, "--wda-dir", wdaDir]).run()
            }
        }
    }

    // MARK: - Build All

    struct BuildAll: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build-all",
            abstract: "Rebuild WDA for all enrolled devices"
        )

        @Flag(help: "Clean build")
        var clean = false

        @Flag(help: "Start WDA after building each device")
        var start = false

        func run() throws {
            let devices = try DeviceRegistry.load()
            let sorted = devices.sorted(by: { $0.value.port < $1.value.port })

            for (name, _) in sorted {
                print("=== \(name) ===")
                var args = [name]
                if clean { args.append("--clean") }
                if start { args.append("--start") }
                do {
                    var build = try Build.parse(args)
                    try build.run()
                } catch {
                    print("  FAILED: \(error)")
                }
                print()
            }
        }
    }

    // MARK: - Serve (heartbeat daemon)

    struct Serve: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run WDA with auto-restart (daemon mode)")

        @Argument(help: "Device name")
        var device: String

        @Option(help: "WDA source directory")
        var wdaDir: String = IDBConfig.load().resolvedWdaDir

        @Option(help: "Max consecutive failures before giving up")
        var maxFailures: Int = 5

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(device)
            var failures = 0

            // Handle SIGTERM/SIGINT
            let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            signal(SIGTERM, SIG_IGN)
            signalSource.setEventHandler {
                fputs("[serve] SIGTERM received, stopping...\n", stderr)
                WDA.killWDA(name)
                Foundation.exit(0)
            }
            signalSource.resume()

            let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)
            intSource.setEventHandler {
                fputs("[serve] SIGINT received, stopping...\n", stderr)
                WDA.killWDA(name)
                Foundation.exit(0)
            }
            intSource.resume()

            fputs("[serve] Starting WDA heartbeat for \(name) (port \(dev.port))\n", stderr)

            while failures < maxFailures {
                // Clear log
                FileManager.default.createFile(atPath: WDA.logPath(name), contents: nil)

                let process = WDA.launchXcodebuild(name: name, dev: dev, wdaDir: wdaDir)
                do {
                    try process.run()
                } catch {
                    fputs("[serve] Failed to launch xcodebuild: \(error)\n", stderr)
                    failures += 1
                    sleep(5)
                    continue
                }

                try? "\(process.processIdentifier)".write(toFile: WDA.pidPath(name), atomically: true, encoding: .utf8)

                // Wait for ready
                if let url = WDA.waitForReady(name: name, dev: dev) {
                    fputs("[serve] WDA ready at \(url)\n", stderr)
                    failures = 0  // Reset on success
                } else {
                    fputs("[serve] WDA did not become ready within 30s\n", stderr)
                }

                // Wait for process to exit
                process.waitUntilExit()
                let code = process.terminationStatus
                fputs("[serve] xcodebuild exited with code \(code)\n", stderr)

                try? FileManager.default.removeItem(atPath: WDA.pidPath(name))

                if code == 0 {
                    // Clean exit (test suite finished normally) — restart
                    fputs("[serve] Clean exit, restarting in 2s...\n", stderr)
                    sleep(2)
                } else {
                    failures += 1
                    fputs("[serve] Failure \(failures)/\(maxFailures), restarting in 5s...\n", stderr)
                    sleep(5)
                }
            }

            fputs("[serve] Max failures (\(maxFailures)) reached. Giving up.\n", stderr)
            throw ExitCode.failure
        }
    }

    // MARK: - Install Service (launchd)

    struct InstallService: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-service",
            abstract: "Generate and install a launchd plist for WDA heartbeat"
        )

        @Argument(help: "Device name")
        var device: String

        @Option(help: "Path to idb binary")
        var idbPath: String?

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(device)

            let idb = idbPath ?? {
                // Try to find ourselves
                let execPath = CommandLine.arguments[0]
                if execPath.hasPrefix("/") { return execPath }
                return shell("which idb").out.isEmpty ? execPath : shell("which idb").out
            }()

            let label = "com.idb.wda.\(name)"
            let plistPath = NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath

            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(idb)</string>
                    <string>wda</string>
                    <string>serve</string>
                    <string>\(name)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>StandardOutPath</key>
                <string>/tmp/idb-wda-\(name).log</string>
                <key>StandardErrorPath</key>
                <string>/tmp/idb-wda-\(name).log</string>
                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/Applications/Xcode-26.0.1.app/Contents/Developer/usr/bin</string>
                </dict>
            </dict>
            </plist>
            """

            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            print("Wrote \(plistPath)")
            print()
            print("To enable:")
            print("  launchctl load \(plistPath)")
            print()
            print("To disable:")
            print("  launchctl unload \(plistPath)")
            print()
            print("To check:")
            print("  launchctl list | grep \(label)")
        }
    }

    // MARK: - Log

    struct Log_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "log", abstract: "Tail WDA log for a device")

        @Argument(help: "Device name")
        var device: String

        @Option(name: .shortAndLong, help: "Number of lines")
        var lines: Int = 50

        @Flag(name: .shortAndLong, help: "Follow (tail -f)")
        var follow = false

        func run() throws {
            let (name, _) = try DeviceRegistry.resolve(device)
            let log = WDA.logPath(name)

            if follow {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                task.arguments = ["-f", log]
                task.standardOutput = FileHandle.standardOutput
                try task.run()
                task.waitUntilExit()
            } else {
                let result = shell("tail -\(lines) \(log)")
                print(result.out)
            }
        }
    }
}
