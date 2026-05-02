import SwiftUI
import AppKit
import AVPainReliever

/// Stable identifier used to open and dismiss the wizard window.
let addProfileWindowID = "add-profile"

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

        Window("Add Profile", id: addProfileWindowID) {
            AddProfileWindowContent(delegate: appDelegate)
        }
        .windowResizability(.contentSize)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(delegate.currentProfileTitle)
            .font(.headline)
        if let camera = delegate.currentCameraDisplay {
            // Reminder for Zoom/Slack/Teams users: the system
            // preferred camera is set, but those apps don't follow
            // it. This line tells the user what name to pick if
            // they need to update the in-app camera selection.
            Text("Camera: \(camera)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Divider()

        if !delegate.availableProfiles.isEmpty {
            Menu("Switch to") {
                ForEach(delegate.availableProfiles, id: \.name) { profile in
                    Button {
                        delegate.applyManually(profile)
                    } label: {
                        let isActive = profile.name == delegate.activeProfileSlug
                        if isActive {
                            Label(PrettyName.format(profile.name), systemImage: "checkmark")
                        } else {
                            Text(PrettyName.format(profile.name))
                        }
                    }
                }
            }
            Divider()
        }

        Button("Add Profile…") {
            openWindow(id: addProfileWindowID)
            // Accessory apps (LSUIElement-style) don't auto-activate
            // when a window opens — the new window appears behind
            // whatever was focused. Force-activate so the wizard is
            // immediately usable without an extra click.
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("n")

        Button("Re-evaluate Now") {
            delegate.reevaluate()
        }
        .keyboardShortcut("r")
        Button("Reload Config") {
            delegate.reloadConfig()
        }
        .keyboardShortcut("l")

        Divider()

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

/// Wrapper view inside the Add-Profile Window scene. Owns the
/// `AddProfileViewModel` as a `@StateObject` so its lifetime matches
/// the window's, even though SwiftUI may rebuild the surrounding view
/// when the AppDelegate publishes elsewhere.
private struct AddProfileWindowContent: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var viewModel: AddProfileViewModel

    init(delegate: AppDelegate) {
        self.delegate = delegate
        let deps = delegate.addProfileDependencies()
        _viewModel = StateObject(wrappedValue: AddProfileViewModel(
            watcher: deps.watcher,
            audioController: deps.audioController,
            cameraController: deps.cameraController,
            configURL: deps.configURL,
            onSaved: deps.onSaved
        ))
    }

    var body: some View {
        AddProfileView(viewModel: viewModel) {
            dismissWindow(id: addProfileWindowID)
        }
    }
}
