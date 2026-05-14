import ArgumentParser
import Foundation

struct Elements: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find UI elements via WDA queries (no full-tree snapshot)")

    @OptionGroup var deviceOpt: DeviceOption

    @Option(name: .long, help: "Class chain query (e.g. '**/XCUIElementTypeButton[`label == \"Links\"`]')")
    var classChain: String?

    @Option(name: .long, help: "Element type (e.g. Button, Cell, StaticText)")
    var type: String?

    @Option(name: .long, help: "Filter by label (exact match, combined with --type)")
    var label: String?

    @Option(name: .long, help: "Filter by label substring (combined with --type)")
    var labelContains: String?

    @Option(name: .long, help: "NSPredicate string query")
    var predicate: String?

    @Flag(name: .long, help: "Output raw JSON response")
    var raw = false

    func validate() throws {
        let strategies = [classChain != nil, type != nil, predicate != nil]
        if strategies.allSatisfy({ !$0 }) {
            throw ValidationError("Provide --class-chain, --type, or --predicate")
        }
        if classChain != nil && (type != nil || predicate != nil) {
            throw ValidationError("--class-chain cannot be combined with --type or --predicate")
        }
        if predicate != nil && type != nil {
            throw ValidationError("--predicate cannot be combined with --type")
        }
        if (label != nil || labelContains != nil) && type == nil {
            throw ValidationError("--label/--label-contains requires --type")
        }
        if label != nil && labelContains != nil {
            throw ValidationError("--label and --label-contains are mutually exclusive")
        }
    }

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)

        let (strategy, value) = buildQuery()
        let elements = try wda.findElements(using: strategy, value: value)

        if raw {
            let data = try JSONSerialization.data(withJSONObject: elements, options: .prettyPrinted)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        printCompact(elements)
    }

    private func buildQuery() -> (strategy: String, value: String) {
        if let chain = classChain {
            return ("class chain", chain)
        }

        if let pred = predicate {
            return ("predicate string", pred)
        }

        let xcType = "XCUIElementType\(type!)"
        if let exact = label {
            return ("class chain", "**/\(xcType)[`label == \"\(exact)\"`]")
        }
        if let sub = labelContains {
            return ("class chain", "**/\(xcType)[`label CONTAINS \"\(sub)\"`]")
        }
        return ("class chain", "**/\(xcType)")
    }

    private func printCompact(_ elements: [[String: Any]]) {
        if elements.isEmpty {
            print("(no matching elements)")
            return
        }

        let fmt = { (t: String, l: String, c: String) in
            "\(t.padding(toLength: 14, withPad: " ", startingAt: 0))\(l.padding(toLength: 34, withPad: " ", startingAt: 0))\(c)"
        }
        print(fmt("TYPE", "LABEL", "CENTER"))
        print(String(repeating: "-", count: 64))

        for el in elements {
            let elType = (el["type"] as? String ?? "?")
                .replacingOccurrences(of: "XCUIElementType", with: "")
            let elLabel = el["label"] as? String ?? ""
            var cx = 0, cy = 0
            if let rect = el["rect"] as? [String: Any],
               let x = (rect["x"] as? NSNumber)?.intValue,
               let y = (rect["y"] as? NSNumber)?.intValue,
               let w = (rect["width"] as? NSNumber)?.intValue,
               let h = (rect["height"] as? NSNumber)?.intValue {
                cx = x + w / 2
                cy = y + h / 2
            }
            print(fmt(elType, String(elLabel.prefix(32)), "(\(cx),\(cy))"))
        }
    }
}
