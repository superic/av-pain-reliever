import Foundation
import AVPainReliever

/// Snapshot of an audio device for the wizard's pickers.
/// Re-exported here so the SwiftUI views don't have to import the
/// engine module for a name.
typealias AudioDevice = AudioDeviceSummary

/// Owns the editable state of the Add-Profile form and runs the save
/// action. Created with the data sources it needs (USB watcher,
/// audio controller, target file URL, post-save reload callback)
/// rather than reaching into `AppDelegate` itself, which keeps the
/// view model independently testable later.
@MainActor
final class AddProfileViewModel: ObservableObject {
    // MARK: - Form state

    @Published var name: String = ""
    @Published var audioInput: String? = nil
    @Published var audioOutput: String? = nil

    /// Currently-attached USB devices the user can include in the
    /// fingerprint. Refreshed on demand from the watcher.
    @Published private(set) var attachedDevices: [NamedUSBDevice] = []
    /// Subset of `attachedDevices.id` the user has checked.
    @Published var selectedDeviceIDs: Set<USBDevice> = []

    /// Audio devices CoreAudio sees right now.
    @Published private(set) var audioDevices: [AudioDevice] = []

    /// User-facing error from the most recent save attempt. Cleared
    /// when the user edits any field.
    @Published var lastError: String? = nil

    /// True while the save operation is in flight (so the form can
    /// disable buttons / show a spinner).
    @Published private(set) var isSaving = false

    /// True after a successful save — the host view watches this and
    /// closes the window.
    @Published private(set) var didSave = false

    // MARK: - Dependencies

    private let watcher: USBWatcher
    private let audioController: AudioController
    private let configURL: URL
    private let onSaved: () -> Void

    init(
        watcher: USBWatcher,
        audioController: AudioController,
        configURL: URL,
        onSaved: @escaping () -> Void
    ) {
        self.watcher = watcher
        self.audioController = audioController
        self.configURL = configURL
        self.onSaved = onSaved
        refresh()
    }

    // MARK: - Live data

    /// Re-pull the USB and audio device lists. Called on init and
    /// from the "Refresh" button — useful when the user docks
    /// mid-wizard.
    func refresh() {
        let named = watcher.currentDevicesNamed()
        attachedDevices = named
        // Default selection: every currently-attached device,
        // including unnamed hub legs. Capturing more is the safer
        // default — the user knows what's plugged in right now and
        // can uncheck peripherals (keyboards/mice/phones) that
        // aren't location-specific. Including hub legs is fine
        // because they're stable parts of the dock.
        if selectedDeviceIDs.isEmpty {
            selectedDeviceIDs = Set(named.map(\.device))
        }
        audioDevices = audioController.availableDevices()
    }

    var inputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsInput)
    }

    var outputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsOutput)
    }

    // MARK: - Validation

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNameValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return trimmedName.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// True only while the save operation is in flight. The button
    /// itself is otherwise always clickable so the user gets a clear
    /// inline error if the name is invalid (the previous design
    /// disabled the button silently and gave no feedback when a name
    /// like "Home Office" with a space failed validation).
    var canSave: Bool {
        !isSaving
    }

    /// Inline hint shown under the Name field. Empty when nothing's
    /// typed yet (the placeholder + caption do that work); explicit
    /// red error when the typed name has invalid characters; nil
    /// otherwise.
    var nameValidationHint: String? {
        guard !name.isEmpty else { return nil }
        guard isNameValid else {
            return "Use only letters, numbers, hyphens, or underscores."
        }
        return nil
    }

    // MARK: - Save

    func save() {
        guard !isSaving else { return }
        guard isNameValid else {
            lastError = "Profile name can only contain letters, numbers, hyphens, or underscores."
            return
        }
        isSaving = true
        lastError = nil
        defer { isSaving = false }

        let fingerprint = attachedDevices
            .filter { selectedDeviceIDs.contains($0.device) }
            .map(\.device)
        let deviceNames: [USBDevice: String?] = Dictionary(
            uniqueKeysWithValues: attachedDevices
                .filter { selectedDeviceIDs.contains($0.device) }
                .map { ($0.device, $0.name) }
        )

        let profile = Profile(
            name: trimmedName,
            fingerprint: fingerprint,
            audioInput: audioInput,
            audioOutput: audioOutput
        )

        do {
            try ProfileWriter().append(
                profile: profile,
                deviceNames: deviceNames,
                to: configURL,
                startingHeader: AddProfileViewModel.starterHeader
            )
            didSave = true
            onSaved()
        } catch let ProfileWriteError.duplicateProfile(name) {
            lastError = "A profile named \"\(name)\" already exists. Choose a different name."
        } catch let ProfileWriteError.invalidName(name) {
            lastError = "\"\(name)\" isn't a valid profile name. Use letters, numbers, hyphens, or underscores."
        } catch let ProfileWriteError.writeFailed(reason) {
            lastError = "Couldn't save: \(reason)"
        } catch {
            lastError = "Couldn't save: \(error)"
        }
    }

    /// Header banner used when the writer creates a fresh
    /// `profiles.toml` (e.g., the user clicks Add Profile before the
    /// app has bootstrapped a starter file). Mirrors the AppDelegate
    /// starter content so the file looks consistent regardless of
    /// who created it.
    static let starterHeader = """
    # AV Pain Reliever — profile config.
    # Each [profiles.<name>] section defines a location.
    # See https://github.com/superic/av-pain-reliever for the schema.

    """
}
