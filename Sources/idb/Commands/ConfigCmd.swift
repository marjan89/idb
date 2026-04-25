import ArgumentParser
import Foundation

struct Config_: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage idb configuration",
        subcommands: [Init_.self, Show.self, Set_.self, Path.self]
    )

    struct Init_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "init", abstract: "Create config with defaults")

        @Flag(help: "Overwrite existing config")
        var force = false

        func run() throws {
            if FileManager.default.fileExists(atPath: IDBConfig.configPath) && !force {
                print("Config already exists at \(IDBConfig.configPath)")
                print("Use --force to overwrite")
                return
            }
            try IDBConfig.defaults.save()
            print("Created \(IDBConfig.configPath)")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show current config")

        func run() throws {
            let config = IDBConfig.load()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            print(String(data: data, encoding: .utf8) ?? "")
            print("\nPath: \(IDBConfig.configPath)")
        }
    }

    struct Set_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a config value")

        @Argument(help: "Key (wdaDir, registryPath, logDir, derivedDataDir, defaultMjpegPort, defaultFastTouchPort)")
        var key: String

        @Argument(help: "Value")
        var value: String

        func run() throws {
            var config = IDBConfig.load()
            switch key {
            case "wdaDir": config.wdaDir = value
            case "registryPath": config.registryPath = value
            case "logDir": config.logDir = value
            case "derivedDataDir": config.derivedDataDir = value
            case "defaultMjpegPort":
                guard let v = Int(value) else { print("Invalid port"); throw ExitCode.failure }
                config.defaultMjpegPort = v
            case "defaultFastTouchPort":
                guard let v = Int(value) else { print("Invalid port"); throw ExitCode.failure }
                config.defaultFastTouchPort = v
            default:
                print("Unknown key: \(key)")
                print("Valid keys: wdaDir, registryPath, logDir, derivedDataDir, defaultMjpegPort, defaultFastTouchPort")
                throw ExitCode.failure
            }
            try config.save()
            print("Set \(key) = \(value)")
        }
    }

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print config file path")
        func run() { print(IDBConfig.configPath) }
    }
}
