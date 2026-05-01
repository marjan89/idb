import XCTest
@testable import idb

final class ConfigTests: XCTestCase {

    func testDefaultsAreValid() {
        let config = IDBConfig.defaults
        XCTAssertEqual(config.defaultMjpegPort, 9100)
        XCTAssertEqual(config.defaultFastTouchPort, 9200)
        XCTAssertEqual(config.mirrorKeybindings.home, "esc")
        XCTAssertEqual(config.mirrorKeybindings.back, "opt+backspace")
        XCTAssertEqual(config.mirrorKeybindings.taskSwitcher, "tab")
    }

    func testTOMLRoundTrip() throws {
        let config = IDBConfig(
            wdaDir: "/test/wda",
            registryPath: "/test/devices.toml",
            logDir: "/test/logs",
            derivedDataDir: "/test/dd",
            defaultMjpegPort: 9101,
            defaultFastTouchPort: 9201,
            signingEmail: "test@example.com",
            mirrorKeybindings: MirrorKeybinding(home: "shift+h", back: "ctrl+b", taskSwitcher: "opt+tab")
        )

        let toml = IDBConfig.generateTOML(from: config)
        XCTAssertTrue(toml.contains("wda_dir = \"/test/wda\""))
        XCTAssertTrue(toml.contains("default_mjpeg_port = 9101"))
        XCTAssertTrue(toml.contains("home = \"shift+h\""))
        XCTAssertTrue(toml.contains("back = \"ctrl+b\""))
        XCTAssertTrue(toml.contains("task_switcher = \"opt+tab\""))
    }

    func testGeneratedTOMLContainsDocumentation() {
        let toml = IDBConfig.generateTOML(from: .defaults)
        XCTAssertTrue(toml.contains("# Path to WebDriverAgent source"))
        XCTAssertTrue(toml.contains("# Mirror keybindings"))
        XCTAssertTrue(toml.contains("# Examples:"))
        XCTAssertTrue(toml.contains("[mirror_keybindings]"))
    }
}
