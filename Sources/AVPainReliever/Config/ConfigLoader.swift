import Foundation
import TOMLKit

/// Errors thrown by `ConfigLoader`. All carry enough detail for the
/// menu-bar app's first-run flow to surface a useful message to the
/// user without dumping a stack trace.
public enum ConfigError: Error, Equatable {
    /// Couldn't read the file at the given path.
    case unreadable(path: String, reason: String)
    /// File contents weren't valid UTF-8.
    case notUTF8(path: String)
    /// The TOML couldn't be parsed at all.
    case malformed(reason: String)
    /// The TOML parsed but didn't match our schema.
    case schemaViolation(reason: String)
}

/// Loads `[Profile]` from a TOML config file.
///
/// Schema (lives in `~/Library/Application Support/AVPainReliever/profiles.toml`):
///
/// ```toml
/// [profiles.laptop]
/// audioInput  = "MacBook Pro Microphone"
/// audioOutput = "MacBook Pro Speakers"
/// # fingerprint omitted = empty list (always matches with specificity 0,
/// # making this profile the implicit fallback)
///
/// [profiles.home-office]
/// audioInput  = "Yeti Stereo Microphone"
/// audioOutput = "CalDigit Thunderbolt 3 Audio"
/// camera      = "LG UltraFine Display Camera"
/// fingerprint = [
///   { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
///   # `serialNumber` is optional. When present, the entry only matches
///   # that exact unit — useful when you have two of the same model at
///   # different locations (e.g., identical LG monitors at home and
///   # work). Omit it to match any unit of the (vid, pid).
///   { vendorID = 0x043e, productID = 0x9a68, serialNumber = "ABC123",
///     name = "Home LG UltraFine" },
/// ]
/// ```
///
/// All body fields are optional. Inside a fingerprint entry, `vendorID`
/// and `productID` are required; `name` is for human reading and is
/// ignored at match time. Unknown fields are silently ignored, so V1
/// reads V2-and-beyond TOML cleanly minus features it doesn't know.
///
/// The top-level `[profiles.<name>]` namespace reserves the file's top
/// level for future settings (debounce override, log path, etc.) without
/// breaking the existing schema.
public struct ConfigLoader {
    public init() {}

    /// Read and parse a TOML file at `url` into the engine's `Profile`
    /// list. Throws `ConfigError` on any failure; never crashes.
    public func loadProfiles(from url: URL) throws -> [Profile] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        guard let toml = String(data: data, encoding: .utf8) else {
            throw ConfigError.notUTF8(path: url.path)
        }
        return try parseProfiles(toml)
    }

    /// Parse a TOML string. Useful for tests and for in-memory
    /// configurations (e.g., the wizard's "preview the config" step).
    public func parseProfiles(_ toml: String) throws -> [Profile] {
        let decoder = TOMLDecoder()
        let file: ConfigFile
        do {
            file = try decoder.decode(ConfigFile.self, from: toml)
        } catch let DecodingError.dataCorrupted(context) {
            // TOMLKit surfaces parse errors as `dataCorrupted` with a
            // useful debugDescription.
            throw ConfigError.malformed(reason: context.debugDescription)
        } catch let DecodingError.keyNotFound(key, context) {
            throw ConfigError.schemaViolation(
                reason: "missing required key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch let DecodingError.typeMismatch(_, context) {
            throw ConfigError.schemaViolation(
                reason: "type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            )
        } catch {
            throw ConfigError.malformed(reason: String(describing: error))
        }
        return file.toProfiles()
    }
}

// MARK: - Codable DTOs

/// Top-level TOML shape. The `profiles` key holds a name → body
/// dictionary. Other top-level keys are tolerated (Codable's default
/// is to ignore unknown keys); this gives us forward compatibility
/// when we add app-level settings later.
private struct ConfigFile: Decodable {
    let profiles: [String: ProfileBody]?

    func toProfiles() -> [Profile] {
        guard let profiles else { return [] }
        return profiles.map { (name, body) in
            let entries = body.fingerprint ?? []
            // Build a USBDevice → display-name map from any entries
            // that carried a `name = "..."` annotation. The wizard's
            // edit form uses these to render saved-but-disconnected
            // devices with the names the user originally captured.
            var names: [USBDevice: String] = [:]
            for entry in entries {
                if let entryName = entry.name, !entryName.isEmpty {
                    names[entry.usbDevice] = entryName
                }
            }
            return Profile(
                name: name,
                fingerprint: entries.map(\.usbDevice),
                audioInput: body.audioInput,
                audioOutput: body.audioOutput,
                camera: body.camera,
                icon: body.icon,
                fingerprintNames: names
            )
        }
    }
}

private struct ProfileBody: Decodable {
    let audioInput: String?
    let audioOutput: String?
    let camera: String?
    let icon: String?
    let fingerprint: [FingerprintEntry]?
}

private struct FingerprintEntry: Decodable {
    let vendorID: Int
    let productID: Int
    /// For human reading in the config file. Ignored at match time —
    /// the resolver matches by `(vendorID, productID)` (with optional
    /// serial-number disambiguation, see below) and never by `name`.
    let name: String?
    /// Optional USB serial number. When present, the resolver
    /// matches strictly: this fingerprint entry only fires when an
    /// attached device with the same `(vid, pid)` ALSO has this
    /// exact serial. Used to disambiguate physically-identical
    /// devices at different locations (e.g., two LG monitors of the
    /// same model at home and work).
    let serialNumber: String?

    var usbDevice: USBDevice {
        USBDevice(vendorID: vendorID, productID: productID, serialNumber: serialNumber)
    }
}
