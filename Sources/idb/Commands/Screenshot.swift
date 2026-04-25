import ArgumentParser
import Foundation

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Take a screenshot and save to file")

    @OptionGroup var deviceOpt: DeviceOption

    @Argument(help: "Output file path (default: screenshot.png)")
    var output: String = "screenshot.png"

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        let data = try wda.screenshot()
        try data.write(to: URL(fileURLWithPath: output))
        print("Saved \(data.count) bytes to \(output)")
    }
}
