import ArgumentParser
import Foundation

// Global state for signal handler in Serve (C function pointers can't capture context)
private var _serveDeviceName: String = ""
private func _serveSignalHandler(_ sig: Int32) {
    fputs("[serve] Signal \(sig) received, stopping...\n", stderr)
    WDA.killWDA(_serveDeviceName)
    Foundation.exit(0)
}

struct WDA: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage WebDriverAgent lifecycle",
        subcommands: [Start.self, Stop.self, Status.self, Build.self, BuildAll.self, Serve.self, InstallService.self, Log_.self]
    )

    private enum Timeout {
        /// Grace period after SIGTERM before SIGKILL (microseconds)
        static let killGrace: useconds_t = 500_000
        /// Max seconds to wait for WDA ready after launch
        static let readyWait = 30
        /// Seconds between restart attempts after clean exit
        static let restartClean: UInt32 = 2
        /// Seconds between restart attempts after failure
        static let restartFailed: UInt32 = 5
        /// xcodebuild build timeout (seconds)
        static let build: TimeInterval = 300
        /// xcodebuild destination timeout (seconds) — physical devices can be slow
        static let destination = 120
    }

    // MARK: - Shared helpers

    static var config: IDBConfig { IDBConfig.load() }

    static func logPath(_ name: String) -> String { config.wdaLogPath(name) }
    static func pidPath(_ name: String) -> String { "\(config.logDir)/wda-\(name).pid" }
    static func derivedDataPath(_ name: String) -> String { config.derivedDataPath(name) }

    static func wdaPID(_ name: String) -> Int32? {
        guard let pidStr = try? String(contentsOfFile: pidPath(name), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return nil }
        return kill(pid, 0) == 0 ? pid : nil
    }

    static func isWDARunning(_ name: String) -> Bool { wdaPID(name) != nil }

    static func killWDA(_ name: String) {
        if let pid = wdaPID(name) {
            kill(pid, SIGTERM)
            usleep(Timeout.killGrace)
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        // Kill xcodebuild for THIS device only (by UDID)
        let devices = try? DeviceRegistry.load()
        if let dev = devices?[name] {
            shell("pkill -9 -f 'xcodebuild.*\(dev.udid)' 2>/dev/null")
        }
        sleep(1)
        try? FileManager.default.removeItem(atPath: pidPath(name))
    }

    // MARK: - Pre-flight & keychain

    /// Pre-flight checks before launching xcodebuild.
    /// `skipBundleCheck`: true for Build (the bundle doesn't exist yet).
    static func preflight(dev: Device, wdaDir: String, ddPath: String, skipBundleCheck: Bool = false) -> [String] {
        var issues: [String] = []

        // 1. Signing identity exists in keychain
        let identityCheck = shell("security find-identity -v -p codesigning 2>/dev/null")
        if !identityCheck.out.contains(dev.signingIdentity) {
            issues.append("FATAL: Signing identity '\(dev.signingIdentity)' not found in keychain.")
        }

        // 2. WDA project exists
        let projectPath = "\(wdaDir)/WebDriverAgent.xcodeproj"
        if !FileManager.default.fileExists(atPath: projectPath) {
            issues.append("FATAL: WDA project not found at \(projectPath)")
        }

        // 3. Test bundle exists (for test-without-building)
        if !skipBundleCheck {
            let testBundle = "\(ddPath)/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"
            if !FileManager.default.fileExists(atPath: testBundle) {
                issues.append("No test bundle. Run: idb wda build \(dev.udid)")
            }
        }

        // 4. Provisioning profile validity
        let profileDir = NSString(string: "~/Library/MobileDevice/Provisioning Profiles").expandingTildeInPath
        if FileManager.default.fileExists(atPath: profileDir) {
            let profiles = (try? FileManager.default.contentsOfDirectory(atPath: profileDir)) ?? []
            var hasValid = false
            for profile in profiles where profile.hasSuffix(".mobileprovision") {
                let decoded = shell("security cms -D -i \(profileDir.shellEscaped)/\(profile.shellEscaped) 2>/dev/null")
                if decoded.out.contains(dev.bundleId) {
                    if let range = decoded.out.range(of: "<key>ExpirationDate</key>"),
                       let dateStart = decoded.out.range(of: "<date>", range: range.upperBound..<decoded.out.endIndex),
                       let dateEnd = decoded.out.range(of: "</date>", range: dateStart.upperBound..<decoded.out.endIndex) {
                        let dateStr = String(decoded.out[dateStart.upperBound..<dateEnd.lowerBound])
                        let fmt = ISO8601DateFormatter()
                        if let expiry = fmt.date(from: dateStr) {
                            if expiry < Date() {
                                issues.append("Provisioning profile for '\(dev.bundleId)' expired. Rebuild: idb wda build <device> --clean")
                            } else {
                                hasValid = true
                            }
                        }
                    }
                }
            }
            if !hasValid && !issues.contains(where: { $0.contains("expired") }) {
                issues.append("No provisioning profile for '\(dev.bundleId)'. Run: idb wda build <device>")
            }
        }

        // 5. Keychain partition list — test-sign in a detached session (no /dev/tty)
        let testFile = "/tmp/idb-codesign-test-\(ProcessInfo.processInfo.processIdentifier)"
        shell("cp /usr/bin/true '\(testFile)'")
        let signTest = shellDetached("codesign -s '\(dev.signingIdentity)' --force '\(testFile)' 2>&1", timeout: 5)
        try? FileManager.default.removeItem(atPath: testFile)
        if signTest.code != 0 {
            let combined = signTest.out + " " + signTest.err
            if combined.contains("User interaction is not allowed")
                || combined.contains("errSecInternalComponent")
                || combined.contains("Timed out") {
                issues.append("KEYCHAIN: codesign cannot access '\(dev.signingIdentity)'. Partition list needs updating.")
            }
        }

        return issues
    }

    /// Offer to fix keychain access inline. Returns true if fixed.
    static func offerKeychainFix(dev: Device) -> Bool {
        print()
        print("codesign cannot access signing key '\(dev.signingIdentity)' without prompting.")
        print("Fix: grant codesign access to keys in login.keychain-db")
        print("  → security unlock-keychain + set-key-partition-list -S apple-tool:,apple:")
        print()

        guard let password = readPassword(prompt: "Enter your login (keychain) password: ") else {
            print("Cancelled.")
            return false
        }

        let kc = NSString(string: "~/Library/Keychains/login.keychain-db").expandingTildeInPath
        shell("security unlock-keychain -p '\(password)' '\(kc)' 2>/dev/null")
        let result = shell("security set-key-partition-list -S apple-tool:,apple: -s -k '\(password)' '\(kc)' 2>&1")

        if result.code == 0 {
            print("Keychain access granted.")
            return true
        } else if result.out.contains("authorizationCanceled") || result.err.contains("authorizationCanceled") {
            fputs("Wrong password.\n", stderr)
            return false
        } else {
            fputs("Failed: \(result.err.isEmpty ? result.out : result.err)\n", stderr)
            return false
        }
    }

    /// Run preflight, handle fatal/keychain/warning issues. Returns false if should abort.
    static func runPreflight(dev: Device, wdaDir: String, ddPath: String, skipBundleCheck: Bool = false) -> Bool {
        var issues = preflight(dev: dev, wdaDir: wdaDir, ddPath: ddPath, skipBundleCheck: skipBundleCheck)

        // Fatal errors
        let fatal = issues.filter { $0.hasPrefix("FATAL:") }
        for issue in fatal { fputs("ERROR: \(issue)\n", stderr) }
        if !fatal.isEmpty { return false }

        // Keychain — offer inline fix
        if issues.contains(where: { $0.hasPrefix("KEYCHAIN:") }) {
            if offerKeychainFix(dev: dev) {
                issues = preflight(dev: dev, wdaDir: wdaDir, ddPath: ddPath, skipBundleCheck: skipBundleCheck)
                if issues.contains(where: { $0.hasPrefix("KEYCHAIN:") }) {
                    fputs("ERROR: Keychain still not accessible.\n", stderr)
                    return false
                }
            } else {
                return false
            }
        }

        // Warnings
        for issue in issues where !issue.hasPrefix("FATAL:") && !issue.hasPrefix("KEYCHAIN:") {
            fputs("WARNING: \(issue)\n", stderr)
        }
        return true
    }

    // MARK: - Launch helpers

    /// xcodebuild arguments for test-without-building
    static func xcodebuildArgs(dev: Device, wdaDir: String, ddPath: String) -> [String] {
        [
            "test-without-building",
            "-project", "\(wdaDir)/WebDriverAgent.xcodeproj",
            "-scheme", "WebDriverAgentRunner",
            "-destination", "id=\(dev.udid)",
            "-destination-timeout", "\(Timeout.destination)",
            "-derivedDataPath", ddPath,
            "DEVELOPMENT_TEAM=\(dev.teamId)",
            "CODE_SIGN_IDENTITY=\(dev.signingIdentity)",
            "PRODUCT_BUNDLE_IDENTIFIER=\(dev.bundleId)",
            "USE_PORT=\(dev.port)",
        ]
    }

    /// Launch xcodebuild in a detached session (no controlling terminal).
    /// Output goes to the WDA log file. Returns the child PID.
    static func launchBackground(name: String, dev: Device, wdaDir: String) throws -> pid_t {
        let log = logPath(name)
        let logHandle: FileHandle = FileHandle(forWritingAtPath: log) ?? {
            FileManager.default.createFile(atPath: log, contents: nil)
            return FileHandle(forWritingAtPath: log)!
        }()
        logHandle.seekToEndOfFile()

        let devNull = open("/dev/null", O_RDONLY)
        defer { if devNull >= 0 { close(devNull) } }

        let args = xcodebuildArgs(dev: dev, wdaDir: wdaDir, ddPath: derivedDataPath(name))
        return try spawnDetached(
            executable: "/usr/bin/xcodebuild",
            arguments: args,
            stdoutFd: logHandle.fileDescriptor,
            stderrFd: logHandle.fileDescriptor,
            stdinFd: devNull >= 0 ? devNull : STDIN_FILENO
        )
    }

    /// Attempt to recover from device preparation errors.
    /// Cleans DDI cache and checks device state. Returns true if recovery was attempted.
    static func recoverDevice(dev: Device) -> Bool {
        print()
        print("Attempting device recovery...")

        // Clean cached developer disk images
        let ddClean = shell("xcrun devicectl manage ddis clean 2>&1")
        if ddClean.code == 0 {
            print("  Cleaned developer disk image cache.")
        }

        // Check device state
        let devList = shell("xcrun devicectl list devices 2>&1")
        let lines = devList.out.components(separatedBy: "\n")
        for line in lines {
            if line.contains("connected") {
                print("  Device state: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        // Check if device is locked (need CoreDevice UUID)
        if let coreUUID = findCoreDeviceUUID(udid: dev.udid) {
            let lockState = shell("xcrun devicectl device info lockState --device \(coreUUID) 2>&1")
            if lockState.out.contains("passcodeRequired: true") {
                print()
                print("  ⚠ Device may be locked. Unlock it and keep it unlocked during WDA startup.")
            }
        }

        print()
        print("Unplug and replug the device, then retry.")
        return true
    }

    /// Find CoreDevice UUID for a given UDID by matching devicectl output
    private static func findCoreDeviceUUID(udid: String) -> String? {
        // devicectl uses CoreDevice UUIDs, not UDID. We need to correlate via device name.
        // The enrolled device name should appear in devicectl list.
        let devList = shell("xcrun devicectl list devices 2>&1")
        for line in devList.out.components(separatedBy: "\n") {
            if line.contains("connected"),
               let uuid = line.components(separatedBy: " ").first(where: { $0.count == 36 && $0.contains("-") }) {
                return uuid
            }
        }
        return nil
    }

    static func waitForReady(name: String, dev: Device, timeout: Int = Timeout.readyWait) -> String? {
        let ip = extractHostFromLog(name) ?? "localhost"
        for _ in 0..<timeout {
            sleep(1)
            // Check log for ServerURL (background mode)
            if let log = try? String(contentsOfFile: logPath(name), encoding: .utf8),
               let range = log.range(of: "ServerURLHere->"),
               let endRange = log.range(of: "<-ServerURLHere", range: range.upperBound..<log.endIndex) {
                return String(log[range.upperBound..<endRange.lowerBound])
            }
            // Check HTTP endpoint (works for both modes)
            let check = shell("curl -s --connect-timeout 2 http://\(ip):\(dev.port)/status 2>/dev/null")
            if check.code == 0 && check.out.contains("ready") {
                return "http://\(ip):\(dev.port)"
            }
        }
        return nil
    }

    // MARK: - Start

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start WDA on a device (single run, tails log)")

        @Argument(help: "Device name")
        var device: String

        @Option(help: "WDA source directory")
        var wdaDir: String = IDBConfig.load().resolvedWdaDir

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(device)
            let ddPath = WDA.derivedDataPath(name)

            guard WDA.runPreflight(dev: dev, wdaDir: wdaDir, ddPath: ddPath) else {
                throw ExitCode.failure
            }

            WDA.killWDA(name)
            FileManager.default.createFile(atPath: WDA.logPath(name), contents: nil)

            print("Starting WDA on \(name) (port \(dev.port))...")

            // Launch in detached session — no /dev/tty, no rogue "Password:" prompts.
            // If something needs auth, it fails fast instead of hanging.
            let pid = try WDA.launchBackground(name: name, dev: dev, wdaDir: wdaDir)
            try "\(pid)".write(toFile: WDA.pidPath(name), atomically: true, encoding: .utf8)

            // Wait for ready while tailing the log
            if let url = WDA.waitForReady(name: name, dev: dev) {
                print("WDA ready at \(url)")
            } else {
                // Check if process already exited
                var status: Int32 = 0
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid {
                    let code = (status & 0x7f) == 0 ? Int32((status >> 8) & 0xff) : -1
                    fputs("xcodebuild exited with code \(code)\n", stderr)

                    // Show last lines of log for context
                    let logTail = shell("tail -20 \(WDA.logPath(name))")
                    if !logTail.out.isEmpty { fputs(logTail.out + "\n", stderr) }

                    // Check for known recoverable errors
                    if let log = try? String(contentsOfFile: WDA.logPath(name), encoding: .utf8) {
                        if log.contains("preparation errors") || log.contains("need to be unlocked") {
                            WDA.recoverDevice(dev: dev)
                        } else if log.contains("not trusted") || log.contains("not been explicitly trusted") {
                            fputs("\nDeveloper certificate not trusted on device.\n", stderr)
                            fputs("On the phone: Settings > General > VPN & Device Management\n", stderr)
                            fputs("  Tap the developer profile > Trust\n", stderr)
                            fputs("Then retry: idb wda start \(name)\n", stderr)
                        } else if log.contains("profile cannot be installed") {
                            fputs("\nProvisioning profile rejected by device.\n", stderr)
                            fputs("The device UDID may not be registered. Rebuild: idb wda build \(name) --clean --start\n", stderr)
                        } else if log.contains("Unable to Install") {
                            fputs("\nFailed to install WDA on device. Check the log: idb wda log \(name)\n", stderr)
                        }
                    }

                    try? FileManager.default.removeItem(atPath: WDA.pidPath(name))
                    throw ExitCode.failure
                }

                print("WDA started (PID \(pid)) but not responding yet. Check: idb wda log \(name)")
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
            let (name, dev) = try DeviceRegistry.resolve(device)
            let ddPath = derivedData ?? WDA.derivedDataPath(name)

            guard WDA.runPreflight(dev: dev, wdaDir: wdaDir, ddPath: ddPath, skipBundleCheck: true) else {
                throw ExitCode.failure
            }

            if clean {
                print("Cleaning derived data...")
                shell("rm -rf \(ddPath)")
            }

            print("Building WDA...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.currentDirectoryURL = URL(fileURLWithPath: wdaDir)
            process.arguments = [
                "build-for-testing",
                "-project", "WebDriverAgent.xcodeproj",
                "-scheme", "WebDriverAgentRunner",
                "-destination", "id=\(dev.udid)",
                "-allowProvisioningUpdates",
                "-derivedDataPath", ddPath,
            ]
            // stdin inherited — keychain/codesign prompts reach the user
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                print("BUILD FAILED (exit code \(process.terminationStatus))")
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
                    let build = try Build.parse(args)
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

            // Pre-flight
            let issues = WDA.preflight(dev: dev, wdaDir: wdaDir, ddPath: WDA.derivedDataPath(name))
            for issue in issues { fputs("[serve] WARNING: \(issue)\n", stderr) }
            if issues.contains(where: { $0.hasPrefix("KEYCHAIN:") }) {
                fputs("[serve] ERROR: Keychain access blocked. Fix interactively: idb wda start \(name)\n", stderr)
                throw ExitCode.failure
            }
            if issues.contains(where: { $0.hasPrefix("FATAL:") }) {
                throw ExitCode.failure
            }

            // Signal handling — use sigaction (not DispatchSource) since main thread blocks.
            // Store device name in global so the C handler can access it.
            _serveDeviceName = name
            signal(SIGTERM, _serveSignalHandler)
            signal(SIGINT, _serveSignalHandler)

            fputs("[serve] Starting WDA heartbeat for \(name) (port \(dev.port))\n", stderr)

            while failures < maxFailures {
                // Clear log
                FileManager.default.createFile(atPath: WDA.logPath(name), contents: nil)

                let pid: pid_t
                do {
                    pid = try WDA.launchBackground(name: name, dev: dev, wdaDir: wdaDir)
                } catch {
                    fputs("[serve] Failed to launch xcodebuild: \(error)\n", stderr)
                    failures += 1
                    sleep(Timeout.restartFailed)
                    continue
                }

                try? "\(pid)".write(toFile: WDA.pidPath(name), atomically: true, encoding: .utf8)

                // Wait for ready
                if let url = WDA.waitForReady(name: name, dev: dev) {
                    fputs("[serve] WDA ready at \(url)\n", stderr)
                    failures = 0
                } else {
                    fputs("[serve] WDA did not become ready within \(Timeout.readyWait)s\n", stderr)
                }

                // Wait for process to exit
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                let code = (status & 0x7f) == 0 ? Int32((status >> 8) & 0xff) : -1
                fputs("[serve] xcodebuild exited with code \(code)\n", stderr)

                try? FileManager.default.removeItem(atPath: WDA.pidPath(name))

                if code == 0 {
                    fputs("[serve] Clean exit, restarting in \(Timeout.restartClean)s...\n", stderr)
                    sleep(Timeout.restartClean)
                } else {
                    failures += 1
                    fputs("[serve] Failure \(failures)/\(maxFailures), restarting in \(Timeout.restartFailed)s...\n", stderr)
                    sleep(Timeout.restartFailed)
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

// MARK: - String extension for shell escaping

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
