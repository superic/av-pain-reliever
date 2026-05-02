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
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Color.chrome)
            Text("No profiles yet")
                .font(.headline)
            Text("Click Add Profile to capture the dock you're at right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
