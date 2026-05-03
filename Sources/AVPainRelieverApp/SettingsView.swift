import SwiftUI
import AppKit
import AVPainReliever

/// Stable identifiers for the Settings tabs. Bound to the TabView's
/// selection so callers (e.g. the menu's "Edit Profiles…" item) can
/// pre-select a tab before opening the window. Tab choice persists
/// across opens via the AppDelegate's @Published property.
enum SettingsTab: Hashable {
    case general
    case profiles
}

/// The Settings scene has two tabs: General (toggles + slider) and
/// Profiles (list with edit/delete). Deliberately *no* mention of
/// Hammerspoon, OBS, or any other third-party tool — the app must read
/// as its own product.
///
/// Hosted inside SwiftUI's dedicated `Settings { ... }` scene rather
/// than a generic `Window` scene so the TabView gets the System-
/// Settings-style toolbar tab chrome (white-container segmented
/// control). A generic Window scene rendered the bare-tabs-in-
/// titlebar variant under LSUIElement, which read as styling drift.
struct SettingsView: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView(selection: $delegate.settingsTab) {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ProfilesSettingsTab(delegate: delegate)
                .tabItem {
                    Label("Profiles", systemImage: "list.bullet.rectangle")
                }
                .tag(SettingsTab.profiles)
        }
        .frame(width: 480, height: 380)
        .centeredOnScreen()
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Send notifications when profiles change", isOn: $settings.notificationsEnabled)
                Toggle("Show current profile in the menu bar", isOn: $settings.showProfileNameInMenuBar)
            } header: {
                Label("Behavior", systemImage: "wand.and.stars")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Debounce window")
                        Spacer()
                        Text(String(format: "%.1f s", settings.debounceInterval))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.debounceInterval, in: 0.5...5.0, step: 0.1)
                    Text("Wait this long after USB activity before re-evaluating. Higher values handle slow docks; lower values feel snappier. Default: 1.5 s.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Detection", systemImage: "cable.connector")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

/// Small helper to render the version string consistently across
/// About, Settings, and any future window that needs it. Falls back
/// to "dev build" when the binary isn't bundled (the SPM build
/// path).
enum VersionInfo {
    static var short: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (shortVersion, build) {
        case let (s?, b?): return "AV Pain Reliever \(s) (\(b))"
        case let (s?, nil): return "AV Pain Reliever \(s)"
        default: return "AV Pain Reliever — dev build"
        }
    }
}

private struct ProfilesSettingsTab: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if delegate.availableProfiles.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(delegate.availableProfiles, id: \.name) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.name == delegate.activeProfileSlug,
                            onEdit: {
                                delegate.beginEditingProfile(profile)
                                openWindow(id: addProfileWindowID)
                                NSApp.activate(ignoringOtherApps: true)
                            },
                            onDelete: { delegate.requestDelete(profile) }
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button {
                    delegate.beginAddingProfile()
                    openWindow(id: addProfileWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(delegate.availableProfiles.count) profile\(delegate.availableProfiles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            // Hero icon — uses the app icon (rather than a generic
            // tray) so the empty state still feels like the
            // product, not a generic-iOS-style placeholder.
            Image(nsImage: AppIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            VStack(spacing: 4) {
                Text("Set up your first location")
                    .font(.title3.weight(.semibold))
                Text("Plug in your dock or peripherals, then capture them as a profile. AV Pain Reliever will switch your audio + camera defaults whenever you dock there again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            Button {
                delegate.beginAddingProfile()
                openWindow(id: addProfileWindowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Add Profile", systemImage: "plus")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Leading icon mirrors the Switch To submenu: profile's
            // user-picked icon when set, slug-driven auto-mapper
            // fallback when not.
            Image(systemName: ProfileIcon.effectiveSymbol(
                for: profile.name,
                override: profile.icon
            ))
                .font(.title3)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(PrettyName.format(profile.name))
                        .font(.body.weight(.medium))
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }
                if let summary = summaryText {
                    summary
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            // Icon-only inline actions — keeps the profile name +
            // summary in the visual centre of each row instead of
            // fighting two text-bearing buttons for space. Sizing
            // and accessibility are handled inside `IconButton` so
            // both renders match dimensions regardless of which
            // SF Symbol each carries.
            IconButton(
                systemImage: "pencil",
                accessibilityLabel: "Edit profile",
                action: onEdit
            )
            IconButton(
                systemImage: "trash",
                accessibilityLabel: "Delete profile",
                role: .destructive,
                action: onDelete
            )
        }
        .padding(.vertical, 4)
    }

    /// Caption-line under each profile name. Renders inline SF Symbols
    /// (mic / speaker / camera) instead of the emoji prefixes the
    /// earlier draft used — emoji at caption size read as cheap and
    /// clash with the otherwise-monochrome SF Symbol vocabulary used
    /// throughout the menu and wizard. `Text + Text(Image:)`
    /// concatenation keeps it a single flowing line that wraps and
    /// respects `.lineLimit(2)` cleanly.
    private var summaryText: Text? {
        var parts: [Text] = []
        if let mic = profile.audioInput {
            parts.append(Text(Image(systemName: "mic")) + Text(" \(mic)"))
        }
        if let out = profile.audioOutput {
            parts.append(Text(Image(systemName: "speaker.wave.2")) + Text(" \(out)"))
        }
        if let cam = profile.camera {
            parts.append(Text(Image(systemName: "camera")) + Text(" \(cam)"))
        }
        if profile.fingerprint.isEmpty {
            parts.append(Text("Always matches when undocked"))
        } else {
            let count = profile.fingerprint.count
            parts.append(Text("\(count) USB device\(count == 1 ? "" : "s")"))
        }
        guard !parts.isEmpty else { return nil }
        let separator = Text("  •  ")
        return parts.dropFirst().reduce(parts[0]) { acc, next in
            acc + separator + next
        }
    }
}
