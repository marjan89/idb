import XCTest
@testable import idb

final class KeybindingTests: XCTestCase {

    func testDefaultKeybindings() {
        let kb = MirrorKeybinding.defaults
        XCTAssertEqual(kb.home, "esc")
        XCTAssertEqual(kb.back, "opt+backspace")
        XCTAssertEqual(kb.taskSwitcher, "tab")
    }

    func testKeybindingStringParsing() {
        // Test the format is consistent
        let bindings = [
            "esc", "tab", "backspace", "return", "space",
            "opt+backspace", "shift+h", "ctrl+tab",
            "opt+shift+x", "a", "z",
        ]
        for b in bindings {
            let parts = b.lowercased().split(separator: "+").map(String.init)
            XCTAssertFalse(parts.isEmpty, "Binding '\(b)' should have at least one part")
            // Last part is the key
            let key = parts.last!
            XCTAssertFalse(key.isEmpty, "Key in '\(b)' should not be empty")
            // Modifiers are everything before the key
            let mods = Set(parts.dropLast())
            for m in mods {
                XCTAssertTrue(["opt", "option", "alt", "shift", "ctrl", "control"].contains(m),
                              "Unknown modifier '\(m)' in '\(b)'")
            }
        }
    }

    func testKeybindingEquality() {
        let a = MirrorKeybinding(home: "esc", back: "opt+backspace", taskSwitcher: "tab")
        let b = MirrorKeybinding.defaults
        XCTAssertEqual(a, b)

        let c = MirrorKeybinding(home: "shift+h", back: "opt+backspace", taskSwitcher: "tab")
        XCTAssertNotEqual(a, c)
    }
}
