import SwiftUI
import AppKit
import AVPainReliever

@main
struct AVPainRelieverApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Both `label` and `content` MUST be Views that take the
        // AppDelegate as @ObservedObject — referencing
        // appDelegate.currentProfileTitle directly inside the Scene's
        // body does NOT re-render the MenuBarExtra label when the
        // @Published property changes. View-level dependency tracking
        // is what makes the live update work.
        MenuBarExtra {
            MenuContentView(delegate: appDelegate)
        } label: {
            MenuLabelView(delegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuLabelView: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        Image(systemName: "pills.fill")
        Text(delegate.currentProfileTitle)
    }
}

private struct MenuContentView: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        Text(delegate.currentProfileTitle)
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
