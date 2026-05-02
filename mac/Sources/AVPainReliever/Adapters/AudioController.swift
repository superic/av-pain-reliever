import Foundation
import CoreAudio

/// Default-device role — input (microphone) or output (speakers).
public enum AudioDeviceRole: String, Sendable, CaseIterable {
    case input
    case output

    fileprivate var scope: AudioObjectPropertyScope {
        switch self {
        case .input:  return kAudioDevicePropertyScopeInput
        case .output: return kAudioDevicePropertyScopeOutput
        }
    }

    fileprivate var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input:  return kAudioHardwarePropertyDefaultInputDevice
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

/// Outcome of `AudioController.setDefault(named:role:)`. The four cases
/// mirror the engine's `setAudioDevice` warning messages and let
/// `ProfileApplier` log a precise reason for any miss.
public enum AudioApplyResult: Equatable, Sendable {
    /// Device found, scope matched, default switched.
    case ok
    /// No audio device with the given name.
    case notFound
    /// A device with that name exists but doesn't have streams in the
    /// requested role (e.g. a speakers-only device passed for `.input`).
    case wrongScope
    /// Found and scoped, but the CoreAudio set call failed. Carries the
    /// `OSStatus` for diagnostics.
    case setFailed(OSStatus)
}

/// One entry in the wizard UI's audio-device picker. CoreAudio
/// sometimes splits a single physical device across multiple
/// `AudioDeviceID`s (e.g., CalDigit appears once as input-only and
/// once as output-only); the summary merges by name and ORs the
/// capability flags so the picker shows one row per real-world
/// device with both checkboxes available.
public struct AudioDeviceSummary: Hashable, Sendable, Identifiable {
    public let name: String
    public let supportsInput: Bool
    public let supportsOutput: Bool

    public init(name: String, supportsInput: Bool, supportsOutput: Bool) {
        self.name = name
        self.supportsInput = supportsInput
        self.supportsOutput = supportsOutput
    }

    public var id: String { name }
}

/// Names of the system's currently-set default input + output
/// devices. Used by the wizard to pre-select "what's currently
/// active" so users capturing a new profile don't have to repeat
/// audio choices they already made manually.
public struct AudioDefaults: Sendable {
    public let inputName: String?
    public let outputName: String?

    public init(inputName: String?, outputName: String?) {
        self.inputName = inputName
        self.outputName = outputName
    }
}

/// Abstraction over system audio defaults so `ProfileApplier` can be
/// unit-tested without CoreAudio. Production uses `CoreAudioController`;
/// tests use a recording mock.
public protocol AudioController {
    /// Look up an audio device by name + role and set it as the system
    /// default for that role. See `AudioApplyResult` for the four
    /// possible outcomes.
    func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult

    /// Snapshot of available audio devices, deduplicated by name with
    /// merged input/output capabilities. Used by the wizard UI to
    /// populate audio pickers.
    func availableDevices() -> [AudioDeviceSummary]

    /// Names of the system's currently-set default input + output.
    /// Either side may be nil if CoreAudio has no default for that
    /// scope (rare on macOS but defensible).
    func currentDefaults() -> AudioDefaults
}

/// Production `AudioController` backed by raw CoreAudio. Lifted from
/// `prototypes/audio-defaults.swift` once that prototype proved the
/// read+write surface works end to end (see `SWIFT_PORT.md` →
/// "CoreAudio prototype findings").
///
/// Stateless — every call re-enumerates devices. CoreAudio's
/// `kAudioHardwarePropertyDevices` is fast (microseconds), so caching
/// would buy nothing and risk stale data when devices come and go.
public struct CoreAudioController: AudioController {
    public init() {}

    public func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult {
        // CoreAudio occasionally splits a single physical device into
        // separate AudioDeviceIDs (one per scope) — see the engine's
        // `--- audio devices ---` log block, where CalDigit, Yeti, and
        // LG UltraFine each show up twice. Filter by name first, then
        // by scope, so a "Yeti" name match doesn't accidentally pick
        // the output side when we asked for input.
        let nameMatches = Self.allDeviceIDs().filter { Self.deviceName($0) == named }
        if nameMatches.isEmpty {
            return .notFound
        }
        guard let id = nameMatches.first(where: { Self.hasStreams($0, scope: role.scope) }) else {
            return .wrongScope
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: role.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = id
        let kr = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &device
        )
        return kr == noErr ? .ok : .setFailed(kr)
    }

    public func currentDefaults() -> AudioDefaults {
        AudioDefaults(
            inputName: Self.defaultDeviceName(for: .input),
            outputName: Self.defaultDeviceName(for: .output)
        )
    }

    private static func defaultDeviceName(for role: AudioDeviceRole) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: role.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        let name = Self.deviceName(deviceID)
        return name.isEmpty ? nil : name
    }

    public func availableDevices() -> [AudioDeviceSummary] {
        var byName: [String: AudioDeviceSummary] = [:]
        for id in Self.allDeviceIDs() {
            let name = Self.deviceName(id)
            guard !name.isEmpty else { continue }
            let inputs = Self.hasStreams(id, scope: kAudioDevicePropertyScopeInput)
            let outputs = Self.hasStreams(id, scope: kAudioDevicePropertyScopeOutput)
            let prior = byName[name]
            byName[name] = AudioDeviceSummary(
                name: name,
                supportsInput: (prior?.supportsInput ?? false) || inputs,
                supportsOutput: (prior?.supportsOutput ?? false) || outputs
            )
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    // MARK: - CoreAudio plumbing

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        var resultSize = size
        let kr = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &resultSize, &ids
        )
        return kr == noErr ? ids : []
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let kr = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        guard kr == noErr, let cf = name?.takeRetainedValue() else { return "" }
        return cf as String
    }

    private static func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }
}
