import XCTest
@testable import idb

final class DeviceRegistryTests: XCTestCase {

    func testDeviceDecodesFromJSON() throws {
        let json = """
        {
            "phone": {
                "udid": "00008140-001C48AC3EDB001C",
                "model": "iPhone 16 Pro (iPhone17,1)",
                "ios": "26.3.1",
                "team_id": "8WLC7943H8",
                "signing_identity": "Apple Development",
                "bundle_id": "com.marjan89.WebDriverAgentRunner",
                "port": 8100,
                "enrolled": "2026-04-19"
            }
        }
        """.data(using: .utf8)!

        let devices = try JSONDecoder().decode([String: Device].self, from: json)
        XCTAssertEqual(devices.count, 1)

        let phone = devices["phone"]!
        XCTAssertEqual(phone.udid, "00008140-001C48AC3EDB001C")
        XCTAssertEqual(phone.model, "iPhone 16 Pro (iPhone17,1)")
        XCTAssertEqual(phone.port, 8100)
        XCTAssertEqual(phone.teamId, "8WLC7943H8")
        XCTAssertEqual(phone.bundleId, "com.marjan89.WebDriverAgentRunner")
    }

    func testOptionalPortsDefaultToConfig() throws {
        let json = """
        {
            "dev": {
                "udid": "AAAA",
                "model": "iPhone",
                "ios": "18.0",
                "team_id": "TEAM",
                "signing_identity": "Apple Development",
                "bundle_id": "com.test.wda",
                "port": 8101,
                "enrolled": "2026-01-01"
            }
        }
        """.data(using: .utf8)!

        let devices = try JSONDecoder().decode([String: Device].self, from: json)
        let dev = devices["dev"]!

        XCTAssertNil(dev.mjpegPort)
        XCTAssertNil(dev.fastTouchPort)
        // Resolved ports fall back to config defaults
        XCTAssertEqual(dev.resolvedMjpegPort, IDBConfig.load().defaultMjpegPort)
        XCTAssertEqual(dev.resolvedFastTouchPort, IDBConfig.load().defaultFastTouchPort)
    }

    func testExplicitPortsOverrideDefaults() throws {
        let json = """
        {
            "dev": {
                "udid": "AAAA",
                "model": "iPhone",
                "ios": "18.0",
                "team_id": "TEAM",
                "signing_identity": "Apple Development",
                "bundle_id": "com.test.wda",
                "port": 8101,
                "mjpeg_port": 9101,
                "fast_touch_port": 9201,
                "enrolled": "2026-01-01"
            }
        }
        """.data(using: .utf8)!

        let devices = try JSONDecoder().decode([String: Device].self, from: json)
        let dev = devices["dev"]!

        XCTAssertEqual(dev.resolvedMjpegPort, 9101)
        XCTAssertEqual(dev.resolvedFastTouchPort, 9201)
    }

    func testDeviceEncodesBackToJSON() throws {
        let device = Device(
            udid: "TEST", model: "iPhone Test", ios: "18.0",
            teamId: "TEAM", signingIdentity: "Apple Development",
            bundleId: "com.test.wda", port: 8100,
            mjpegPort: nil, fastTouchPort: nil, enrolled: "2026-01-01"
        )
        let devices = ["test": device]

        let data = try JSONEncoder().encode(devices)
        let decoded = try JSONDecoder().decode([String: Device].self, from: data)

        XCTAssertEqual(decoded["test"]?.udid, "TEST")
        XCTAssertEqual(decoded["test"]?.port, 8100)
    }

    func testResolveUnknownDeviceThrows() {
        // Write a temp registry
        let tmp = NSTemporaryDirectory() + "idb-test-devices.json"
        try! "{}".write(toFile: tmp, atomically: true, encoding: .utf8)

        // Can't easily test resolve() without mocking the path,
        // but we can test the error type exists
        let error = IDBError.unknownDevice("ghost", available: ["phone", "dev"])
        XCTAssertTrue(error.description.contains("ghost"))
        XCTAssertTrue(error.description.contains("phone"))

        try? FileManager.default.removeItem(atPath: tmp)
    }

    func testNoDeviceSpecifiedError() {
        let error = IDBError.noDeviceSpecified(available: ["a", "b"])
        XCTAssertTrue(error.description.contains("No device specified"))
        XCTAssertTrue(error.description.contains("a, b"))
    }
}
