import ArgumentParser
import Foundation

struct Config_: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage idb configuration",
        subcommands: [Init_.self, Show.self, Set_.self, Path.self]
    )

    struct Init_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "init", abstract: "Create config with defaults and documentation")

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
            print(IDBConfig.generateTOML(from: config))
            print("\n# Path: \(IDBConfig.configPath)")
        }
    }

    struct Set_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a config value")

        @Argument(help: "Key (use dotted path for nested: mirror_keybindings.home)")
        var key: String

        @Argument(help: "Value")
        var value: String

        func run() throws {
            var config = IDBConfig.load()
            switch key {
            case "wda_dir": config.wdaDir = value
            case "registry_path": config.registryPath = value
            case "log_dir": config.logDir = value
            case "derived_data_dir": config.derivedDataDir = value
            case "default_mjpeg_port":
                guard let v = Int(value) else { print("Invalid port"); throw ExitCode.failure }
                config.defaultMjpegPort = v
            case "default_fast_touch_port":
                guard let v = Int(value) else { print("Invalid port"); throw ExitCode.failure }
                config.defaultFastTouchPort = v
            case "mirror_keybindings.home":
                config.mirrorKeybindings.home = value
            case "mirror_keybindings.back":
                config.mirrorKeybindings.back = value
            case "mirror_keybindings.task_switcher":
                config.mirrorKeybindings.taskSwitcher = value
            default:
                print("Unknown key: \(key)")
                print("""
                Valid keys:
                  wda_dir, registry_path, log_dir, derived_data_dir,
                  default_mjpeg_port, default_fast_touch_port,
                  mirror_keybindings.home, mirror_keybindings.back,
                  mirror_keybindings.task_switcher
                """)
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
