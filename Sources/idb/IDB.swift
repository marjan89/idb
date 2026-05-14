import ArgumentParser

@main
struct IDB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "idb",
        abstract: "iOS Device Bridge — unified CLI for iOS device control",
        version: "0.1.0",
        subcommands: [
            Devices.self,
            WDA.self,
            Tap.self,
            Swipe.self,
            Type_.self,
            Button.self,
            UI.self,
            Elements.self,
            Screenshot.self,
            App.self,
            Syslog.self,
            Home.self,
            Back.self,
            Scroll_.self,
            Copy_.self,
            Paste.self,
            Mirror_.self,
            Doctor.self,
            Config_.self,
        ]
    )
}
