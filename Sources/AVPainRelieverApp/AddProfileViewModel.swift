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
    /// Pretty-cased name of the profile the user is editing, when
    /// they got here by renaming an existing profile into a colliding
    /// slug. Nil when the wizard is creating a new profile and the
    /// typed name happened to collide. Drives the alert body so the
    /// edit-rename case can spell out that the profile being edited
    /// will also be deleted (both the "Update existing" and "Save as
    /// new" paths drop the original section, see `performSave`'s
    /// `editingSlug != slug` cleanup).
    let editingPrettyName: String?
}

/// State the view shows when the user tries to save a profile whose
/// USB fingerprint exactly matches another saved profile. The
/// resolver tiebreaks alphabetically, so two profiles with the same
/// fingerprint mean only one of them ever auto-applies. The other
/// is reachable only via the menu's Switch to submenu. The warning
/// dialog spells out the consequence and lets the user save anyway
/// or cancel back to the form. Separate from `PendingCollision`,
/// which handles slug clashes (a totally different scenario where
/// the user explicitly opts into duplication).
struct PendingFingerprintWarning: Identifiable, Equatable {
    let id = UUID()
    /// Pretty-cased name of the other profile that already owns this
    /// fingerprint, e.g. "Home Office". Drives the alert body.
    let existingPrettyName: String
}

/// Owns the editable state of the Add-Profile form and runs the save
/// action. Created with the data sources it needs (USB watcher,
/// audio controller, target file URL, post-save reload callback)
/// rather than reaching into `AppDelegate` itself, which keeps the
/// view model independently testable later.
@MainActor
final class AddProfileViewModel: ObservableObject {
    // MARK: - Form state

    @Published var name: String = "" {
        didSet {
            // Any user edit to the name field clears the
            // auto-suggest flag — the value is no longer the
            // suggestion, so the "Suggested" caption must drop.
            // Guard against the trivial set-to-self case (refresh()
            // re-running the same suggestion).
            if name != oldValue && nameWasAutoSuggested {
                nameWasAutoSuggested = false
            }
        }
    }
    /// True when the current `name` value was filled in by
    /// `ProfileIcon.suggestedName(forDeviceNames:)` rather than typed
    /// by the user. Drives a small "Suggested." caption in the wizard
    /// so the auto-fill behavior is discoverable instead of looking
    /// like the wizard guessed the user's mind. Reset by `name`'s
    /// `didSet` the moment the user edits the field.
    @Published private(set) var nameWasAutoSuggested: Bool = false
    @Published var audioInput: String? = nil
    @Published var audioOutput: String? = nil
    @Published var camera: String? = nil
    /// User-picked SF Symbol for this profile. `nil` means "use the
    /// auto-mapper based on the slug" — that's the default until the
    /// user opens the icon picker and chooses something. Persisted to
    /// the TOML's `icon` field on save.
    @Published var icon: String? = nil

    /// Devices shown in the wizard's USB-fingerprint list. Union of
    /// (currently-attached devices) and (devices the editing profile
    /// saved that aren't currently attached). Sorted by display name
    /// with disconnected entries pushed to the bottom so the active
    /// hardware is visually grouped at the top.
    @Published private(set) var attachedDevices: [NamedUSBDevice] = []
    /// Subset of `attachedDevices` IDs the user has checked.
    @Published var selectedDeviceIDs: Set<USBDevice> = []

    /// True when the user has zero devices ticked, which makes the
    /// profile an *implicit fallback*: the resolver treats an empty
    /// fingerprint as matching any USB state with specificity 0, so
    /// it wins only when no more-specific profile matches. The wizard
    /// surfaces this state with a tailored hint so a user who saves
    /// without realizing what they did doesn't end up with (a) an
    /// always-matching profile that drowns out their other locations
    /// or (b) the inverse — a many-device fingerprint accidentally
    /// captured on a profile they meant to be the fallback. The
    /// canonical user case for this hint is the default "laptop"
    /// profile: empty fingerprint, kicks in when undocked.
    var willMatchAnywhere: Bool {
        selectedDeviceIDs.isEmpty
    }
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

    /// Set when the user attempts to save a profile whose USB
    /// fingerprint exactly matches another saved profile's
    /// fingerprint. The view shows a "soft" alert (Save Anyway /
    /// Cancel) explaining that auto-switching will alphabetical-
    /// tiebreak between the two and only one will ever apply
    /// automatically. Independent of `pendingCollision`: that's a
    /// slug-clash dialog where the user explicitly opts into
    /// duplication; this one warns about a quieter ambiguity that's
    /// easy to miss otherwise.
    @Published var pendingFingerprintWarning: PendingFingerprintWarning? = nil

    /// Save context stashed across the fingerprint-warning dialog so
    /// `confirmFingerprintWarning()` can resume the save with the
    /// exact same slug/mode/forceApply the user originally hit Save
    /// with. Cleared on cancel as well so a subsequent save starts
    /// from a clean slate.
    private var stashedSaveContext: (slug: String, mode: SaveMode, forceApply: Bool)?

    // MARK: - Dependencies

    private let watcher: USBWatcher
    private let audioController: AudioInventory
    private let cameraController: CameraInventory
    private let configURL: URL
    /// Persistent store for the wizard's remembered-devices caches.
    /// Optional so tests that only care about live-snapshot behavior
    /// can omit it; production always passes a real store via
    /// `AppDelegate.addProfileDependencies`. When non-nil, `refresh()`
    /// appends current live device names + the editing profile's
    /// saved audio/camera selections into the caches, and the
    /// disconnected-name lists below derive from `remembered \ live`.
    private let settings: SettingsStore?
    /// Notifies the host that the wizard wrote a profile to disk.
    /// `forceApplySlug` is the slug the host should explicitly apply
    /// after reloading — non-nil for the collision "Save as new" path,
    /// where the new profile shares its fingerprint with the colliding
    /// sibling and would lose `ProfileResolver`'s alphabetical
    /// tiebreak. Nil for every other save path (no-collision append,
    /// in-place edit, rename, collision update-existing) — those let
    /// the resolver pick normally.
    private let onSaved: (_ forceApplySlug: String?) -> Void
    private let editingSlug: String?
    /// Slugs of all profiles that already exist in the user's
    /// config. The wizard consults this to suppress
    /// `ProfileIcon.suggestedName` when its proposed slug is
    /// already taken — auto-filling "home-office" when the user
    /// already has a Home Office profile would just create a
    /// pre-loaded collision they'd have to resolve at save time.
    /// Empty set means "don't suppress" (used by tests + the
    /// pre-collision-check codepath).
    private let existingProfileSlugs: Set<String>
    /// Every other saved profile (the editing one filtered out),
    /// kept so the wizard can cross-reference currently-attached
    /// USB devices and label rows that belong to *another* location.
    /// Without this, a user editing Conference Room from home sees
    /// CalDigit in the device list with no hint that it belongs to
    /// Home Office. Empty in tests that don't exercise the
    /// cross-reference labels.
    private let otherProfiles: [Profile]

    /// Whether the host's virtual camera is currently the active
    /// routing layer. Used to (a) hide the virtual camera from the
    /// camera picker — it's an *output*, not a source the user
    /// should select per profile, and (b) tailor the helper text
    /// under the picker so the wizard explains the model the user
    /// has actually opted into.
    let virtualCameraEnabled: Bool

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
        audioController: AudioInventory,
        cameraController: CameraInventory,
        configURL: URL,
        editing: Profile? = nil,
        existingProfileSlugs: Set<String> = [],
        otherProfiles: [Profile] = [],
        virtualCameraEnabled: Bool = false,
        settings: SettingsStore? = nil,
        onSaved: @escaping (_ forceApplySlug: String?) -> Void
    ) {
        self.watcher = watcher
        self.audioController = audioController
        self.cameraController = cameraController
        self.configURL = configURL
        self.onSaved = onSaved
        self.editingSlug = editing?.name
        self.existingProfileSlugs = existingProfileSlugs
        // Filter the editing profile out defensively in case the
        // caller passed every available profile; the cross-reference
        // pill is for *other* profiles, not "this is in itself."
        let editingName = editing?.name
        self.otherProfiles = otherProfiles.filter { $0.name != editingName }
        self.virtualCameraEnabled = virtualCameraEnabled
        self.settings = settings

        if let profile = editing {
            // Pre-populate from the existing profile so the user can
            // adjust the bits they care about. Pretty-cased name keeps
            // the textfield human-readable; we re-slugify on save.
            self.name = PrettyName.format(profile.name)
            self.audioInput = profile.audioInput
            self.audioOutput = profile.audioOutput
            self.camera = profile.camera
            self.icon = profile.icon
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

        // When editing, the profile's saved fingerprint (whether
        // currently attached or not) floats to the top so the user
        // immediately sees "these are the devices this profile is
        // built from." Below that, any unticked currently-attached
        // devices the user might want to add. This makes the
        // edit-from-elsewhere flow obvious even when most of the
        // fingerprint is disconnected.
        //
        // When adding (savedFingerprint empty, disconnected empty),
        // the expression collapses to a plain tier-sorted live
        // snapshot. The auto-tick logic below picks the Important
        // rows, which already appear first via the tier sort.
        let fingerprintIDs = Set(savedFingerprint)
        let liveInFingerprint = liveSnapshot.filter { fingerprintIDs.contains($0.device) }
        let liveOutOfFingerprint = liveSnapshot.filter { !fingerprintIDs.contains($0.device) }
        attachedDevices = Self.sortedByTier(liveInFingerprint)
            + Self.sortedByTier(disconnected)
            + Self.sortedByTier(liveOutOfFingerprint)
        disconnectedDeviceIDs = disconnectedIDs

        // Default selection: only the headline hardware classified
        // as Important (mics, cameras, capture cards, dedicated
        // audio interfaces). Earlier versions auto-ticked every
        // attached device and required the user to deliberately
        // untick the peripherals that travel — but that loaded
        // cognitive work onto the user and produced over-broad
        // fingerprints (a Magic Keyboard quietly winds up in a
        // home-office fingerprint because the user forgot to
        // untick it).
        //
        // Now: tick only the things we have a confident "this
        // defines the location" signal on. The user actively ticks
        // anything else they want in the fingerprint (hub legs,
        // displays, Stream Decks, etc. — all visible but unticked).
        // Skipped when editing: the saved fingerprint already
        // populated `selectedDeviceIDs` before refresh() runs, so
        // the empty-check fails and existing selections survive.
        if selectedDeviceIDs.isEmpty && editingSlug == nil {
            selectedDeviceIDs = Set(
                liveSnapshot
                    .filter {
                        DevicePortability
                            .importantCategory(deviceName: $0.name) != nil
                    }
                    .map(\.device)
            )
        }
        audioDevices = audioController.availableDevices()
        // Filter the embedded virtual camera out of the picker —
        // it's an output, not a source. A profile names the *real*
        // camera that the virtual camera should route. Filtering
        // here also quietly cleans up profiles created during the
        // brief window where the virtual camera was selectable: the
        // saved-but-now-invalid value is sanitized below.
        cameras = cameraController.availableCameras()
            .filter { $0.name != VirtualCameraActivator.virtualCameraDisplayName }
        if camera == VirtualCameraActivator.virtualCameraDisplayName {
            camera = nil
        }

        // Seed the editing profile's per-profile cache with ONLY its
        // saved-on-disk selections (never live attached devices).
        // Live devices already show up in the dropdown via `audioDevices`
        // and `cameras`; caching them would falsely make Conference
        // Room "remember" CalDigit just because CalDigit happened to
        // be attached when the user opened Conference Room's wizard
        // at their home dock. The cache only exists to keep a profile's
        // OWN saved selections visible across disconnects.
        //
        // When adding a new profile (editingSlug == nil) there's no
        // profile-key yet, so the seed is skipped entirely. History
        // builds up once the profile exists and is reopened.
        if let editingSlug {
            let inputsToRemember = audioInput.map { [$0] } ?? []
            let outputsToRemember = audioOutput.map { [$0] } ?? []
            let camerasToRemember = camera.map { [$0] } ?? []
            settings?.rememberDevices(
                forProfile: editingSlug,
                audioInputs: inputsToRemember,
                audioOutputs: outputsToRemember,
                cameras: camerasToRemember
            )
        }

        // Pre-select whatever the system currently uses so the user
        // doesn't have to repeat audio/camera choices they already
        // made manually before opening the wizard. Only sets an
        // unset field; never overwrites a deliberate user pick.
        let defaults = audioController.currentDefaults()
        if audioInput == nil { audioInput = defaults.inputName }
        if audioOutput == nil { audioOutput = defaults.outputName }
        if camera == nil {
            // `currentPreferredName()` will read back "AV Pain
            // Reliever" once the virtual camera is the system-wide
            // preferred — that's by design (#2). Skip it here so
            // the pre-fill always lands on a *real* camera.
            let preferred = cameraController.currentPreferredName()
            camera = preferred == VirtualCameraActivator.virtualCameraDisplayName ? nil : preferred
        }

        // First-launch convenience: if the user hasn't typed a name and
        // we recognize a docked-setup signature in the attached
        // devices, pre-fill a sensible suggestion. Only when adding —
        // editing keeps the existing name. The user can always rename.
        if name.isEmpty && editingSlug == nil {
            let deviceNames = liveSnapshot.compactMap { $0.name }
            if let suggested = ProfileIcon.suggestedName(forDeviceNames: deviceNames),
               !existingProfileSlugs.contains(suggested)
            {
                // Skip the auto-fill when a profile by the suggested
                // slug already exists. The user clicking "Add Profile"
                // is asking for a NEW location, not a recapture of
                // the existing one — pre-loading the same name would
                // just queue up a save-time collision they'd have to
                // resolve.
                name = PrettyName.format(suggested)
                // Set AFTER the assignment — `name`'s didSet clears
                // the flag, so we have to re-set true here for the
                // wizard to know the value came from us, not the
                // user.
                nameWasAutoSuggested = true
            }
        }
    }

    var inputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsInput)
    }

    var outputDevices: [AudioDevice] {
        audioDevices.filter(\.supportsOutput)
    }

    /// Editing profile's remembered audio input names that aren't
    /// currently attached. The wizard's input picker renders these at
    /// the bottom of the list (alphabetical, with a "(not connected)"
    /// suffix) so a user editing from a different location can still
    /// pick the right mic. Empty when adding a new profile (no
    /// profile-key yet), when no `SettingsStore` was injected (test
    /// cases), or when this profile has no remembered names.
    var disconnectedInputNames: [String] {
        Self.disconnected(
            remembered: settings?.rememberedAudioInputs[editingSlug ?? ""],
            from: inputDevices.map(\.name)
        )
    }

    /// Editing profile's remembered audio output names that aren't
    /// currently attached.
    var disconnectedOutputNames: [String] {
        Self.disconnected(
            remembered: settings?.rememberedAudioOutputs[editingSlug ?? ""],
            from: outputDevices.map(\.name)
        )
    }

    /// Editing profile's remembered camera names that aren't
    /// currently attached.
    var disconnectedCameraNames: [String] {
        Self.disconnected(
            remembered: settings?.rememberedCameras[editingSlug ?? ""],
            from: cameras.map(\.name)
        )
    }

    private static func disconnected(remembered: [String]?, from live: [String]) -> [String] {
        guard let remembered else { return [] }
        let liveSet = Set(live)
        return remembered.filter { !liveSet.contains($0) }.sorted()
    }

    /// Whether the wizard should render the green "Important: <cat>"
    /// pill for `device`. The pill was designed to explain why a
    /// device gets auto-ticked into a new profile's fingerprint, so
    /// it only makes sense in two contexts:
    ///
    /// 1. Adding a new profile (auto-tick is live).
    /// 2. Editing an existing profile and the device is already in
    ///    its fingerprint (the pill confirms why it's ticked).
    ///
    /// Editing Conference Room while at home and seeing CalDigit
    /// labeled "Important: Audio" (the source of this gate) would
    /// be a false claim that CalDigit matters to Conference Room.
    /// The view falls through to `otherProfileLabel(forDevice:)` so
    /// the user instead sees "In Home Office" on those rows.
    func shouldShowImportantPill(forDevice device: USBDevice) -> Bool {
        selectedDeviceIDs.contains(device) || !editingExisting
    }

    /// Quiet gray label the wizard renders on a currently-attached
    /// device that doesn't belong to THIS profile's fingerprint but
    /// does belong to one (or more) other saved profiles. Lets a
    /// user editing Conference Room from home see "In Home Office"
    /// on the CalDigit row instead of an unexplained device. Returns
    /// nil when the device isn't in any other profile's fingerprint.
    /// For multiple matches we render a count phrase rather than
    /// listing names. The pill's job is to orient, not enumerate.
    ///
    /// Always nil when *adding* a new profile: the add flow is about
    /// capturing the current location, not investigating how each
    /// attached device relates to other profiles. Surfacing those
    /// labels there reads as noise (every device the user has ever
    /// fingerprinted suddenly gets a "lives somewhere else" badge).
    func otherProfileLabel(forDevice device: USBDevice) -> String? {
        guard editingExisting else { return nil }
        let matches = otherProfiles.filter { $0.fingerprint.contains(device) }
        switch matches.count {
        case 0: return nil
        case 1: return "In \(PrettyName.format(matches[0].name))"
        default: return "In \(matches.count) other profiles"
        }
    }

    /// Four-tier sort for the wizard's device list, alphabetical
    /// within each tier:
    /// 1. Important (mic / video / speaker / audio per
    ///    `DevicePortability.importantCategory`) — top, easiest to
    ///    scan when picking fingerprint candidates.
    /// 2. Other named, non-portable.
    /// 3. Portable named (keyboards, mice, phones — likely to
    ///    travel with the user, not great fingerprint candidates).
    /// 4. Unnamed (vendor + product both nil — usually internal
    ///    hub legs of multi-function devices, low signal value)
    ///    — bottom.
    ///
    /// Important wins over portable when the rare overlap appears
    /// (e.g. a "Mic Mouse"), so the pill's strongest signal is
    /// always at the top of the list.
    ///
    /// Single source of truth for both classifications:
    /// `DevicePortability.importantCategory` /
    /// `DevicePortability.portabilityCategory`.
    private static func sortedByTier(_ devices: [NamedUSBDevice])
        -> [NamedUSBDevice]
    {
        devices.sorted { lhs, rhs in
            let lhsTier = tier(for: lhs)
            let rhsTier = tier(for: rhs)
            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }
            return lhs.displayName < rhs.displayName
        }
    }

    /// Lower number = higher in the list.
    private static func tier(for device: NamedUSBDevice) -> Int {
        if DevicePortability.importantCategory(deviceName: device.name) != nil {
            return 0
        }
        if device.name == nil && device.vendorName == nil {
            return 3
        }
        if DevicePortability.portabilityCategory(deviceName: device.name) != nil {
            return 2
        }
        return 1
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
            // editingSlug is non-nil here only when the user is
            // editing an existing profile and renamed it into a
            // colliding slug — `save()`'s in-place fast-path above
            // already returned for the `slug == editingSlug` case,
            // so reaching this branch means we're truly renaming.
            pendingCollision = PendingCollision(
                existingPrettyName: PrettyName.format(slug),
                newSlug: writer.nextAvailableName(base: slug, in: configURL),
                existingSlug: slug,
                editingPrettyName: editingSlug.map(PrettyName.format)
            )
            return
        }
        // Reaching here means we're either creating a fresh profile
        // (editingSlug == nil) or renaming an existing one to a free
        // slug. Force-apply only the fresh-profile case so the new
        // slug wins `ProfileResolver`'s alphabetical tiebreak — the
        // user just declared "this profile is active now." Edit-
        // renames stay deliberately resolver-driven: if the user
        // renames a profile they aren't currently on, the host
        // shouldn't force-switch them; the resolver will keep them
        // where they were.
        performSave(slug: slug, mode: .append, forceApply: editingSlug == nil)
    }

    /// User picked "Update existing" in the collision dialog — replace
    /// the prior profile's section with our current selections. Force-
    /// applies unconditionally: clicking a button in the collision
    /// dialog is an explicit user choice about which profile to land
    /// on (the alternative was Cancel). Without force-apply, the
    /// resolver might tiebreak away from the merged target — or, in
    /// edit-rename collisions, pick a wholly unrelated profile because
    /// the editing slug just got deleted.
    func confirmReplace() {
        guard let collision = pendingCollision else { return }
        pendingCollision = nil
        // Skip the fingerprint warning: clicking Update is an
        // explicit duplication choice that already passed through
        // the (separate) name-collision dialog.
        performSave(slug: collision.existingSlug, mode: .replace, forceApply: true, bypassFingerprintCheck: true)
    }

    /// User picked "Save as new" in the collision dialog — append
    /// under the auto-suggested suffixed slug. Force-applies for the
    /// same reason as `confirmReplace`: the dialog button is the
    /// user's explicit "land me on this" signal.
    func confirmSaveAsNew() {
        guard let collision = pendingCollision else { return }
        pendingCollision = nil
        // Skip the fingerprint warning: Save-as-new is almost always
        // a deliberate fingerprint-duplication choice (that's how
        // you split one location into multiple profiles), and the
        // user already made it past one dialog.
        performSave(slug: collision.newSlug, mode: .append, forceApply: true, bypassFingerprintCheck: true)
    }

    /// User picked "Cancel" — drop the collision state and let them
    /// edit the form.
    func cancelCollision() {
        pendingCollision = nil
    }

    /// User picked "Save Anyway" in the fingerprint-warning dialog.
    /// Resume the save with the stashed context, bypassing the check
    /// so we don't re-prompt for the same conflict.
    func confirmFingerprintWarning() {
        guard let context = stashedSaveContext else { return }
        pendingFingerprintWarning = nil
        stashedSaveContext = nil
        performSave(
            slug: context.slug,
            mode: context.mode,
            forceApply: context.forceApply,
            bypassFingerprintCheck: true
        )
    }

    /// User picked "Cancel" in the fingerprint-warning dialog. Drop
    /// the warning + stashed context so a subsequent save runs the
    /// check fresh.
    func cancelFingerprintWarning() {
        pendingFingerprintWarning = nil
        stashedSaveContext = nil
    }

    /// Return the first *other* saved profile whose fingerprint is
    /// the exact same set as `fingerprint`, or nil. Set comparison
    /// so order and TOML round-trip noise don't matter. Used by the
    /// save path to flag the alphabetical-tiebreak hazard before the
    /// write goes through. The editing profile is already filtered
    /// out of `otherProfiles` so self-comparison never triggers.
    func conflictingProfile(forFingerprint fingerprint: [USBDevice]) -> Profile? {
        let target = Set(fingerprint)
        return otherProfiles.first { Set($0.fingerprint) == target }
    }

    // MARK: - Implementation

    private enum SaveMode {
        case append
        case replace
    }

    private func performSave(slug: String, mode: SaveMode, forceApply: Bool = false, bypassFingerprintCheck: Bool = false) {
        // Build the fingerprint from EVERY ticked row in the form —
        // both currently-attached and saved-but-disconnected. The
        // user editing while away from a location is the whole
        // reason disconnected devices are visible, so dropping them
        // here would silently undo the user's intent on save.
        let selectedRows = attachedDevices.filter { selectedDeviceIDs.contains($0.device) }
        let fingerprint = selectedRows.map(\.device)

        // Soft warning: another saved profile already owns this
        // exact fingerprint. The resolver alphabetical-tiebreaks
        // between same-specificity matches, so only one of the two
        // would ever auto-apply. Pause the save and let the user
        // confirm via `confirmFingerprintWarning()` (which calls
        // back through with `bypassFingerprintCheck: true`) or back
        // out via `cancelFingerprintWarning()`. The collision-dialog
        // continuation methods (confirmReplace / confirmSaveAsNew)
        // bypass this check because they're explicit duplication
        // choices already.
        if !bypassFingerprintCheck,
           let conflict = conflictingProfile(forFingerprint: fingerprint)
        {
            stashedSaveContext = (slug: slug, mode: mode, forceApply: forceApply)
            pendingFingerprintWarning = PendingFingerprintWarning(
                existingPrettyName: PrettyName.format(conflict.name)
            )
            return
        }

        isSaving = true
        lastError = nil
        defer { isSaving = false }

        let deviceNames: [USBDevice: String?] = Dictionary(
            uniqueKeysWithValues: selectedRows.map { ($0.device, $0.name) }
        )

        let profile = Profile(
            name: slug,
            fingerprint: fingerprint,
            audioInput: audioInput,
            audioOutput: audioOutput,
            camera: camera,
            icon: icon
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
            // started editing). Drop the old TOML section so the user
            // doesn't end up with both, and migrate the editing
            // profile's per-slug state (stats + remembered-device
            // caches) over to the new slug. For mode .replace
            // (collision "Update existing"), the editing profile is
            // being subsumed into the target, so its side data goes
            // away via forgetProfile instead of being moved.
            // Failures on the TOML delete surface as a warning since
            // the new profile already saved fine.
            if let editing = editingSlug, editing != slug {
                switch mode {
                case .append:
                    settings?.renameProfile(from: editing, to: slug)
                case .replace:
                    settings?.forgetProfile(slug: editing)
                }
                do {
                    try ProfileWriter().delete(named: editing, in: configURL)
                } catch {
                    lastError = "Saved as \"\(PrettyName.format(slug))\", but couldn't remove the old \"\(PrettyName.format(editing))\" entry: \(error)"
                }
            }
            didSave = true
            onSaved(forceApply ? slug : nil)
        } catch let ProfileWriteError.duplicateProfile(name) {
            // Race: collision check passed but the file changed
            // before write. Surface it.
            lastError = "Couldn't save: profile \"\(PrettyName.format(name))\" already exists."
        } catch let ProfileWriteError.missingProfile(name) {
            // Race: replace expected the section to be there but
            // someone (the user editing the TOML by hand, another
            // tool) removed it between collision check and write.
            lastError = "Couldn't save: profile \"\(PrettyName.format(name))\" is no longer in the config. Try Add Profile instead."
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
    # AV Pain Reliever profile config.
    # Each [profiles.<name>] section defines a location.
    # See https://github.com/superic/av-pain-reliever for the schema.

    """
}
