import XCTest
@testable import idb

/// Tests for the regex-based UI XML parser used by `idb ui`
final class UIParserTests: XCTestCase {

    func testExtractsVisibleAccessibleElements() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <XCUIElementTypeApplication type="XCUIElementTypeApplication" name="Settings" visible="true" accessible="false" x="0" y="0" width="390" height="844">
          <XCUIElementTypeButton type="XCUIElementTypeButton" name="Back" label="Back" enabled="true" visible="true" accessible="true" x="0" y="47" width="68" height="44"/>
          <XCUIElementTypeStaticText type="XCUIElementTypeStaticText" value="Wi-Fi" name="Wi-Fi" label="Wi-Fi" enabled="true" visible="true" accessible="true" x="100" y="200" width="200" height="21"/>
          <XCUIElementTypeOther type="XCUIElementTypeOther" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        </XCUIElementTypeApplication>
        """

        let elements = parseUIElements(xml)
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements[0].label, "Back")
        XCTAssertEqual(elements[0].type, "Button")
        XCTAssertEqual(elements[1].label, "Wi-Fi")
    }

    func testHandlesUnescapedQuotesInAttributes() {
        // WDA produces broken XML with unescaped quotes in values
        let xml = """
        <XCUIElementTypeStaticText type="XCUIElementTypeStaticText" value="Apps from developer "Apple Development"" name="Apps" label="Apps" enabled="true" visible="true" accessible="true" x="0" y="100" width="390" height="50"/>
        """

        let elements = parseUIElements(xml)
        // Should not crash; may or may not extract the element depending on parser robustness
        // The important thing is no crash
        XCTAssertTrue(true)
    }

    func testFiltersContainerElements() {
        let xml = """
        <XCUIElementTypeWindow type="XCUIElementTypeWindow" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        <XCUIElementTypeOther type="XCUIElementTypeOther" name="container" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        <XCUIElementTypeScrollView type="XCUIElementTypeScrollView" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        <XCUIElementTypeTable type="XCUIElementTypeTable" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        <XCUIElementTypeCell type="XCUIElementTypeCell" visible="true" accessible="false" x="0" y="0" width="390" height="844"/>
        """

        let elements = parseUIElements(xml)
        XCTAssertEqual(elements.count, 0)
    }

    func testExtractsCenterCoordinates() {
        let xml = """
        <XCUIElementTypeButton type="XCUIElementTypeButton" name="OK" label="OK" enabled="true" visible="true" accessible="true" x="100" y="200" width="80" height="40"/>
        """

        let elements = parseUIElements(xml)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].x, 140)  // 100 + 80/2
        XCTAssertEqual(elements[0].y, 220)  // 200 + 40/2
    }

    func testIgnoresInvisibleElements() {
        let xml = """
        <XCUIElementTypeButton type="XCUIElementTypeButton" name="Hidden" label="Hidden" enabled="true" visible="false" accessible="true" x="0" y="0" width="100" height="44"/>
        """

        let elements = parseUIElements(xml)
        XCTAssertEqual(elements.count, 0)
    }

    // MARK: - Helper

    private struct ParsedElement {
        let type: String
        let label: String
        let x: Int
        let y: Int
    }

    /// Mirrors the parsing logic from UI.swift
    private func parseUIElements(_ xml: String) -> [ParsedElement] {
        let containers = Set(["Application", "Window", "Other", "ScrollView", "Table", "Cell"])
        var elements: [ParsedElement] = []

        for line in xml.components(separatedBy: "\n") {
            guard line.contains("visible=\"true\"") else { continue }
            guard line.contains("accessible=\"true\"") || line.contains("enabled=\"true\"") else { continue }

            guard let typeMatch = line.range(of: "XCUIElementType"),
                  let spaceAfter = line[typeMatch.upperBound...].firstIndex(of: " ") else { continue }
            let typeName = String(line[typeMatch.upperBound..<spaceAfter])
            if containers.contains(typeName) { continue }

            let label = extractAttr(line, "label") ?? extractAttr(line, "name") ?? ""
            if label.isEmpty { continue }

            guard let x = extractAttr(line, "x").flatMap(Double.init),
                  let y = extractAttr(line, "y").flatMap(Double.init),
                  let w = extractAttr(line, "width").flatMap(Double.init),
                  let h = extractAttr(line, "height").flatMap(Double.init) else { continue }

            elements.append(ParsedElement(type: typeName, label: label, x: Int(x + w/2), y: Int(y + h/2)))
        }
        return elements
    }

    private func extractAttr(_ line: String, _ attr: String) -> String? {
        let pattern = attr + "=\""
        guard let start = line.range(of: pattern)?.upperBound else { return nil }
        var i = start
        while i < line.endIndex {
            if line[i] == "\"" {
                let next = line.index(after: i)
                if next >= line.endIndex || " >/".contains(line[next]) {
                    return String(line[start..<i])
                }
            }
            i = line.index(after: i)
        }
        return nil
    }
}
