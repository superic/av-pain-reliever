import Foundation
import AVPainReliever

/// Snapshot of an audio device for the wizard's pickers.
/// Re-exported here so the SwiftUI views don't have to import the
/// engine module for a name.
typealias AudioDevice = AudioDeviceSummary
typealias CameraDevice = CameraSummary

/// State the view shows when the user tries to save a profile name
/// that already exists. The view's alert renders three buttons that
/// route to `confirmReplace` / `confirmSaveAsNew` / `cancelCollision`.
struct PendingCollision: Identifiable, Equatable {
    let id = UUID()
    /// Pretty-cased existing name, e.g. "Home Office".
    let existingPrettyName: String
    /// Slug we'd save under if user picks "Save as new".
    let newSlug: String
    /// Pretty-cased version of `newSlug`, e.g. "Home Office 2".
    var newPrettyName: String { PrettyName.format(newSlug) }
    /// Slug of the existing profile we'd replace.
    let existingSlug: String
}

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
    @Published var camera: String? = nil

    /// Devices shown in the wizard's USB-fingerprint list. Union of
    /// (currently-attached devices) and (devices the editing profile
    /// saved that aren't currently attached). Sorted by display name
    /// with disconnected entries pushed to the bottom so the active
    /// hardware is visually grouped at the top.
    @Published private(set) var attachedDevices: [NamedUSBDevice] = []
    /// Subset of `attachedDevices` IDs the user has checked.
    @Published var selectedDeviceIDs: Set<USBDevice> = []
    /// Devices in `attachedDevices` that came from the editing
    /// profile's fingerprint but are NOT currently plugged in. The
    /// view shows these with a yellow "Not connected" badge and
    /// keeps their names from the saved TOML so the user can still
    /// see what their profile is actually doing while away from the
    /// location.
    @Published private(set) var disconnectedDeviceIDs: Set<USBDevice> = []

    /// Audio devices CoreAudio sees right now.
    @Published private(set) var audioDevices: [AudioDevice] = []
    /// Cameras AVFoundation sees right now.
    @Published private(set) var cameras: [CameraDevice] = []

    /// User-facing error from the most recent save attempt. Cleared
    /// when the user edits any field.
    @Published var lastError: String? = nil

    /// True while the save operation is in flight (so the form can
    /// disable buttons / show a spinner).
    @Published private(set) var isSaving = false

    /// True after a successful save — the host view watches this and
    /// closes the window.
    @Published private(set) var didSave = false

    /// Set when the user attempts to save a profile name that
    /// conflicts with an existing one. The view shows a dialog
    /// asking whether to update the existing profile (with the
    /// current selections) or save as a new one with a numbered
    /// suffix.
    @Published var pendingCollision: PendingCollision? = nil

    // MARK: - Dependencies

    private let watcher: USBWatcher
    private let audioController: AudioController
    private let cameraController: CameraController
    private let configURL: URL
    private let onSaved: () -> Void
    private let editingSlug: String?

    /// Saved fingerprint from the profile being edited — preserved
    /// verbatim across `refresh()` so saved-but-disconnected devices
    /// keep showing up even after the live watcher snapshot updates.
    /// Empty when adding a new profile.
    private var savedFingerprint: [USBDevice] = []
    /// Display names for `savedFingerprint` entries from the source
    /// TOML. Used by the wizard to show meaningful labels even when
    /// the device isn't currently attached (in which case the live
    /// watcher snapshot wouldn't carry a name).
    private var savedFingerprintNames: [USBDevice: String] = [:]

    init(
        watcher: USBWatcher,
        audioController: AudioController,
        cameraController: CameraController,
        configURL: URL,
        editing: Profile? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.watcher = watcher
        self.audioController = audioController
        self.cameraController = cameraController
        self.configURL = configURL
        self.onSaved = onSaved
        self.editingSlug = editing?.name

        if let profile = editing {
            // Pre-populate from the existing profile so the user can
            // adjust the bits they care about. Pretty-cased name keeps
            // the textfield human-readable; we re-slugify on save.
            self.name = PrettyName.format(profile.name)
            self.audioInput = profile.audioInput
            self.audioOutput = profile.audioOutput
            self.camera = profile.camera
            self.savedFingerprint = profile.fingerprint
            self.savedFingerprintNames = profile.fingerprintNames
            // Default to keeping every saved device ticked. The user
            // can untick to remove from the fingerprint. refresh()
            // will then merge the live watcher snapshot with these
            // saved entries so devices that aren't currently attached
            // still appear (with a "Not connected" hint), instead of
            // silently disappearing.
            self.selectedDeviceIDs = Set(profile.fingerprint)
        }

        refresh()
    }

    // MARK: - Live data

    /// Re-pull the USB and audio device lists. Called on init and
    /// from the "Refresh" button — useful when the user docks
    /// mid-wizard. Audio defaults are pre-populated from the system's
    /// current default input/output the *first* time refresh runs;
    /// subsequent refreshes leave the user's manual selection alone.
    func refresh() {
        let liveSnapshot = watcher.currentDevicesNamed()
        let liveIDs = Set(liveSnapshot.map(\.device))

        // Saved-but-disconnected: any device in the editing profile's
        // fingerprint that isn't currently plugged in. Synthesize a
        // NamedUSBDevice from the saved fingerprint + the per-device
        // names the loader preserved, so the wizard can render them
        // with a readable label and a "Not connected" badge instead
        // of dropping them from the form.
        let disconnected: [NamedUSBDevice] = savedFingerprint
            .filter { !liveIDs.contains($0) }
            .map { device in
                NamedUSBDevice(
                    device: device,
                    name: savedFingerprintNames[device],
                    vendorName: nil
                )
            }
        let disconnectedIDs = Set(disconnected.map(\.device))

        // Live devices first (sorted as the watcher returned them),
        // then disconnected entries pushed to the bottom by name so
        // the active hardware stays grouped at the top of the list.
        attachedDevices = liveSnapshot + disconnected.sorted {
            $0.displayName < $1.displayName
        }
        disconnectedDeviceIDs = disconnectedIDs

        // Default selection: every currently-attached device,
        // including unnamed hub legs. Capturing more is the safer
        // default — the user knows what's plugged in right now and
        // can uncheck peripherals (keyboards/mice/phones) that
        // aren't location-specific. Including hub legs is fine
        // because they're stable parts of the dock. (Skipped when
        // editing — the saved fingerprint pre-populates selection.)
        if selectedDeviceIDs.isEmpty {
            selectedDeviceIDs = Set(liveSnapshot.map(\.device))
        }
        audioDevices = audioController.availableDevices()
        cameras = cameraController.availableCameras()

        // Pre-select whatever the system currently uses so the user
        // doesn't have to repeat audio/camera choices they already
        // made manually before opening the wizard. Only sets an
        // unset field; never overwrites a deliberate user pick.
        let defaults = audioController.currentDefaults()
        if audioInput == nil { audioInput = defaults.inputName }
        if audioOutput == nil { audioOutput = defaults.outputName }
        if camera == nil { camera = cameraController.currentPreferredName() }

        // First-launch convenience: if the user hasn't typed a name and
        // we recognize a docked-setup signature in the attached
        // devices, pre-fill a sensible suggestion. Only when adding —
        // editing keeps the existing name. The user can always rename.
        if name.isEmpty && editingSlug == nil {
            let deviceNames = liveSnapshot.compactMap { $0.name }
            if let suggested = ProfileIcon.suggestedName(forDeviceNames: deviceNames) {
                name = PrettyName.format(suggested)
            }
        }
    }

    var inputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsInput)
    }

    var outputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsOutput)
    }

    // MARK: - Name handling
    //
    // The wizard accepts any human-friendly name ("Home Office",
    // "Mom's House", "Café 2"). Internally we slugify on save; the
    // user never sees the slug. Display layers (menu bar, alerts)
    // route the slug back through PrettyName.format.

    /// Pretty-cased preview of what the user will see after saving.
    /// Empty when the user hasn't typed anything yet.
    var prettyPreview: String {
        let slug = Slug.format(name)
        return slug.isEmpty ? "" : PrettyName.format(slug)
    }

    /// Slug used to drive the wizard's live profile-icon preview.
    /// Falls back to a generic placeholder slug while the field is
    /// empty so the icon isn't a flickering question-mark.
    var previewSlug: String {
        let slug = Slug.format(name)
        return slug.isEmpty ? "_placeholder_" : slug
    }

    /// True only while the save operation is in flight. Otherwise
    /// the button is always clickable; validation runs at click time
    /// with a clear inline error so the user knows why save was
    /// rejected (vs. silently disabling and leaving them stuck).
    var canSave: Bool {
        !isSaving && !didSave
    }

    /// True when the wizard was opened to edit an existing profile
    /// rather than to create a new one. Drives copy + button labels.
    var editingExisting: Bool {
        editingSlug != nil
    }

    // MARK: - Save

    func save() {
        guard !isSaving else { return }
        let slug = Slug.format(name)
        guard !slug.isEmpty else {
            lastError = "Please enter a profile name."
            return
        }
        let writer = ProfileWriter()

        // Editing a profile and keeping the same slug → replace in
        // place. Editing a profile but renaming it to a slug that
        // collides with another existing profile → fall through to
        // the collision dialog.
        if let editing = editingSlug, slug == editing {
            performSave(slug: slug, mode: .replace)
            return
        }

        if writer.profileExists(named: slug, in: configURL) {
            // Don't write yet — surface the collision dialog and let
            // the user pick (update existing / save as new / cancel).
            pendingCollision = PendingCollision(
                existingPrettyName: PrettyName.format(slug),
                newSlug: writer.nextAvailableName(base: slug, in: configURL),
                existingSlug: slug
            )
            return
        }
        performSave(slug: slug, mode: .append)
    }

    /// User picked "Update existing" in the collision dialog — replace
    /// the prior profile's section with our current selections.
    func confirmReplace() {
        guard let collision = pendingCollision else { return }
        pendingCollision = nil
        performSave(slug: collision.existingSlug, mode: .replace)
    }

    /// User picked "Save as new" in the collision dialog — append
    /// under the auto-suggested suffixed slug.
    func confirmSaveAsNew() {
        guard let collision = pendingCollision else { return }
        pendingCollision = nil
        performSave(slug: collision.newSlug, mode: .append)
    }

    /// User picked "Cancel" — drop the collision state and let them
    /// edit the form.
    func cancelCollision() {
        pendingCollision = nil
    }

    // MARK: - Implementation

    private enum SaveMode {
        case append
        case replace
    }

    private func performSave(slug: String, mode: SaveMode) {
        isSaving = true
        lastError = nil
        defer { isSaving = false }

        // Build the fingerprint from EVERY ticked row in the form —
        // both currently-attached and saved-but-disconnected. The
        // user editing while away from a location is the whole
        // reason disconnected devices are visible, so dropping them
        // here would silently undo the user's intent on save.
        let selectedRows = attachedDevices.filter { selectedDeviceIDs.contains($0.device) }
        let fingerprint = selectedRows.map(\.device)
        let deviceNames: [USBDevice: String?] = Dictionary(
            uniqueKeysWithValues: selectedRows.map { ($0.device, $0.name) }
        )

        let profile = Profile(
            name: slug,
            fingerprint: fingerprint,
            audioInput: audioInput,
            audioOutput: audioOutput,
            camera: camera
        )

        do {
            switch mode {
            case .append:
                try ProfileWriter().append(
                    profile: profile,
                    deviceNames: deviceNames,
                    to: configURL,
                    startingHeader: AddProfileViewModel.starterHeader
                )
            case .replace:
                try ProfileWriter().replace(
                    profile: profile,
                    deviceNames: deviceNames,
                    in: configURL
                )
            }
            // Renamed an existing profile (slug differs from the one we
            // started editing) → drop the old section so the user
            // doesn't end up with both. Failures here surface as a
            // warning since the new profile already saved fine.
            if let editing = editingSlug, editing != slug {
                do {
                    try ProfileWriter().delete(named: editing, in: configURL)
                } catch {
                    lastError = "Saved as \"\(PrettyName.format(slug))\", but couldn't remove the old \"\(PrettyName.format(editing))\" entry: \(error)"
                }
            }
            didSave = true
            onSaved()
        } catch let ProfileWriteError.duplicateProfile(name) {
            // Race: collision check passed but the file changed
            // before write. Surface it.
            lastError = "Couldn't save: profile \"\(PrettyName.format(name))\" already exists."
        } catch let ProfileWriteError.invalidName(name) {
            lastError = "Couldn't save: \"\(name)\" isn't a valid profile name."
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
