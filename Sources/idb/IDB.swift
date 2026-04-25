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
            Screenshot.self,
            App.self,
            Syslog.self,
            Mirror_.self,
            Doctor.self,
        ]
    )
}
