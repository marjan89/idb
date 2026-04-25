import Foundation

/// idb configuration — loaded from ~/.config/idb/config.json
struct IDBConfig: Codable {
    var wdaDir: String
    var registryPath: String
    var logDir: String
    var derivedDataDir: String
    var defaultMjpegPort: Int
    var defaultFastTouchPort: Int

    static let configDir = NSString(string: "~/.config/idb").expandingTildeInPath
    static let configPath = NSString(string: "~/.config/idb/config.json").expandingTildeInPath

    static let defaults = IDBConfig(
        wdaDir: "~/WebDriverAgent",
        registryPath: "~/.config/idb/devices.json",
        logDir: "/tmp",
        derivedDataDir: "/tmp",
        defaultMjpegPort: 9100,
        defaultFastTouchPort: 9200
    )

    /// Load config — falls back to defaults for missing keys
    static func load() -> IDBConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(IDBConfig.self, from: data) else {
            return defaults
        }
        return config
    }

    func save() throws {
        let dir = IDBConfig.configDir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: IDBConfig.configPath))
    }

    /// Resolve paths (expand ~)
    var resolvedWdaDir: String { NSString(string: wdaDir).expandingTildeInPath }
    var resolvedRegistryPath: String { NSString(string: registryPath).expandingTildeInPath }

    func wdaLogPath(_ name: String) -> String { "\(logDir)/wda-\(name).log" }
    func derivedDataPath(_ name: String) -> String { "\(derivedDataDir)/wda-build-\(name)" }
}
