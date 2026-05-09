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
    let devices: [String]
    func availableDevices() -> [AudioDeviceSummary] {
        devices.map { AudioDeviceSummary(name: $0, supportsInput: true, supportsOutput: true) }
    }
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
