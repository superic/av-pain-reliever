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
    case camera
    case stats
}

private extension View {
    /// Shared chrome for every Settings tab body — `.formStyle(.grouped)`
    /// + 8 pt padding around the Form's rounded card. Apply to the
    /// `Form` at the root of each tab's body so the gray section
    /// cards line up consistently against the window edges. Camera,
    /// General, and Stats use this; Profiles has its own layout
    /// (no Form) and stays bespoke for now.
    ///
    /// One place to change the convention. If we ever want to bump
    /// the padding to 12 or swap to a different formStyle, edit
    /// here and every tab follows.
    func settingsTabContent() -> some View {
        self
            .formStyle(.grouped)
            .padding(8)
    }
}

/// The Settings scene has four tabs: General (toggles + slider),
/// Profiles (list with edit/delete), Camera (virtual camera
/// install/enable + status), and Stats (opt-in local usage
/// counters). Deliberately *no* mention of Hammerspoon, OBS, or
/// any other third-party tool — the app must read as its own
/// product.
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

            CameraSettingsTab(
                settings: settings,
                activator: delegate.virtualCameraActivator
            )
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(SettingsTab.camera)

            StatsSettingsTab(settings: settings, delegate: delegate)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
                .tag(SettingsTab.stats)
        }
        .frame(width: 480, height: 380)
        .centeredOnScreen()
    }
}

/// Camera tab — opt-in toggle for the virtual camera that lets
/// Zoom / Slack / Teams pick up the active profile's source camera
/// (those apps ignore the system's `userPreferredCamera`).
/// Installing requires user approval through System Settings, so
/// the section explains what's about to happen and surfaces a
/// status row that mirrors the activator's state machine.
private struct CameraSettingsTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var activator: VirtualCameraActivator

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable AV Pain Reliever as a virtual camera",
                    isOn: $settings.virtualCameraEnabled
                )
                .disabled(activator.isEnvOverride)

                statusRow

                if case .requiresRelaunch = activator.state {
                    Button("Restart AV Pain Reliever") {
                        activator.relaunch()
                    }
                    .controlSize(.small)
                } else if showsApprovalAffordance {
                    Button("Open Login Items & Extensions") {
                        openExtensionsSettings()
                    }
                    .controlSize(.small)
                }

                // Form footer hint rendered as the last row in the
                // section body — `footer:` is constrained on
                // macOS 14, locked convention per project memory.
                Text(explanationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("Virtual camera", systemImage: "camera.metering.center.weighted")
            }
        }
        .settingsTabContent()
    }

    /// Live status row — colored dot + human-readable label that
    /// repaints on every activator state transition.
    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.callout)
            Spacer()
            if activator.isEnvOverride {
                Text("Debug override")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch activator.state {
        case .on: return .green
        case .activating, .needsApproval: return .orange
        case .failed, .requiresRelaunch: return .red
        case .off: return .secondary
        }
    }

    private var statusLabel: String {
        switch activator.state {
        case .off: return "Off"
        case .activating: return "Activating…"
        case .needsApproval: return "Approval needed"
        case .on: return "Active"
        case .failed(let msg): return "Failed: \(msg)"
        case .requiresRelaunch: return "Restart required"
        }
    }

    private var showsApprovalAffordance: Bool {
        switch activator.state {
        case .needsApproval, .failed: return true
        default: return false
        }
    }

    private var explanationText: String {
        if activator.isEnvOverride {
            return "The AVPR_ACTIVATE_VIRTUAL_CAMERA debug override is active for this launch. The toggle is locked until you relaunch without it."
        }
        switch activator.state {
        case .off:
            return "When on, Zoom, Slack, Teams, and other apps that have their own camera picker can choose 'AV Pain Reliever' to follow the active profile's source camera."
        case .activating:
            return "Submitting the activation request to macOS. If a system prompt appears, approve it in System Settings."
        case .needsApproval:
            return "macOS is waiting for you to approve the Camera Extension. Open System Settings → General → Login Items & Extensions → Camera Extensions."
        case .on:
            return "Pick 'AV Pain Reliever' in Zoom, Slack, or any app's camera picker. The active profile's source camera flows through it."
        case .failed:
            return "Activation didn't complete. Open System Settings → General → Login Items & Extensions to check the extension's state, then toggle this off and on to retry."
        case .requiresRelaunch:
            return "macOS holds the virtual camera in a stale state after toggling off and back on inside one session. Restart AV Pain Reliever to re-enable it cleanly."
        }
    }

    private func openExtensionsSettings() {
        // Apple's documented x-apple URL for the extensions page.
        // Falls back to the general System Settings app on older
        // macOS versions where the deep link isn't recognized —
        // still gets the user one click closer than nothing.
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")!
        NSWorkspace.shared.open(url)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var showingMenuBarIconPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Send notifications when profiles change", isOn: $settings.notificationsEnabled)
                Toggle("Show current profile in the menu bar", isOn: $settings.showProfileNameInMenuBar)
                Toggle("Show current profile icon in the menu bar", isOn: $settings.showProfileIconInMenuBar)
                // Picker row + a conditional caption explaining why
                // the picker greys out when the profile-icon toggle
                // above is on. Caption shows only in the disabled
                // state so the cause-and-effect is unambiguous: the
                // moment you flip the toggle, the explanation
                // appears next to the disabled control.
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Menu bar icon") {
                        Button {
                            showingMenuBarIconPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: settings.menuBarIconSymbol)
                                    .font(.body)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $showingMenuBarIconPicker, arrowEdge: .bottom) {
                            MenuBarSymbolPicker(
                                selection: $settings.menuBarIconSymbol,
                                onPick: { showingMenuBarIconPicker = false }
                            )
                        }
                    }
                    if settings.showProfileIconInMenuBar {
                        Text("Active profile icon overrides this above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.showProfileIconInMenuBar)
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

            Section {
                Toggle("Receive experimental updates", isOn: $settings.experimentalUpdates)
                Text("Opt in to early-access builds. Experimental releases include unfinished features (the virtual camera in v0.2.x) and may be less stable than the regular release line. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }
        }
        .settingsTabContent()
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

/// Stats tab — local usage tracking behind an opt-in toggle. Ships
/// off; the Tracking section collapses to just the toggle + helper
/// text on a fresh install, avoiding "what is this stuff?" friction
/// before the user has chosen to keep notes. Renamed from "Advanced"
/// to avoid colliding with the menu bar's existing Advanced submenu
/// — and the tab only houses stats today, so the on-the-nose name
/// reads better.
private struct StatsSettingsTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var delegate: AppDelegate
    @State private var resetConfirmationVisible = false

    var body: some View {
        Form {
            Section {
                Toggle("Track usage stats locally", isOn: $settings.statsTrackingEnabled)
                Text("Counts only — what profile switched, when, and how often. No meeting content, no durations, no telemetry. Stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.statsTrackingEnabled {
                    statsRows
                }
            } header: {
                Label("Tracking", systemImage: "switch.2")
            }

            if hasAnyStatsValue {
                Section {
                    Button(role: .destructive) {
                        resetConfirmationVisible = true
                    } label: {
                        Text("Reset stats…")
                    }
                } header: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .settingsTabContent()
        .alert(
            "Reset all usage stats?",
            isPresented: $resetConfirmationVisible
        ) {
            Button("Reset", role: .destructive) {
                settings.resetStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes every counter and date on this screen. Your profiles and other settings are untouched.")
        }
    }

    /// True iff any stats value is non-zero / non-empty. Used to show
    /// the Reset section even when tracking is off, so a user who
    /// disables tracking after collecting some history can still wipe.
    private var hasAnyStatsValue: Bool {
        settings.profileSwitchCount > 0
            || !settings.perProfileCounts.isEmpty
            || settings.lastSwitchSlug != nil
            || settings.manualOverrideCount > 0
            || settings.activeDaysCount > 0
            || !settings.uniqueDeviceFingerprints.isEmpty
            || settings.statsStartDate != nil
    }

    @ViewBuilder
    private var statsRows: some View {
        LabeledContent("Tracking since", value: trackingSinceString)
        LabeledContent("Auto-switches", value: "\(settings.profileSwitchCount)")
        if let lastLine = lastSwitchedString {
            LabeledContent("Last switched", value: lastLine)
        }
        if let (topSlug, topCount) = topProfile {
            LabeledContent("Most-used location", value: "\(PrettyName.format(topSlug)) (\(topCount))")
            ForEach(otherProfiles, id: \.0) { slug, count in
                LabeledContent(PrettyName.format(slug), value: "\(count)")
            }
        }
        LabeledContent("Manual overrides", value: "\(settings.manualOverrideCount)")
        LabeledContent("Current streak", value: streakString(settings.currentStreakDays))
        LabeledContent("Longest streak", value: streakString(settings.longestStreakDays))
        LabeledContent("Active days", value: "\(settings.activeDaysCount)")
        LabeledContent("Unique USB devices recognized", value: "\(settings.uniqueDevicesSeenCount)")
    }

    /// "Today" on day 0, "Yesterday" on day 1, "N days ago" beyond.
    /// Renders nil-state as "Not yet" so a freshly-enabled user
    /// doesn't see "0 days ago" before any data has been collected.
    private var trackingSinceString: String {
        guard let start = settings.statsStartDate else { return "Not yet" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday (1 day)"
        default: return "\(days) days ago"
        }
    }

    private var lastSwitchedString: String? {
        guard let date = settings.lastSwitchDate, let slug = settings.lastSwitchSlug
        else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "\(relative) → \(PrettyName.format(slug))"
    }

    /// Highest entry in `perProfileCounts`; nil when the dictionary
    /// is empty.
    private var topProfile: (String, Int)? {
        settings.perProfileCounts.max { $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }

    /// All entries except the top one, sorted by descending count.
    /// The top one is rendered as the "Most-used location" highlight
    /// just above; this list adds the rankings without duplicating
    /// the leader.
    private var otherProfiles: [(String, Int)] {
        guard let top = topProfile else { return [] }
        return settings.perProfileCounts
            .filter { $0.key != top.0 }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    private func streakString(_ days: Int) -> String {
        switch days {
        case 0: return "—"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }
}
