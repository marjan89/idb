import ArgumentParser
import Foundation

struct Copy_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "Copy iPhone clipboard to Mac clipboard")

    @OptionGroup var deviceOpt: DeviceOption

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)
        let text = try wda.getPasteboard()
        if text.isEmpty {
            print("(clipboard empty)")
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
            let pipe = Pipe()
            task.standardInput = pipe
            try task.run()
            pipe.fileHandleForWriting.write(Data(text.utf8))
            pipe.fileHandleForWriting.closeFile()
            task.waitUntilExit()
            print(text)
        }
    }
}

struct Paste: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Paste Mac clipboard to iPhone clipboard")

    @OptionGroup var deviceOpt: DeviceOption

    @Flag(help: "Also type the text into the focused field")
    var type = false

    func run() throws {
        let (name, dev) = try DeviceRegistry.resolve(deviceOpt.device)
        let wda = try connectWDA(dev, name: name)

        let result = shell("pbpaste")
        let text = result.out
        if text.isEmpty {
            print("(Mac clipboard empty)")
            return
        }

        try wda.setPasteboard(text)
        print("Pasted to device: \(String(text.prefix(80)))\(text.count > 80 ? "..." : "")")

        if type {
            try wda.typeKeys(text.map { String($0) })
        }
    }
}
