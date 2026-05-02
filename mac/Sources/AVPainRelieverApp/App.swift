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
            // Hidden helper — observes appDelegate.shouldShowWelcome
            // and opens the welcome window when it flips true. Lives
            // inside MenuBarExtra so SwiftUI's openWindow environment
            // is available; menu items render fine alongside.
            WelcomeOpener(delegate: appDelegate)
        } label: {
            MenuLabelView(delegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)

        Window("Add Profile", id: addProfileWindowID) {
            AddProfileWindowContent(delegate: appDelegate)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: settingsWindowID) {
            SettingsView(delegate: appDelegate, settings: appDelegate.settings)
        }
        .windowResizability(.contentSize)

        Window("About AV Pain Reliever", id: aboutWindowID) {
            AboutView(delegate: appDelegate)
        }
        .windowResizability(.contentSize)

        Window("Welcome", id: welcomeWindowID) {
            WelcomeWindowContent(delegate: appDelegate)
        }
        .windowResizability(.contentSize)
    }
}

/// Invisible view inside the menu scene whose only job is to react to
/// `appDelegate.shouldShowWelcome` and open the welcome window via the
/// SwiftUI environment. Keeping the openWindow trigger inside a real
/// View is the cleanest way to bridge AppDelegate (no environment
/// access) → SwiftUI's openWindow API.
private struct WelcomeOpener: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: delegate.shouldShowWelcome) { _, show in
                if show {
                    openWindow(id: welcomeWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

private struct WelcomeWindowContent: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView(
            onAddProfile: {
                delegate.dismissWelcome()
                openWindow(id: addProfileWindowID)
                NSApp.activate(ignoringOtherApps: true)
                dismissWindow(id: welcomeWindowID)
            },
            onSkip: {
                delegate.dismissWelcome()
                dismissWindow(id: welcomeWindowID)
            }
        )
    }
}

private struct MenuLabelView: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        if delegate.atUnknownLocation {
            // The fallback profile name (typically "Laptop") would
            // imply "I'm undocked" — but the user is at a new dock
            // we don't recognise. Make that visible so they don't
            // assume the app is misbehaving.
            Image(systemName: "questionmark.circle")
            Text("New location")
        } else {
            Image(systemName: Theme.Symbol.appIcon)
            Text(delegate.currentProfileTitle)
        }
    }
}

private struct MenuContentView: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    /// One-shot easter egg: when the user holds Option while the menu
    /// opens (clicks anywhere then peeks the menu — close enough), an
    /// extra "stats" line shows up. The flag flips back to false when
    /// the menu closes (next reopen needs another modifier press),
    /// which the SwiftUI scene resets automatically by reconstructing
    /// the view.
    @State private var showStats: Bool = false

    var body: some View {
        if delegate.atUnknownLocation {
            // Headline replaces the misleading fallback profile name
            // ("Laptop") with an honest "New location detected" so
            // the user knows the engine is in fallback mode rather
            // than assuming they're somehow undocked.
            Text("New location detected")
                .font(.headline)
            Text("\(delegate.lastUnknownDevices.count) USB device\(delegate.lastUnknownDevices.count == 1 ? "" : "s") attached")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
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
        }
        if showStats || NSEvent.modifierFlags.contains(.option) {
            Text(StatsCopy.line(for: delegate.profileSwitchCount))
                .font(.caption)
                .foregroundStyle(Theme.Color.highlight)
        }
        Divider()

        if delegate.atUnknownLocation {
            // Visually prominent affordance — same destination as
            // Add Profile… below, but framed as the obvious next
            // step. The wizard pre-selects all currently-attached
            // devices anyway, so the user just needs to pick a name
            // and hit Save.
            Button {
                openWindow(id: addProfileWindowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Set Up This Location…", systemImage: "plus.circle.fill")
            }
            Divider()
        }

        if !delegate.availableProfiles.isEmpty {
            Menu("Switch to") {
                ForEach(delegate.availableProfiles, id: \.name) { profile in
                    profileMenuEntry(profile)
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

        Button("Settings…") {
            openWindow(id: settingsWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("About AV Pain Reliever") {
            openWindow(id: aboutWindowID)
            NSApp.activate(ignoringOtherApps: true)
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

    /// Each profile entry inside the "Switch to" submenu. Clicking
    /// switches immediately — single-click is the right interaction
    /// for "switch to". Edit/Delete live in Settings → Profiles.
    ///
    /// Layout: name on the top line, audio/camera summary on a
    /// smaller secondary line below. The active profile gets a
    /// checkmark in a fixed-width leading slot; inactive rows
    /// reserve the same slot empty so all names line up.
    ///
    /// No leading SF Symbol icon — the user only wanted iconography
    /// on top-level items, and the submenu was getting way too wide
    /// with both the icon and the inlined summary on the same row.
    /// Pulling the summary onto a sub-line + dropping the icon keeps
    /// the submenu tight.
    @ViewBuilder
    private func profileMenuEntry(_ profile: Profile) -> some View {
        let pretty = PrettyName.format(profile.name)
        let isActive = profile.name == delegate.activeProfileSlug
        Button {
            delegate.applyManually(profile)
        } label: {
            // SwiftUI's MenuBarExtra menu collapses Buttons to single-
            // line items by default. Embedding a newline in an
            // `AttributedString` is the reliable way to get a real
            // two-line entry — Text(AttributedString) bridges to
            // NSMenuItem.attributedTitle on macOS, which respects
            // newlines and per-run font/color attributes.
            Text(menuLabel(for: profile, pretty: pretty, isActive: isActive))
        }
    }

    /// Build the AttributedString shown in a "Switch to" submenu row.
    /// First line = profile name (semibold when active, with a
    /// leading checkmark in a fixed-width slot to keep names aligned
    /// across active + inactive rows). Second line = subtext with
    /// audio + camera in caption-size secondary color.
    private func menuLabel(
        for profile: Profile,
        pretty: String,
        isActive: Bool
    ) -> AttributedString {
        // Leading slot: checkmark on active, two spaces of width on
        // inactive rows so the names line up. Using "✓ " on active +
        // "   " on inactive keeps things simple in a plain string;
        // attributed-string columns can't be set in NSMenu titles.
        let prefix = isActive ? "✓ " : "   "
        var first = AttributedString(prefix + pretty)
        if isActive {
            first.font = .body.weight(.semibold)
        }
        guard
            delegate.showAudioCameraInMenu,
            let summary = profileSummary(profile)
        else {
            return first
        }
        // Subtext is indented to align under the name (past the
        // leading checkmark slot). Smaller font + secondary color
        // visually demotes it.
        var second = AttributedString("\n   " + summary)
        second.font = .caption
        second.foregroundColor = .secondary
        first.append(second)
        return first
    }

    /// One-line summary of the audio / camera the profile would
    /// apply. Plain bullet-separated names — no per-item emoji,
    /// since the row itself provides enough context (the user just
    /// drilled into "Switch to" so they know they're looking at AV
    /// behaviour). Returns nil for profiles with no apply fields.
    private func profileSummary(_ profile: Profile) -> String? {
        var parts: [String] = []
        if let mic = profile.audioInput { parts.append(mic) }
        if let out = profile.audioOutput, out != profile.audioInput {
            parts.append(out)
        }
        if let cam = profile.camera { parts.append(cam) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
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
            editing: deps.editing,
            onSaved: deps.onSaved
        ))
    }

    var body: some View {
        AddProfileView(viewModel: viewModel) {
            dismissWindow(id: addProfileWindowID)
        }
    }
}
