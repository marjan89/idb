import ArgumentParser
import Foundation

struct WDA: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage WebDriverAgent lifecycle",
        subcommands: [Start.self, Stop.self, Status.self, Build.self, Log_.self]
    )

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start WDA on a device")

        @Argument(help: "Device name")
        var device: String

        func run() throws {
            let result = shell("bash ~/.claude/daemons/wda/wda-ctl.sh start \(device)", timeout: 60)
            print(result.out)
            if !result.err.isEmpty { print(result.err) }
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop WDA on a device")

        @Argument(help: "Device name")
        var device: String

        func run() throws {
            let result = shell("bash ~/.claude/daemons/wda/wda-ctl.sh stop \(device)")
            print(result.out)
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check WDA status")

        @Argument(help: "Device name (optional)")
        var device: String?

        func run() throws {
            let arg = device ?? ""
            let result = shell("bash ~/.claude/daemons/wda/wda-ctl.sh status \(arg)")
            print(result.out)
        }
    }

    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build WDA fork and deploy to device")

        @Argument(help: "Device name")
        var device: String

        @Flag(help: "Clean build (remove derived data first)")
        var clean = false

        func run() throws {
            let (name, dev) = try DeviceRegistry.resolve(device)

            if clean {
                print("Cleaning derived data...")
                shell("rm -rf /tmp/wda-build-\(name)")
            }

            print("Building WDA fork...")
            let buildResult = shell("""
                ~/.claude/bin/nosandbox bash -c "cd /Users/Shared/projects/device-tools/WebDriverAgent && \
                xcodebuild build-for-testing \
                    -project WebDriverAgent.xcodeproj \
                    -scheme WebDriverAgentRunner \
                    -destination 'generic/platform=iOS' \
                    -allowProvisioningUpdates \
                    -derivedDataPath /tmp/wda-build-\(name)"
                """, timeout: 300)

            if buildResult.code != 0 {
                print("BUILD FAILED")
                // Extract errors
                for line in buildResult.out.split(separator: "\n") where line.contains("error:") {
                    print("  \(line)")
                }
                throw ExitCode.failure
            }
            print("BUILD SUCCEEDED")

            print("Starting WDA on \(name)...")
            let startResult = shell("bash ~/.claude/daemons/wda/wda-ctl.sh start \(name)", timeout: 60)
            print(startResult.out)
        }
    }

    struct Log_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "log", abstract: "Tail WDA log for a device")

        @Argument(help: "Device name")
        var device: String

        @Option(name: .shortAndLong, help: "Number of lines")
        var lines: Int = 50

        func run() throws {
            let result = shell("tail -\(lines) /tmp/wda-\(device).log")
            print(result.out)
        }
    }
}
