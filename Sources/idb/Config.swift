import Foundation
import TOMLKit

/// Mirror keybinding configuration
struct MirrorKeybinding: Equatable {
    var home: String
    var back: String
    var taskSwitcher: String

    static let defaults = MirrorKeybinding(
        home: "esc",
        back: "opt+backspace",
        taskSwitcher: "tab"
    )
}

/// idb configuration — loaded from ~/.config/idb/config.toml
struct IDBConfig: Equatable {
    var wdaDir: String
    var registryPath: String
    var logDir: String
    var derivedDataDir: String
    var defaultMjpegPort: Int
    var defaultFastTouchPort: Int
    var mirrorKeybindings: MirrorKeybinding

    static let configDir = NSString(string: "~/.config/idb").expandingTildeInPath
    static let configPath = NSString(string: "~/.config/idb/config.toml").expandingTildeInPath

    static let defaults = IDBConfig(
        wdaDir: "~/WebDriverAgent",
        registryPath: "~/.config/idb/devices.json",
        logDir: "/tmp",
        derivedDataDir: "/tmp",
        defaultMjpegPort: 9100,
        defaultFastTouchPort: 9200,
        mirrorKeybindings: .defaults
    )

    var keybindings: MirrorKeybinding { mirrorKeybindings }

    /// Resolve paths (expand ~)
    var resolvedWdaDir: String { NSString(string: wdaDir).expandingTildeInPath }
    var resolvedRegistryPath: String { NSString(string: registryPath).expandingTildeInPath }

    func wdaLogPath(_ name: String) -> String { "\(logDir)/wda-\(name).log" }
    func derivedDataPath(_ name: String) -> String { "\(derivedDataDir)/wda-build-\(name)" }

    // MARK: - Load

    static func load() -> IDBConfig {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8),
              let table = try? TOMLTable(string: contents) else {
            return defaults
        }
        return parse(table)
    }

    private static func parse(_ t: TOMLTable) -> IDBConfig {
        var config = defaults

        if let v = t["wda_dir"]?.string { config.wdaDir = v }
        if let v = t["registry_path"]?.string { config.registryPath = v }
        if let v = t["log_dir"]?.string { config.logDir = v }
        if let v = t["derived_data_dir"]?.string { config.derivedDataDir = v }
        if let v = t["default_mjpeg_port"]?.int { config.defaultMjpegPort = v }
        if let v = t["default_fast_touch_port"]?.int { config.defaultFastTouchPort = v }

        if let kb = t["mirror_keybindings"] as? TOMLTable {
            if let v = kb["home"]?.string { config.mirrorKeybindings.home = v }
            if let v = kb["back"]?.string { config.mirrorKeybindings.back = v }
            if let v = kb["task_switcher"]?.string { config.mirrorKeybindings.taskSwitcher = v }
        }

        return config
    }

    // MARK: - Save (for config set)

    func save() throws {
        try FileManager.default.createDirectory(atPath: IDBConfig.configDir, withIntermediateDirectories: true)
        try IDBConfig.generateTOML(from: self).write(toFile: IDBConfig.configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Generate annotated TOML

    static func generateTOML(from config: IDBConfig) -> String {
        """
        # idb — iOS Device Bridge configuration
        #
        # This file is loaded from ~/.config/idb/config.toml
        # All paths support ~ expansion.
        # Regenerate defaults with: idb config init --force

        # Path to WebDriverAgent source (your fork with FBFastTouchServer)
        # Used by: idb wda build
        wda_dir = "\(config.wdaDir)"

        # Path to device registry JSON
        # Contains enrolled devices with UDID, ports, signing config
        # Managed by: idb devices add/remove
        registry_path = "\(config.registryPath)"

        # Directory for WDA logs (wda-<device>.log, wda-<device>.pid)
        # Used by: idb wda start/serve/log
        log_dir = "\(config.logDir)"

        # Directory for xcodebuild derived data (wda-build-<device>/)
        # Used by: idb wda build
        # Must match between build and test-without-building
        derived_data_dir = "\(config.derivedDataDir)"

        # Default MJPEG stream port
        # WDA's MJPEG server port. Override per-device in devices.json (mjpeg_port)
        # Used by: idb mirror
        default_mjpeg_port = \(config.defaultMjpegPort)

        # Default FastTouch binary protocol port
        # FBFastTouchServer TCP port (~5ms touch input). Override per-device in devices.json (fast_touch_port)
        # Requires WDA fork with FBFastTouchServer. Falls back to HTTP if unavailable.
        # Used by: idb tap, idb swipe, idb mirror
        default_fast_touch_port = \(config.defaultFastTouchPort)

        # Mirror keybindings
        # Format: key alone or modifier+key
        # Keys: esc, tab, backspace, return, space, left, right, up, down, or any single character
        # Modifiers: opt (option/alt), shift, ctrl — combine with +
        # Examples: "esc", "opt+backspace", "shift+h", "ctrl+tab"
        [mirror_keybindings]
        home = "\(config.mirrorKeybindings.home)"
        back = "\(config.mirrorKeybindings.back)"
        task_switcher = "\(config.mirrorKeybindings.taskSwitcher)"
        """
    }
}
