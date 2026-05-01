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

/// Abstraction over system audio defaults so `ProfileApplier` can be
/// unit-tested without CoreAudio. Production uses `CoreAudioController`;
/// tests use a recording mock.
public protocol AudioController {
    /// Look up an audio device by name + role and set it as the system
    /// default for that role. See `AudioApplyResult` for the four
    /// possible outcomes.
    func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult
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
