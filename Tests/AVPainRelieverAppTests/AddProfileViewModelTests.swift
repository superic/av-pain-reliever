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
            onSaved: {}
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
            onSaved: {}
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
            onSaved: {}
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
            onSaved: {}
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
            onSaved: { saved = true }
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
            onSaved: {}
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
            onSaved: {}
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
            onSaved: {}
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
            onSaved: {}
        )
        vm.name = "Home Studio"
        vm.save()

        #expect(vm.lastError == nil)
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["home-studio"])
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

private struct FakeAudio: AudioController {
    let devices: [String]
    func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult { .ok }
    func availableDevices() -> [AudioDeviceSummary] {
        devices.map { AudioDeviceSummary(name: $0, supportsInput: true, supportsOutput: true) }
    }
    func currentDefaults() -> AudioDefaults {
        AudioDefaults(inputName: nil, outputName: nil)
    }
}

private struct FakeCamera: CameraController {
    let cameras: [String]
    func setPreferred(named: String) -> CameraApplyResult { .ok }
    func availableCameras() -> [CameraSummary] { cameras.map { CameraSummary(name: $0) } }
    func currentPreferredName() -> String? { nil }
}
