import Testing
import Foundation
@testable import AVPainReliever
@testable import AVPainRelieverApp

/// Unit tests for the wizard's view model — focused on the edit-mode
/// pre-fill, the auto-suggest from attached devices, and the rename
/// path that should clean up the old TOML section.
@MainActor
@Suite("AddProfileViewModel")
struct AddProfileViewModelTests {

    @Test("opening on an existing profile pre-fills name + audio + camera")
    func editModePreFills() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit"
            )
        ]
        let audio = FakeAudio(devices: ["Yeti", "MacBook Pro Microphone"])
        let camera = FakeCamera(cameras: ["Built-in"])

        let editing = Profile(
            name: "home-office",
            fingerprint: [USBDevice(vendorID: 0x2188, productID: 0x6533)],
            audioInput: "Yeti",
            audioOutput: "MacBook Pro Speakers",
            camera: "Built-in"
        )

        let url = URL(fileURLWithPath: "/tmp/does-not-matter.toml")
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: audio,
            cameraController: camera,
            configURL: url,
            editing: editing,
            onSaved: { _ in }
        )

        #expect(vm.name == "Home Office")
        #expect(vm.audioInput == "Yeti")
        #expect(vm.audioOutput == "MacBook Pro Speakers")
        #expect(vm.camera == "Built-in")
        #expect(vm.editingExisting == true)
        #expect(vm.selectedDeviceIDs == [USBDevice(vendorID: 0x2188, productID: 0x6533)])
        // No icon override on the editing profile → viewModel.icon
        // stays nil so the wizard's preview picks up the auto-mapper.
        #expect(vm.icon == nil)
    }

    @Test("opening on an existing profile with an icon pre-fills the override")
    func editModePreFillsIcon() {
        let editing = Profile(
            name: "studio",
            fingerprint: [],
            audioInput: "Shure MV7",
            icon: "music.mic"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            onSaved: { _ in }
        )
        #expect(vm.icon == "music.mic")
    }

    @Test("opening fresh auto-suggests a name for a recognized dock")
    func suggestsHomeOfficeForCalDigit() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            )
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            onSaved: { _ in }
        )
        #expect(vm.name == "Home Office")
    }

    @Test("opening fresh leaves name blank when nothing recognizable is plugged in")
    func leavesNameBlankForUnknownDevices() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0xFFFF, productID: 0xFFFF),
                name: "Generic Hub"
            )
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            onSaved: { _ in }
        )
        #expect(vm.name == "")
    }

    @Test("editing then saving without a rename overwrites in place")
    func editAndSaveReplacesInPlace() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-edit-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput  = "Old Mic"
        audioOutput = "Old Out"
        """.write(to: url, atomically: true, encoding: .utf8)

        let watcher = FakeWatcher()
        let audio = FakeAudio(devices: ["New Mic", "Old Mic"])
        let camera = FakeCamera(cameras: [])

        let editing = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "Old Mic",
            audioOutput: "Old Out"
        )

        var saved = false
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: audio,
            cameraController: camera,
            configURL: url,
            editing: editing,
            onSaved: { _ in saved = true }
        )
        // User changes the input and hits save — the in-place replace
        // path should run.
        vm.audioInput = "New Mic"
        vm.save()

        #expect(saved == true)
        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)

        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "home-office")
        #expect(loaded.first?.audioInput == "New Mic")
    }

    @Test("editing keeps saved fingerprint devices visible even when not attached")
    func editingShowsDisconnectedDevices() {
        // User is undocked: only the laptop's built-in is in the
        // live snapshot. The editing profile fingerprints two
        // dock-side devices that aren't currently attached.
        let watcher = FakeWatcher()
        watcher.named = []  // undocked, no peripherals
        let dockDevice = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let monitorDevice = USBDevice(vendorID: 0x043e, productID: 0x9a68)

        let editing = Profile(
            name: "home-office",
            fingerprint: [dockDevice, monitorDevice],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "CalDigit Thunderbolt 3 Audio",
            camera: "LG UltraFine Display Camera",
            fingerprintNames: [
                dockDevice: "CalDigit Thunderbolt 3 Audio",
                monitorDevice: "LG UltraFine Display Camera"
            ]
        )

        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: ["MacBook Pro Microphone"]),
            cameraController: FakeCamera(cameras: ["FaceTime HD"]),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            onSaved: { _ in }
        )

        // Both saved devices appear in the form even though neither is
        // currently attached, with the right names + flagged disconnected.
        let presented = Set(vm.attachedDevices.map(\.device))
        #expect(presented == [dockDevice, monitorDevice])
        #expect(vm.disconnectedDeviceIDs == [dockDevice, monitorDevice])
        let dockEntry = vm.attachedDevices.first { $0.device == dockDevice }
        #expect(dockEntry?.name == "CalDigit Thunderbolt 3 Audio")
        // Selection is preserved across the disconnect — saved fingerprint
        // devices stay ticked by default.
        #expect(vm.selectedDeviceIDs == [dockDevice, monitorDevice])
        // Audio + camera saved values stay populated regardless of what
        // CoreAudio / AVFoundation report being available right now.
        #expect(vm.audioInput == "Yeti Stereo Microphone")
        #expect(vm.audioOutput == "CalDigit Thunderbolt 3 Audio")
        #expect(vm.camera == "LG UltraFine Display Camera")
    }

    @Test("saving an undocked edit preserves the disconnected fingerprint")
    func savingPreservesDisconnectedFingerprint() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-disconnected-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput  = "Yeti Stereo Microphone"
        audioOutput = "CalDigit Thunderbolt 3 Audio"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
          { vendorID = 0x043e, productID = 0x9a68, name = "LG UltraFine" },
        ]
        """.write(to: url, atomically: true, encoding: .utf8)

        let dockDevice = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let monitorDevice = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        let editing = Profile(
            name: "home-office",
            fingerprint: [dockDevice, monitorDevice],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "CalDigit Thunderbolt 3 Audio",
            fingerprintNames: [
                dockDevice: "CalDigit dock",
                monitorDevice: "LG UltraFine"
            ]
        )

        // Watcher reports nothing attached (user is undocked).
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            onSaved: { _ in }
        )
        // User edits something trivial (audio input) and saves.
        vm.audioInput = "Yeti Stereo Microphone"
        vm.save()

        #expect(vm.lastError == nil)
        let loaded = try ConfigLoader().loadProfiles(from: url)
        let saved = loaded.first { $0.name == "home-office" }!
        // Saving while undocked must NOT silently strip the fingerprint —
        // the user editing while away from the location is exactly the
        // case this preserves.
        #expect(Set(saved.fingerprint) == [dockDevice, monitorDevice])
        // And the names round-trip too, so the next edit also sees them.
        #expect(saved.fingerprintNames[dockDevice] == "CalDigit dock")
        #expect(saved.fingerprintNames[monitorDevice] == "LG UltraFine")
    }

    @Test("unticking a disconnected saved device drops it on save")
    func untickingDisconnectedDeviceRemovesItOnSave() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-untick-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput  = "Yeti"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "Dock" },
          { vendorID = 0x043e, productID = 0x9a68, name = "Monitor" },
        ]
        """.write(to: url, atomically: true, encoding: .utf8)

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let monitor = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        let editing = Profile(
            name: "home-office",
            fingerprint: [dock, monitor],
            audioInput: "Yeti",
            fingerprintNames: [dock: "Dock", monitor: "Monitor"]
        )

        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            onSaved: { _ in }
        )
        // User unticks the monitor while undocked. The save should
        // drop it from the fingerprint just like unticking an
        // attached device would.
        vm.selectedDeviceIDs.remove(monitor)
        vm.save()

        #expect(vm.lastError == nil)
        let loaded = try ConfigLoader().loadProfiles(from: url)
        let saved = loaded.first { $0.name == "home-office" }!
        #expect(saved.fingerprint == [dock])
    }

    @Test("renaming an edited profile migrates its remembered-device cache to the new slug")
    func renameMigratesRememberedDevicesCache() throws {
        // Journey test for the orphan-on-rename gap surfaced by slop
        // review. Setup: a saved profile "home-office" with Yeti as
        // audioInput. The wizard's refresh seeds the per-profile
        // cache. User renames to "Apartment" and saves. The cache
        // entry should follow the rename (Apartment has Yeti
        // remembered, home-office key is gone).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-rename-cache-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        """.write(to: url, atomically: true, encoding: .utf8)

        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let editing = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "Yeti"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Yeti"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        // Sanity: init seeded the cache under the original slug.
        #expect(settings.rememberedAudioInputs["home-office"] == ["Yeti"])

        vm.name = "Apartment"
        vm.save()

        #expect(vm.lastError == nil)
        // Cache moved with the rename. The old slug is gone.
        #expect(settings.rememberedAudioInputs["home-office"] == nil)
        #expect(settings.rememberedAudioInputs["apartment"] == ["Yeti"])
    }

    @Test("collision Update-existing drops the editing profile's remembered-device cache")
    func updateExistingSubsumesEditingCache() throws {
        // Sibling journey test: when the user resolves a name
        // collision via "Update existing", the editing profile is
        // subsumed into the target. The editing profile's cache
        // entries should NOT bleed into the target's; the target
        // keeps its own identity. forgetProfile is the right
        // semantic (cache wiped, not migrated).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-update-cache-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Existing Mic"

        [profiles.studio]
        audioInput = "Studio Mic"
        """.write(to: url, atomically: true, encoding: .utf8)

        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        // Pre-seed Home Office's cache so we can verify it survives
        // the Update Existing flow that wipes Studio's cache.
        settings.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Existing Mic"], audioOutputs: [], cameras: []
        )

        let editing = Profile(name: "studio", fingerprint: [], audioInput: "Studio Mic")
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Studio Mic", "Existing Mic"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            existingProfileSlugs: ["home-office", "studio"],
            settings: settings,
            onSaved: { _ in }
        )
        // Sanity: studio's cache seeded.
        #expect(settings.rememberedAudioInputs["studio"] == ["Studio Mic"])

        vm.name = "home-office"
        vm.save()
        #expect(vm.pendingCollision != nil)
        vm.confirmReplace()

        #expect(vm.lastError == nil)
        // Studio's cache is gone (subsumed). Home Office's cache
        // stays intact, untouched by the merge.
        #expect(settings.rememberedAudioInputs["studio"] == nil)
        #expect(settings.rememberedAudioInputs["home-office"] == ["Existing Mic"])
    }

    @Test("deleting a profile via forgetProfile clears its cache; subsequent edits don't see it")
    func deleteProfileClearsCacheJourney() {
        // Journey test routed through SettingsStore.forgetProfile
        // (which AppDelegate.deleteProfile calls). After the delete,
        // a hypothetical wizard rebuild for any other profile must
        // not see the deleted profile's cache via the "In Other
        // Profile" cross-reference.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.rememberDevices(
            forProfile: "conference-room",
            audioInputs: ["Yeti"], audioOutputs: [], cameras: ["Conference Cam"]
        )

        settings.forgetProfile(slug: "conference-room")

        #expect(settings.rememberedAudioInputs["conference-room"] == nil)
        #expect(settings.rememberedCameras["conference-room"] == nil)
        #expect(settings.hasRememberedDevices == false)
    }

    @Test("renaming an edited profile removes the old section")
    func renameDeletesPriorSection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-rename-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        """.write(to: url, atomically: true, encoding: .utf8)

        let editing = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "Yeti"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Yeti"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            onSaved: { _ in }
        )
        vm.name = "Home Studio"
        vm.save()

        #expect(vm.lastError == nil)
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["home-studio"])
    }

    @Test("device list sorts important → named → portable → unnamed, alphabetical within each tier")
    func deviceListTierSort() {
        let watcher = FakeWatcher()
        watcher.named = [
            // Important
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            ),
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x1e4e, productID: 0x701f),
                name: "HDMI to U3 capture"
            ),
            // Other named, non-portable
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x0747),
                name: "CalDigit — Card Reader",
                vendorName: nil
            ),
            // Portable
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x05ac, productID: 0x024f),
                name: "Magic Keyboard"
            ),
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x05ac, productID: 0x0265),
                name: "Magic Trackpad"
            ),
            // Unnamed
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x043e, productID: 0x9a71),
                name: nil,
                vendorName: nil
            ),
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x043e, productID: 0x9a73),
                name: nil,
                vendorName: nil
            ),
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/tier.toml"),
            editing: nil,
            onSaved: { _ in }
        )
        let displayNames = vm.attachedDevices.map(\.displayName)
        #expect(displayNames == [
            // Tier 0: Important, alphabetical
            "CalDigit Thunderbolt 3 Audio",
            "HDMI to U3 capture",
            // Tier 1: Other named, non-portable
            "CalDigit — Card Reader",
            // Tier 2: Portable
            "Magic Keyboard",
            "Magic Trackpad",
            // Tier 3: Unnamed
            "(unnamed device)",
            "(unnamed device)",
        ])
    }

    @Test("auto-suggest is suppressed when the proposed name already exists")
    func autoSuggestSuppressedOnSlugCollision() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            )
        ]
        // CalDigit would suggest "home-office" — but the user
        // already has one. The wizard must NOT auto-fill in that
        // case; it should leave the name field empty so the user
        // explicitly names their new profile.
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/coll.toml"),
            editing: nil,
            existingProfileSlugs: ["home-office"],
            onSaved: { _ in }
        )
        #expect(vm.name == "")
        #expect(vm.nameWasAutoSuggested == false)
    }

    @Test("nameWasAutoSuggested is true after first refresh on a recognized dock")
    func nameAutoSuggestSetsFlag() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            )
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/sug.toml"),
            editing: nil,
            onSaved: { _ in }
        )
        // CalDigit triggers the "home-office" suggestion in
        // ProfileIcon.suggestedName.
        #expect(vm.name == "Home Office")
        #expect(vm.nameWasAutoSuggested == true)
    }

    @Test("editing the name clears the auto-suggested flag")
    func editingNameClearsAutoSuggestedFlag() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            )
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/edit.toml"),
            editing: nil,
            onSaved: { _ in }
        )
        #expect(vm.nameWasAutoSuggested == true)
        vm.name = "Custom Name"
        #expect(vm.nameWasAutoSuggested == false)
    }

    @Test("willMatchAnywhere is true when no devices are ticked")
    func willMatchAnywhereOnEmptySelection() {
        let url = URL(fileURLWithPath: "/tmp/wma.toml")
        let watcher = FakeWatcher()
        // Watcher returns one Important device so it gets auto-
        // ticked by refresh(). Lets the test exercise both states
        // (something ticked → false; everything cleared → true).
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x2188, productID: 0x6533),
                name: "CalDigit Thunderbolt 3 Audio"
            )
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: nil,
            onSaved: { _ in }
        )
        // With one auto-ticked Important device, willMatchAnywhere
        // is false.
        #expect(vm.selectedDeviceIDs.isEmpty == false)
        #expect(vm.willMatchAnywhere == false)

        // Untick everything. Now this profile is the implicit
        // fallback at save time — the wizard hint covers this state.
        vm.selectedDeviceIDs.removeAll()
        #expect(vm.willMatchAnywhere == true)
    }

    @Test("default tick selects only Important devices, not all live ones")
    func defaultTickFiltersToImportantOnly() {
        let watcher = FakeWatcher()
        let importantDevice = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let portableDevice = USBDevice(vendorID: 0x05ac, productID: 0x024f)
        let neutralDevice = USBDevice(vendorID: 0x0fd9, productID: 0x0080)
        watcher.named = [
            NamedUSBDevice(
                device: importantDevice,
                name: "CalDigit Thunderbolt 3 Audio"
            ), // Important (matches "audio")
            NamedUSBDevice(
                device: portableDevice,
                name: "Magic Keyboard"
            ), // Portable
            NamedUSBDevice(
                device: neutralDevice,
                name: "Stream Deck MK.2"
            ), // Neutral
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/auto.toml"),
            editing: nil,
            onSaved: { _ in }
        )
        // Only the Important device is auto-ticked. The portable
        // and neutral devices appear in the list (visible to the
        // user, with their respective pills) but unticked by
        // default. The user actively ticks anything else they want
        // in the fingerprint.
        #expect(vm.selectedDeviceIDs == [importantDevice])
    }

    @Test("default tick yields empty selection when nothing Important is attached")
    func defaultTickEmptyWhenNoImportantDevices() {
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x05ac, productID: 0x024f),
                name: "Magic Keyboard"
            ), // Portable
            NamedUSBDevice(
                device: USBDevice(vendorID: 0x0fd9, productID: 0x0080),
                name: "Stream Deck MK.2"
            ), // Neutral
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/empty.toml"),
            editing: nil,
            onSaved: { _ in }
        )
        // No Important hardware → nothing auto-ticks → the
        // wizard's "Fallback profile" hint kicks in via
        // willMatchAnywhere = true.
        #expect(vm.selectedDeviceIDs.isEmpty)
        #expect(vm.willMatchAnywhere == true)
    }

    @Test("editing floats the saved fingerprint to the top, regardless of connection")
    func editingFloatsFingerprintToTop() {
        // User edits Conference Room from home. Their home dock is
        // plugged in (CalDigit, Magic Keyboard), and Conference
        // Room's fingerprint is the Conference Mic (currently live)
        // plus an LG monitor that's not here right now. The wizard
        // should show: Conference Mic (ticked, live) → LG monitor
        // (ticked, "Not connected") → then everything else attached
        // (unticked). The saved fingerprint visually anchors the top
        // of the list so the edit context is obvious.
        let conferenceMic = USBDevice(vendorID: 0x046d, productID: 0x085e)
        let lgMonitor = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        let calDigit = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let magicKeyboard = USBDevice(vendorID: 0x05ac, productID: 0x024f)

        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(device: calDigit, name: "CalDigit Thunderbolt 3 Audio"),
            NamedUSBDevice(device: conferenceMic, name: "Conference Room Mic"),
            NamedUSBDevice(device: magicKeyboard, name: "Magic Keyboard"),
        ]
        let editing = Profile(
            name: "conference-room",
            fingerprint: [conferenceMic, lgMonitor],
            fingerprintNames: [
                conferenceMic: "Conference Room Mic",
                lgMonitor: "LG UltraFine Display",
            ]
        )
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/edit-sort.toml"),
            editing: editing,
            onSaved: { _ in }
        )
        // Expected order: live in fingerprint, then disconnected in
        // fingerprint, then live out of fingerprint. Tier sort
        // applies within each group.
        let names = vm.attachedDevices.map(\.displayName)
        #expect(names == [
            "Conference Room Mic",      // live + ticked (in fingerprint)
            "LG UltraFine Display",     // disconnected + ticked
            "CalDigit Thunderbolt 3 Audio",  // live + unticked
            "Magic Keyboard",           // live + unticked
        ])
    }

    @Test("adding preserves the existing tier-sorted order")
    func addingUsesTierSort() {
        // Add mode has no saved fingerprint to float, so the order
        // collapses to the existing tier sort. Regression guard for
        // the edit-mode sort change.
        let calDigit = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let keyboard = USBDevice(vendorID: 0x05ac, productID: 0x024f)
        let watcher = FakeWatcher()
        watcher.named = [
            NamedUSBDevice(device: keyboard, name: "Magic Keyboard"),
            NamedUSBDevice(device: calDigit, name: "CalDigit Thunderbolt 3 Audio"),
        ]
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/add-sort.toml"),
            onSaved: { _ in }
        )
        // Important tier first, then portable.
        #expect(vm.attachedDevices.map(\.displayName) == [
            "CalDigit Thunderbolt 3 Audio",
            "Magic Keyboard",
        ])
    }

    // MARK: - Pill scoping (Important + In Other Profile)

    @Test("shouldShowImportantPill returns true when adding a new profile")
    func shouldShowImportantPillTrueWhenAdding() {
        // Add-new flow: auto-tick is active, the Important pill
        // explains why a device just got pre-ticked.
        let device = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            onSaved: { _ in }
        )
        #expect(vm.shouldShowImportantPill(forDevice: device) == true)
    }

    @Test("shouldShowImportantPill is gated by fingerprint membership when editing")
    func shouldShowImportantPillGatedByFingerprintWhenEditing() {
        // Editing flow: pill only fires for devices in THIS
        // profile's fingerprint. Conference Room's wizard at home
        // sees CalDigit attached — should NOT label it Important
        // because CalDigit isn't part of Conference Room's
        // fingerprint, it belongs to Home Office.
        let inFingerprint = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let notInFingerprint = USBDevice(vendorID: 0x046d, productID: 0x085e)
        let editing = Profile(
            name: "conference-room",
            fingerprint: [inFingerprint]
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            onSaved: { _ in }
        )
        #expect(vm.shouldShowImportantPill(forDevice: inFingerprint) == true)
        #expect(vm.shouldShowImportantPill(forDevice: notInFingerprint) == false)
    }

    @Test("otherProfileLabel returns nil when no other profile claims the device")
    func otherProfileLabelNilWhenNoMatch() {
        let device = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let homeOffice = Profile(name: "home-office", fingerprint: [])
        // Passing `editing:` so we exercise the actual no-match
        // branch. Without it the function would return nil at the
        // `editingExisting` guard regardless of `otherProfiles`,
        // and the assertion would tell us nothing about the match
        // logic. The `otherProfileLabelNilWhenAdding` test below
        // covers the guard.
        let editing = Profile(name: "scratch", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        #expect(vm.otherProfileLabel(forDevice: device) == nil)
    }

    @Test("otherProfileLabel surfaces the other profile's pretty name on a single match")
    func otherProfileLabelSingleMatch() {
        // Headline scenario for the cross-reference pill: editing
        // Conference Room while CalDigit (in Home Office's
        // fingerprint) is attached. The wizard should label the row
        // "In Home Office" so the user knows what they're looking at.
        let calDigit = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [calDigit]
        )
        let editing = Profile(name: "conference-room", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        #expect(vm.otherProfileLabel(forDevice: calDigit) == "In Home Office")
    }

    @Test("otherProfileLabel returns a count phrase when multiple profiles claim the device")
    func otherProfileLabelCountPhraseForMultipleMatches() {
        // A shared USB hub used at three locations. Listing every
        // profile by name would bloat the pill — the count phrase
        // orients without enumerating. Test runs in *edit* mode
        // because the cross-reference label is gated to editing only.
        let hub = USBDevice(vendorID: 0x05e3, productID: 0x0610)
        let homeOffice = Profile(name: "home-office", fingerprint: [hub])
        let conferenceRoom = Profile(name: "conference-room", fingerprint: [hub])
        let cafe = Profile(name: "cafe", fingerprint: [hub])
        let editing = Profile(name: "studio", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice, conferenceRoom, cafe],
            onSaved: { _ in }
        )
        #expect(vm.otherProfileLabel(forDevice: hub) == "In 3 other profiles")
    }

    @Test("otherProfileLabel returns nil when adding a new profile, regardless of matches")
    func otherProfileLabelNilWhenAdding() {
        // Headline bug: Keychron + LG UltraFine appeared in the Add
        // Profile wizard with "In Office" pills because the device
        // was in another saved profile's fingerprint. The user's
        // point — when adding, you're capturing the current location,
        // not investigating relationships to other profiles. Cross-
        // reference labels are gated to editing mode only.
        let device = USBDevice(vendorID: 0x05ac, productID: 0x024f)
        let homeOffice = Profile(name: "home-office", fingerprint: [device])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        #expect(vm.otherProfileLabel(forDevice: device) == nil)
    }

    @Test("otherProfileLabel excludes the editing profile itself from the cross-reference")
    func otherProfileLabelExcludesEditingProfile() {
        // The caller is expected to pass `availableProfiles` and let
        // the view model filter out the editing profile. Otherwise a
        // device in Home Office's fingerprint would render as
        // "In Home Office" while editing Home Office — nonsense.
        let device = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [device]
        )
        let editing = Profile(
            name: "home-office",
            fingerprint: [device]
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice], // caller naively passed every profile
            onSaved: { _ in }
        )
        #expect(vm.otherProfileLabel(forDevice: device) == nil)
    }

    // MARK: - Fingerprint-collision soft warning

    @Test("conflictingProfile returns nil when no other profile shares the fingerprint")
    func conflictingProfileNilWhenNoMatch() {
        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let monitor = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        let homeOffice = Profile(name: "home-office", fingerprint: [dock])
        // Passing `editing:` so the function actually runs its match
        // loop. Otherwise it'd return nil at the editingExisting
        // guard and the assertions would pass vacuously without
        // exercising the no-match path.
        let editing = Profile(name: "scratch", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        // Different fingerprint → no conflict.
        #expect(vm.conflictingProfile(forFingerprint: [dock, monitor]) == nil)
        #expect(vm.conflictingProfile(forFingerprint: [monitor]) == nil)
        #expect(vm.conflictingProfile(forFingerprint: []) == nil)
    }

    @Test("conflictingProfile returns the matching profile on exact-set fingerprint match")
    func conflictingProfileReturnsMatch() {
        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let monitor = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        let homeOffice = Profile(name: "home-office", fingerprint: [dock, monitor])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        // Same devices, different order → still a conflict (set equality).
        #expect(vm.conflictingProfile(forFingerprint: [monitor, dock])?.name == "home-office")
    }

    @Test("conflictingProfile detects two empty-fingerprint profiles colliding")
    func conflictingProfileTwoFallbacksCollide() {
        // Two profiles with empty fingerprints both match anything at
        // specificity 0 and tiebreak alphabetically. Worth warning
        // about — a user adding a second fallback usually doesn't
        // realize only one of them will ever apply.
        let laptop = Profile(name: "laptop", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            otherProfiles: [laptop],
            onSaved: { _ in }
        )
        #expect(vm.conflictingProfile(forFingerprint: [])?.name == "laptop")
    }

    @Test("conflictingProfile excludes the editing profile (handled by otherProfiles filter)")
    func conflictingProfileExcludesEditingProfile() {
        // The view model filters `otherProfiles` to exclude the
        // editing profile at init, so editing Home Office with its
        // existing fingerprint never matches "itself."
        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let homeOffice = Profile(name: "home-office", fingerprint: [dock])
        let editing = Profile(name: "home-office", fingerprint: [dock])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            otherProfiles: [homeOffice], // caller naively passes every profile
            onSaved: { _ in }
        )
        #expect(vm.conflictingProfile(forFingerprint: [dock]) == nil)
    }

    @Test("save with a colliding fingerprint surfaces the warning instead of writing")
    func saveWithConflictingFingerprintSurfacesWarning() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-fp-warn-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
        ]
        """.write(to: url, atomically: true, encoding: .utf8)

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let watcher = FakeWatcher()
        watcher.named = [NamedUSBDevice(device: dock, name: "CalDigit dock")]
        let homeOffice = Profile(name: "home-office", fingerprint: [dock])

        var savedCallbacks = 0
        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            otherProfiles: [homeOffice],
            onSaved: { _ in savedCallbacks += 1 }
        )
        vm.name = "Backup Office"
        // Pre-tick the same device so the fingerprint matches Home Office's.
        vm.selectedDeviceIDs = [dock]
        vm.save()

        // Wizard paused — no write, no onSaved callback, warning is showing.
        #expect(vm.didSave == false)
        #expect(savedCallbacks == 0)
        #expect(vm.pendingFingerprintWarning?.existingPrettyName == "Home Office")
        // File on disk is untouched.
        let beforeReload = try ConfigLoader().loadProfiles(from: url).map(\.name).sorted()
        #expect(beforeReload == ["home-office"])
    }

    @Test("confirmFingerprintWarning resumes the save with the stashed context")
    func confirmFingerprintWarningProceedsWithSave() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-fp-confirm-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
        ]
        """.write(to: url, atomically: true, encoding: .utf8)

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let watcher = FakeWatcher()
        watcher.named = [NamedUSBDevice(device: dock, name: "CalDigit dock")]
        let homeOffice = Profile(name: "home-office", fingerprint: [dock])

        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        vm.name = "Backup Office"
        vm.selectedDeviceIDs = [dock]
        vm.save()
        #expect(vm.pendingFingerprintWarning != nil)

        vm.confirmFingerprintWarning()

        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)
        #expect(vm.pendingFingerprintWarning == nil)
        let loaded = try ConfigLoader().loadProfiles(from: url).map(\.name).sorted()
        #expect(loaded == ["backup-office", "home-office"])
    }

    @Test("cancelFingerprintWarning drops the dialog without saving")
    func cancelFingerprintWarningDoesNotSave() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-fp-cancel-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
        ]
        """.write(to: url, atomically: true, encoding: .utf8)

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let watcher = FakeWatcher()
        watcher.named = [NamedUSBDevice(device: dock, name: "CalDigit dock")]
        let homeOffice = Profile(name: "home-office", fingerprint: [dock])

        let vm = AddProfileViewModel(
            watcher: watcher,
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        vm.name = "Backup Office"
        vm.selectedDeviceIDs = [dock]
        vm.save()
        #expect(vm.pendingFingerprintWarning != nil)

        vm.cancelFingerprintWarning()

        #expect(vm.pendingFingerprintWarning == nil)
        #expect(vm.didSave == false)
        let loaded = try ConfigLoader().loadProfiles(from: url).map(\.name).sorted()
        #expect(loaded == ["home-office"]) // unchanged
    }

    @Test("name-collision Save-as-new bypasses the fingerprint warning")
    func saveAsNewBypassesFingerprintWarning() throws {
        // The save-as-new path is a deliberate duplication choice
        // already (user just got past a name-collision dialog), so
        // surfacing the fingerprint warning right after would be
        // redundant. Regression test for the bypass flag in
        // `confirmSaveAsNew()`.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-fp-saveasnew-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti"
        """.write(to: url, atomically: true, encoding: .utf8)

        let homeOffice = Profile(name: "home-office", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Yeti"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            existingProfileSlugs: ["home-office"],
            otherProfiles: [homeOffice],
            onSaved: { _ in }
        )
        vm.name = "home-office" // trigger the name-collision dialog
        vm.save()
        #expect(vm.pendingCollision != nil)

        vm.confirmSaveAsNew()

        // Save-as-new must complete without a fingerprint warning,
        // even though the new profile (Home Office 2) inherits the
        // same empty fingerprint as Home Office.
        #expect(vm.pendingFingerprintWarning == nil)
        #expect(vm.didSave == true)
    }

    // MARK: - Virtual camera filtering

    @Test("hides AV Pain Reliever from the camera picker")
    func filtersVirtualCameraFromList() {
        let camera = FakeCamera(cameras: [
            "Logitech BRIO",
            "AV Pain Reliever",
            "MacBook Pro Camera",
        ])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: camera,
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            virtualCameraEnabled: true,
            onSaved: { _ in }
        )
        let names = vm.cameras.map(\.name)
        // The virtual camera is an *output*; the per-profile picker
        // is for choosing the real source camera.
        #expect(!names.contains("AV Pain Reliever"))
        #expect(names.contains("Logitech BRIO"))
        #expect(names.contains("MacBook Pro Camera"))
    }

    @Test("clears a saved camera value that points at the virtual camera (legacy profiles)")
    func sanitizesLegacyVirtualCameraSelection() {
        let editing = Profile(
            name: "home-office",
            fingerprint: [],
            camera: "AV Pain Reliever"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: ["Logitech BRIO"]),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            virtualCameraEnabled: true,
            onSaved: { _ in }
        )
        // Legacy profile shouldn't pre-fill a now-hidden value.
        #expect(vm.camera == nil)
    }

    @Test("collision Save-as-new asks the host to force-apply the new slug")
    func saveAsNewSignalsForceApply() throws {
        // Regression for the alphabetical-tiebreak bug: when the
        // wizard's collision path saves a sibling that shares its
        // fingerprint with the existing profile, ProfileResolver
        // would pick the older sibling on reload. The view model
        // signals the host (via onSaved's forceApplySlug parameter)
        // to explicitly apply the just-saved profile, bypassing the
        // resolver's tiebreak.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-saveasnew-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput  = "Existing Mic"
        audioOutput = "Existing Out"
        """.write(to: url, atomically: true, encoding: .utf8)

        var receivedForceApplySlug: String? = nil
        var sawNonForceApplyCallback = false
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["New Mic"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            existingProfileSlugs: ["home-office"],
            onSaved: { forceApplySlug in
                if let slug = forceApplySlug {
                    receivedForceApplySlug = slug
                } else {
                    sawNonForceApplyCallback = true
                }
            }
        )
        // User types the colliding name and hits Save → wizard
        // surfaces the collision dialog instead of writing.
        vm.name = "home-office"
        vm.audioInput = "New Mic"
        vm.save()
        #expect(vm.pendingCollision != nil)

        // User picks "Save as new" → wizard writes under the
        // suffixed slug AND signals force-apply on that slug.
        vm.confirmSaveAsNew()

        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)
        #expect(receivedForceApplySlug != nil)
        #expect(sawNonForceApplyCallback == false)

        // The saved profile lands under the auto-suggested
        // suffixed slug (whatever ProfileWriter picked); the
        // forceApplySlug must match what landed on disk.
        let loaded = try ConfigLoader().loadProfiles(from: url)
        let savedNames = loaded.map(\.name).sorted()
        #expect(savedNames.contains("home-office"))
        #expect(savedNames.count == 2)
        let newSlug = savedNames.first { $0 != "home-office" }
        #expect(newSlug != nil)
        #expect(receivedForceApplySlug == newSlug)
    }

    @Test("no-collision new-profile save asks the host to force-apply the new slug")
    func newProfileSaveSignalsForceApply() throws {
        // Regression for the same alphabetical-tiebreak class as the
        // collision Save-as-new bug, but on the no-collision append
        // path: when the user adds multiple profiles in a row, each
        // fingerprinting the same dock devices, the second-and-later
        // profiles share specificity with the first and lose the
        // alphabetical tiebreak. The view model now passes the new
        // slug to onSaved so the host can force-apply it.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-newprofile-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.alpha-dock]
        audioInput = "Yeti"
        """.write(to: url, atomically: true, encoding: .utf8)

        var receivedForceApplySlug: String? = nil
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Yeti"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            existingProfileSlugs: ["alpha-dock"],
            onSaved: { forceApplySlug in
                receivedForceApplySlug = forceApplySlug
            }
        )
        vm.name = "Beta Dock"
        vm.audioInput = "Yeti"
        vm.save()

        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)
        #expect(receivedForceApplySlug == "beta-dock")
    }

    @Test("edit-rename + collision Save-as-new still force-applies the new slug")
    func editRenameSaveAsNewStillForceApplies() throws {
        // Regression for a bug found while testing this branch:
        // when the user is editing profile A and renames it to B
        // (collision), then picks "Save as B-2", the wizard must
        // still pin them to B-2. The earlier scoping that gated
        // force-apply on `editingSlug == nil` was wrong for the
        // collision-dialog buttons — clicking a button there is an
        // explicit "land me on this" signal regardless of whether
        // the user got to the dialog from create-new or edit-rename.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-editrename-saveasnew-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.eric]
        audioInput = "Eric Mic"

        [profiles.studio]
        audioInput = "Studio Mic"
        """.write(to: url, atomically: true, encoding: .utf8)

        let editing = Profile(
            name: "studio",
            fingerprint: [],
            audioInput: "Studio Mic"
        )
        var receivedForceApplySlug: String? = nil
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Studio Mic"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            existingProfileSlugs: ["eric", "studio"],
            onSaved: { forceApplySlug in
                receivedForceApplySlug = forceApplySlug
            }
        )
        vm.name = "eric"
        vm.save()
        #expect(vm.pendingCollision != nil)

        vm.confirmSaveAsNew()

        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)
        // Force-apply must fire regardless of editing context — the
        // user explicitly picked "Save as new" in the dialog.
        #expect(receivedForceApplySlug != nil)
        let loaded = try ConfigLoader().loadProfiles(from: url)
        let savedNames = Set(loaded.map(\.name))
        // `studio` is gone (renamed), `eric` is unchanged, the
        // suffixed sibling exists with studio's edits.
        #expect(savedNames.contains("eric"))
        #expect(!savedNames.contains("studio"))
        let newSlug = savedNames.first { $0 != "eric" }
        #expect(receivedForceApplySlug == newSlug)
    }

    @Test("collision Update-existing asks the host to force-apply the existing slug")
    func confirmReplaceSignalsForceApply() throws {
        // Mirror of saveAsNewSignalsForceApply for the other collision
        // path: when the user picks "Update existing", the merged
        // profile's settings change but the resolver might still
        // alphabetical-tiebreak away from it (or, more commonly in
        // edit-rename, the previously-active editing profile is now
        // gone and a different sibling could win the resolver). The
        // view model passes the existing slug so the host can pin it.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-replace-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput  = "Existing Mic"
        audioOutput = "Existing Out"
        """.write(to: url, atomically: true, encoding: .utf8)

        var receivedForceApplySlug: String? = nil
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["New Mic"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            existingProfileSlugs: ["home-office"],
            onSaved: { forceApplySlug in
                receivedForceApplySlug = forceApplySlug
            }
        )
        vm.name = "home-office"
        vm.audioInput = "New Mic"
        vm.save()
        #expect(vm.pendingCollision != nil)

        vm.confirmReplace()

        #expect(vm.didSave == true)
        #expect(vm.lastError == nil)
        #expect(receivedForceApplySlug == "home-office")
    }

    @Test("collision from new-profile creation has nil editingPrettyName")
    func collisionFromNewProfileLeavesEditingNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-collision-new-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Existing Mic"
        """.write(to: url, atomically: true, encoding: .utf8)

        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            existingProfileSlugs: ["home-office"],
            onSaved: { _ in }
        )
        vm.name = "home-office"
        vm.save()
        // Wizard surfaces the collision; editingPrettyName stays nil
        // because no profile is being edited. The alert body uses
        // this to pick the "is this a different location?" wording.
        #expect(vm.pendingCollision != nil)
        #expect(vm.pendingCollision?.editingPrettyName == nil)
    }

    @Test("collision from edit-rename carries the editing profile's pretty name")
    func collisionFromEditRenameCarriesEditingName() throws {
        // Regression for the misleading-collision-dialog case: when
        // the user edits "Studio" and renames it into the existing
        // "Home Office" slug, the alert body needs to spell out that
        // BOTH paths through the dialog will delete "Studio". The
        // edit-rename signal is the editingPrettyName field — when
        // non-nil, AddProfileView renders the deletion-aware copy.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-collision-edit-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Existing Mic"

        [profiles.studio]
        audioInput = "Studio Mic"
        """.write(to: url, atomically: true, encoding: .utf8)

        let editing = Profile(
            name: "studio",
            fingerprint: [],
            audioInput: "Studio Mic"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: ["Studio Mic"]),
            cameraController: FakeCamera(cameras: []),
            configURL: url,
            editing: editing,
            existingProfileSlugs: ["home-office", "studio"],
            onSaved: { _ in }
        )
        vm.name = "home-office"
        vm.save()

        #expect(vm.pendingCollision != nil)
        #expect(vm.pendingCollision?.existingPrettyName == "Home Office")
        #expect(vm.pendingCollision?.editingPrettyName == "Studio")
    }

    // MARK: - Remembered devices (per-profile wizard pickers)

    @Test("refresh seeds the editing profile's cache ONLY from its saved selections, not from live attached devices")
    func refreshSeedsCacheFromSavedSelectionsOnly() {
        // Regression test for the seed-from-live bug: opening
        // Conference Room's wizard while a different location's
        // CalDigit was attached used to seed CalDigit into Conference
        // Room's cache, so CalDigit later appeared in Conference
        // Room's dropdown as "(not connected)" even though Conference
        // Room had never used it. Fix: only seed the editing
        // profile's saved on-disk selections; live devices already
        // appear via the live list and don't need caching.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        // CalDigit + a built-in mic are currently attached, but
        // Conference Room's saved selections reference neither.
        let audio = FakeAudio(
            inputs: ["CalDigit TS3 Audio", "MacBook Pro Microphone"],
            outputs: ["CalDigit TS3 Audio", "MacBook Pro Speakers"]
        )
        let camera = FakeCamera(cameras: ["Logitech BRIO", "Built-in"])
        let editing = Profile(
            name: "conference-room",
            fingerprint: [],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "Conference Room Speakers",
            camera: "Conference Cam"
        )
        _ = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: audio,
            cameraController: camera,
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        // Conference Room's cache contains ONLY its saved selections.
        // CalDigit is currently attached and visible in the live
        // dropdown, but it is NOT in the cache (because Conference
        // Room never saved CalDigit as a selection).
        #expect(settings.rememberedAudioInputs["conference-room"] == ["Yeti Stereo Microphone"])
        #expect(settings.rememberedAudioOutputs["conference-room"] == ["Conference Room Speakers"])
        #expect(settings.rememberedCameras["conference-room"] == ["Conference Cam"])
        #expect(settings.rememberedAudioInputs["conference-room"]?.contains("CalDigit TS3 Audio") == false)
        #expect(settings.rememberedAudioOutputs["conference-room"]?.contains("CalDigit TS3 Audio") == false)
        #expect(settings.rememberedCameras["conference-room"]?.contains("Logitech BRIO") == false)
    }

    @Test("refresh does not seed the cache when the editing profile has no saved selections")
    func refreshSkipsCacheWhenEditingProfileHasNoSelections() {
        // Brand-new-feeling editing profile (e.g. an empty-fingerprint
        // fallback) with all audio/camera fields nil. Nothing to
        // cache. The cache stays empty even though live devices are
        // attached.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let audio = FakeAudio(inputs: ["Yeti"], outputs: ["Speakers"])
        let camera = FakeCamera(cameras: ["BRIO"])
        let editing = Profile(name: "laptop", fingerprint: []) // no audioInput / output / camera
        _ = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: audio,
            cameraController: camera,
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        #expect(settings.rememberedAudioInputs["laptop"] == nil)
        #expect(settings.rememberedAudioOutputs["laptop"] == nil)
        #expect(settings.rememberedCameras["laptop"] == nil)
    }

    @Test("refresh does NOT seed the cache when adding a new profile")
    func refreshSkipsCacheWhenAdding() {
        // No editing slug ⇒ no profile-key yet ⇒ nothing to cache.
        // The "add" flow falls back to live attached devices only;
        // history builds up once the profile exists and is reopened.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        _ = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: ["Yeti"], outputs: ["Speakers"]),
            cameraController: FakeCamera(cameras: ["BRIO"]),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            settings: settings,
            onSaved: { _ in }
        )
        #expect(settings.rememberedAudioInputs.isEmpty)
        #expect(settings.rememberedAudioOutputs.isEmpty)
        #expect(settings.rememberedCameras.isEmpty)
    }

    @Test("refresh seeds the editing profile's saved selections even when not attached")
    func refreshSeedsSavedSelectionsForOfflineEdit() {
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let editing = Profile(
            name: "conference-room",
            fingerprint: [],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "Conference Room Speakers",
            camera: "Conference Cam"
        )
        // User is undocked — none of the saved devices are attached.
        _ = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: [], outputs: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        // Saved values land in this profile's cache so the next
        // refresh's disconnected-name lists include them.
        #expect(settings.rememberedAudioInputs["conference-room"] == ["Yeti Stereo Microphone"])
        #expect(settings.rememberedAudioOutputs["conference-room"] == ["Conference Room Speakers"])
        #expect(settings.rememberedCameras["conference-room"] == ["Conference Cam"])
    }

    @Test("disconnected-name lists surface this profile's remembered devices that aren't currently attached")
    func disconnectedNamesReflectMissingDevices() {
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        // Pre-seed Home Office's per-profile cache with a few names
        // in non-alphabetical order so the assertion verifies the sort
        // (not just inclusion/exclusion).
        settings.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti", "MacBook Pro Microphone", "AT2020", "MV7"],
            audioOutputs: ["CalDigit TS3 Audio", "MacBook Pro Speakers", "AirPods Pro"],
            cameras: ["Logitech BRIO", "Built-in", "AnkerWork B600"]
        )
        let editing = Profile(name: "home-office", fingerprint: [])
        // Now the user is undocked: only the laptop's built-ins are live.
        let audio = FakeAudio(
            inputs: ["MacBook Pro Microphone"],
            outputs: ["MacBook Pro Speakers"]
        )
        let camera = FakeCamera(cameras: ["Built-in"])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: audio,
            cameraController: camera,
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        // Disconnected lists carry every remembered name that's not
        // currently attached, alphabetically sorted (no
        // double-counting against live entries).
        #expect(vm.disconnectedInputNames == ["AT2020", "MV7", "Yeti"])
        #expect(vm.disconnectedOutputNames == ["AirPods Pro", "CalDigit TS3 Audio"])
        #expect(vm.disconnectedCameraNames == ["AnkerWork B600", "Logitech BRIO"])
    }

    @Test("disconnected-name lists are isolated per profile, no cross-profile leakage")
    func disconnectedNamesAreScopedPerProfile() {
        // Headline regression test for the per-profile redesign.
        // Home Office's CalDigit must NEVER show up in Conference
        // Room's dropdown.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["CalDigit TS3 Audio"],
            audioOutputs: ["CalDigit TS3 Audio"],
            cameras: ["Logitech BRIO"]
        )
        settings.rememberDevices(
            forProfile: "conference-room",
            audioInputs: ["Yeti Stereo Microphone"],
            audioOutputs: ["Conference Speakers"],
            cameras: ["Conference Cam"]
        )

        let conferenceRoom = Profile(name: "conference-room", fingerprint: [])
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: [], outputs: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: conferenceRoom,
            settings: settings,
            onSaved: { _ in }
        )
        // Only Conference Room's own remembered names appear; the
        // set-equality assertions implicitly exclude Home Office's
        // CalDigit / Logitech BRIO from the input / camera lists.
        #expect(Set(vm.disconnectedInputNames) == ["Yeti Stereo Microphone"])
        #expect(Set(vm.disconnectedOutputNames) == ["Conference Speakers"])
        #expect(Set(vm.disconnectedCameraNames) == ["Conference Cam"])
    }

    @Test("disconnected-name lists are empty when adding a new profile")
    func disconnectedNamesEmptyWhenAdding() {
        // No editing slug means there's no per-profile cache to read.
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        // Even if some OTHER profile has cached names, the "add" flow
        // doesn't see them.
        settings.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"],
            audioOutputs: [],
            cameras: []
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: ["A"], outputs: ["B"]),
            cameraController: FakeCamera(cameras: ["C"]),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            settings: settings,
            onSaved: { _ in }
        )
        #expect(vm.disconnectedInputNames.isEmpty)
        #expect(vm.disconnectedOutputNames.isEmpty)
        #expect(vm.disconnectedCameraNames.isEmpty)
    }

    @Test("disconnected-name lists are empty when no SettingsStore was injected")
    func disconnectedNamesEmptyWithoutSettings() {
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: ["A"], outputs: ["B"]),
            cameraController: FakeCamera(cameras: ["C"]),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            onSaved: { _ in }
        )
        #expect(vm.disconnectedInputNames.isEmpty)
        #expect(vm.disconnectedOutputNames.isEmpty)
        #expect(vm.disconnectedCameraNames.isEmpty)
    }

    @Test("editing while offline keeps the saved selection in the disconnected list")
    func editingOfflineExposesSavedNamesAsDisconnected() {
        let defaults = UserDefaults(suiteName: "AVPainRelieverTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let editing = Profile(
            name: "conference-room",
            fingerprint: [],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "Conference Room Speakers",
            camera: "Conference Cam"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(inputs: [], outputs: []),
            cameraController: FakeCamera(cameras: []),
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            editing: editing,
            settings: settings,
            onSaved: { _ in }
        )
        // The whole point of the feature: saved-but-disconnected
        // names show up so the user can change them.
        #expect(vm.disconnectedInputNames == ["Yeti Stereo Microphone"])
        #expect(vm.disconnectedOutputNames == ["Conference Room Speakers"])
        #expect(vm.disconnectedCameraNames == ["Conference Cam"])
        // Saved values still pre-fill the bindings.
        #expect(vm.audioInput == "Yeti Stereo Microphone")
        #expect(vm.audioOutput == "Conference Room Speakers")
        #expect(vm.camera == "Conference Cam")
    }

    @Test("currentPreferredName fallback skips the virtual camera")
    func preFillSkipsVirtualCamera() {
        // Mirrors a real machine where userPreferredCamera was set
        // to the virtual camera by ProfileApplier under the new
        // override semantics.
        let camera = FakeCamera(
            cameras: ["Logitech BRIO"],
            currentPreferred: "AV Pain Reliever"
        )
        let vm = AddProfileViewModel(
            watcher: FakeWatcher(),
            audioController: FakeAudio(devices: []),
            cameraController: camera,
            configURL: URL(fileURLWithPath: "/tmp/x.toml"),
            virtualCameraEnabled: true,
            onSaved: { _ in }
        )
        // Pre-fill should land on nil (the picker's "Don't change"
        // entry) rather than auto-selecting a value the user can't
        // see in the list.
        #expect(vm.camera == nil)
    }
}

// MARK: - Test fakes

private final class FakeWatcher: USBWatcher, @unchecked Sendable {
    var devices: Set<USBDevice> = []
    var named: [NamedUSBDevice] = []

    func currentDevices() -> Set<USBDevice> { devices }
    func currentDevicesNamed() -> [NamedUSBDevice] { named }
    func start(onChange: @escaping () -> Void) {}
    func stop() {}
}

private struct FakeAudio: AudioInventory {
    let summaries: [AudioDeviceSummary]

    /// Backwards-compatible init — every name supports both input
    /// and output. The remembered-devices tests use the explicit
    /// `inputs:`/`outputs:` init below to model real-world devices
    /// (e.g. a mic that's input-only).
    init(devices: [String]) {
        self.summaries = devices.map {
            AudioDeviceSummary(name: $0, supportsInput: true, supportsOutput: true)
        }
    }

    /// Separate input + output lists so tests can model a mic that
    /// only shows in the input picker, etc.
    init(inputs: [String], outputs: [String]) {
        var byName: [String: AudioDeviceSummary] = [:]
        for name in inputs {
            byName[name] = AudioDeviceSummary(name: name, supportsInput: true, supportsOutput: false)
        }
        for name in outputs {
            let prior = byName[name]
            byName[name] = AudioDeviceSummary(
                name: name,
                supportsInput: prior?.supportsInput ?? false,
                supportsOutput: true
            )
        }
        self.summaries = byName.values.sorted { $0.name < $1.name }
    }

    func availableDevices() -> [AudioDeviceSummary] { summaries }
    func currentDefaults() -> AudioDefaults {
        AudioDefaults(inputName: nil, outputName: nil)
    }
}

private struct FakeCamera: CameraInventory {
    let cameras: [String]
    let currentPreferred: String?

    init(cameras: [String], currentPreferred: String? = nil) {
        self.cameras = cameras
        self.currentPreferred = currentPreferred
    }

    func availableCameras() -> [CameraSummary] { cameras.map { CameraSummary(name: $0) } }
    func currentPreferredName() -> String? { currentPreferred }
}
