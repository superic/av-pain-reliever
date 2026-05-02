import SwiftUI
import AppKit
import AVPainReliever

let settingsWindowID = "settings-window"

/// The Settings scene has two tabs: General (toggles + slider) and
/// Profiles (list with edit/delete). Deliberately *no* mention of
/// Hammerspoon, OBS, or any other third-party tool — the app must read
/// as its own product.
struct SettingsView: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ProfilesSettingsTab(delegate: delegate)
                .tabItem {
                    Label("Profiles", systemImage: "list.bullet.rectangle")
                }
        }
        .frame(width: 480, height: 380)
        .padding(.top, 8)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch AV Pain Reliever at login", isOn: $settings.launchAtLogin)
                Toggle("Send notifications when profiles change", isOn: $settings.notificationsEnabled)
                Toggle("Show audio + camera details in menu", isOn: $settings.showAudioCameraInMenu)
            } header: {
                Label("Behavior", systemImage: "wand.and.stars")
                    .foregroundStyle(Theme.Color.primary)
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
                    .foregroundStyle(Theme.Color.primary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Text(VersionInfo.short)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 6)
        }
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
                    openWindow(id: addProfileWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Color.primary)
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
                    .foregroundStyle(Theme.Color.primary)
                Text("Plug in your dock or peripherals, then capture them as a profile. AV Pain Reliever will switch your audio + camera defaults whenever you dock there again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            Button {
                openWindow(id: addProfileWindowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Add Profile", systemImage: "plus")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Color.primary)
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
            Image(systemName: ProfileIcon.symbol(for: profile.name))
                .font(.title3)
                .foregroundStyle(isActive ? Theme.Color.primary : Theme.Color.chrome)
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
                            .background(Theme.Color.success.opacity(0.85), in: Capsule())
                    }
                }
                if let summary = summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var summary: String? {
        var parts: [String] = []
        if let mic = profile.audioInput { parts.append("🎙 \(mic)") }
        if let out = profile.audioOutput { parts.append("🔈 \(out)") }
        if let cam = profile.camera { parts.append("📷 \(cam)") }
        if profile.fingerprint.isEmpty {
            parts.append("Always matches when undocked")
        } else {
            let count = profile.fingerprint.count
            parts.append("\(count) USB device\(count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  •  ")
    }
}
