import ArgumentParser
import Foundation

struct UI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Dump UI element tree (XCUI source XML)")

    @OptionGroup var deviceOpt: DeviceOption

    @Flag(name: .long, help: "Output raw XML instead of compact format")
    var raw = false

    func run() throws {
        let (_, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev)
        let xml = try wda.source()

        if raw {
            print(xml)
        } else {
            // Compact: extract interactive elements with labels and coordinates
            printCompact(xml)
        }
    }

    private func printCompact(_ xml: String) {
        // Parse XML and extract tappable elements
        guard let data = xml.data(using: .utf8) else {
            print(xml)
            return
        }

        let parser = UIElementParser(data: data)
        let elements = parser.parse()

        if elements.isEmpty {
            print("(no interactive elements found)")
            return
        }

        print(String(format: "%-8s %-30s %-15s %s", "TYPE", "LABEL", "COORDS", "ENABLED"))
        print(String(repeating: "-", count: 70))
        for el in elements {
            print(String(format: "%-8s %-30s (%3.0f,%3.0f)       %s",
                         el.type, String(el.label.prefix(30)),
                         el.x, el.y, el.enabled ? "yes" : "no"))
        }
    }
}

// Simple XML parser for XCUI source
private struct UIElement {
    let type: String
    let label: String
    let x: Double
    let y: Double
    let enabled: Bool
}

private class UIElementParser: NSObject, XMLParserDelegate {
    let data: Data
    var elements: [UIElement] = []

    init(data: Data) {
        self.data = data
    }

    func parse() -> [UIElement] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return elements
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        // Skip containers
        let containers = ["XCUIElementTypeApplication", "XCUIElementTypeWindow",
                          "XCUIElementTypeOther", "XCUIElementTypeScrollView",
                          "XCUIElementTypeTable", "XCUIElementTypeCell"]
        let shortName = elementName.replacingOccurrences(of: "XCUIElementType", with: "")
        if containers.contains(elementName) { return }

        let label = attributes["label"] ?? attributes["name"] ?? ""
        let enabled = attributes["enabled"] == "true"
        let visible = attributes["visible"] == "true"

        guard visible, !label.isEmpty || enabled else { return }

        // Parse frame "{{x, y}, {w, h}}"
        if let frame = attributes["frame"] ?? attributes["rect"] {
            let nums = frame.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .filter { !$0.isEmpty }
                .compactMap { Double($0) }
            if nums.count >= 4 {
                let cx = nums[0] + nums[2] / 2
                let cy = nums[1] + nums[3] / 2
                elements.append(UIElement(type: shortName, label: label, x: cx, y: cy, enabled: enabled))
            }
        }
    }
}
