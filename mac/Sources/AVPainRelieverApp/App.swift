import SwiftUI
import AppKit
import AVPainReliever

@main
struct AVPainRelieverApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            // Status item title — pretty-cased current profile name,
            // updated live by AppDelegate via @Published.
            Image(systemName: "pills.fill")
            Text(appDelegate.currentProfileTitle)
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuContent: some View {
        Text(appDelegate.currentProfileTitle)
            .font(.headline)
        Divider()

        Button("Open OBS") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/OBS.app"))
        }
        Button("Reveal Log in Console") {
            // Surface the os.Logger stream by opening Console.app.
            // The log stream filter for our subsystem can be applied
            // there manually; deep-linking to a filtered view requires
            // a private URL scheme we don't want to bake in.
            let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
            NSWorkspace.shared.openApplication(at: consoleURL, configuration: .init())
        }

        Divider()

        Button("Quit AV Pain Reliever") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
