import ArgumentParser
import Foundation

struct UI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Dump UI element tree (XCUI source XML)")

    @OptionGroup var deviceOpt: DeviceOption

    @Flag(name: .long, help: "Output raw XML instead of compact format")
    var raw = false

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        let xml = try wda.source()

        if raw {
            print(xml)
        } else {
            // Compact: extract interactive elements with labels and coordinates
            printCompact(xml)
        }
    }

    private func printCompact(_ xml: String) {
        // Regex-based extraction — WDA XML has unescaped quotes that break NSXMLParser
        let containers = Set(["Application", "Window", "Other", "ScrollView", "Table", "Cell"])
        var elements: [(type: String, label: String, x: Double, y: Double)]  = []

        for line in xml.components(separatedBy: "\n") {
            guard line.contains("visible=\"true\"") else { continue }
            guard line.contains("accessible=\"true\"") || line.contains("enabled=\"true\"") else { continue }

            // Extract type
            guard let typeMatch = line.range(of: "XCUIElementType"),
                  let spaceAfter = line[typeMatch.upperBound...].firstIndex(of: " ") else { continue }
            let typeName = String(line[typeMatch.upperBound..<spaceAfter])
            if containers.contains(typeName) { continue }

            // Extract label or name
            let label = extractAttr(line, "label") ?? extractAttr(line, "name") ?? ""
            if label.isEmpty { continue }

            // Extract coords
            guard let x = extractAttr(line, "x").flatMap(Double.init),
                  let y = extractAttr(line, "y").flatMap(Double.init),
                  let w = extractAttr(line, "width").flatMap(Double.init),
                  let h = extractAttr(line, "height").flatMap(Double.init) else { continue }

            elements.append((typeName, label, x + w/2, y + h/2))
        }

        if elements.isEmpty {
            print("(no interactive elements found)")
            return
        }

        let fmt = { (t: String, l: String, c: String, e: String) in
            "\(t.padding(toLength: 12, withPad: " ", startingAt: 0))\(l.padding(toLength: 32, withPad: " ", startingAt: 0))\(c)"
        }
        print(fmt("TYPE", "LABEL", "COORDS", ""))
        print(String(repeating: "-", count: 60))
        for el in elements {
            let coords = "(\(Int(el.x)),\(Int(el.y)))"
            print(fmt(el.type, String(el.label.prefix(30)), coords, ""))
        }
    }

    /// Extract an XML attribute value — handles unescaped quotes by finding the last matching pattern
    private func extractAttr(_ line: String, _ attr: String) -> String? {
        let pattern = attr + "=\""
        guard let start = line.range(of: pattern)?.upperBound else { return nil }
        // Find the next quote that's followed by a space or > or /
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
