import Foundation

/// Errors thrown by `ProfileWriter`.
public enum ProfileWriteError: Error, Equatable {
    /// `name` collides with a profile that already exists in the
    /// target file. Caller decides whether to ask the user to pick a
    /// new name or replace.
    case duplicateProfile(name: String)
    /// The new profile's `name` isn't a legal TOML bare key
    /// (alphanumerics, hyphen, underscore only). Quoting would work
    /// but we keep names simple so they look clean in the file AND in
    /// the menu bar.
    case invalidName(String)
    case writeFailed(reason: String)
}

/// Appends a single new profile to an existing TOML config file
/// without rewriting the rest.
///
/// Why append-as-text rather than rewrite-from-model: the user might
/// have hand-edited the TOML to add comments, reorder profiles, or
/// document why each fingerprint device was chosen. Round-tripping
/// through `ConfigLoader` → mutate → `ConfigImporter.encodeTOML`
/// would erase all of that. Appending preserves prior content
/// verbatim, which is the right default for a config-file workflow
/// where the file IS the canonical source of truth.
///
/// If the target file doesn't exist yet, the writer creates it (and
/// any missing parent directories). The caller passes the canonical
/// header banner so a freshly-created file matches the format the
/// app's bootstrap path uses.
public struct ProfileWriter {
    public init() {}

    /// Append `profile` to the TOML file at `url`. Throws
    /// `ProfileWriteError.duplicateProfile` if a `[profiles.<name>]`
    /// section already exists. Caller is responsible for invoking
    /// the engine's `reloadConfig` to pick up the new profile.
    public func append(
        profile: Profile,
        deviceNames: [USBDevice: String?] = [:],
        to url: URL,
        startingHeader: String? = nil
    ) throws {
        let validatedName = try Self.validateName(profile.name)

        let existing: String
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                existing = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw ProfileWriteError.writeFailed(
                    reason: "couldn't read \(url.path): \(error.localizedDescription)"
                )
            }
            if Self.containsProfile(named: validatedName, in: existing) {
                throw ProfileWriteError.duplicateProfile(name: validatedName)
            }
        } else {
            existing = startingHeader ?? ""
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw ProfileWriteError.writeFailed(
                    reason: "couldn't create parent directory for \(url.path): \(error.localizedDescription)"
                )
            }
        }

        var output = existing
        if !output.isEmpty && !output.hasSuffix("\n") { output.append("\n") }
        if !output.isEmpty && !output.hasSuffix("\n\n") { output.append("\n") }
        output.append(Self.render(profile: profile, deviceNames: deviceNames))

        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ProfileWriteError.writeFailed(
                reason: "couldn't write \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Render a single profile as its TOML section. Public for tests
    /// and for the in-memory "preview the TOML" step the wizard could
    /// surface later.
    public func render(profile: Profile, deviceNames: [USBDevice: String?] = [:]) -> String {
        Self.render(profile: profile, deviceNames: deviceNames)
    }

    // MARK: - Implementation

    /// TOML bare keys allow `[A-Za-z0-9_-]+`. Profile names also need
    /// to be valid for menu-bar display + the engine's
    /// pretty-casing logic, so we apply the same restriction.
    static func validateName(_ name: String) throws -> String {
        guard !name.isEmpty else { throw ProfileWriteError.invalidName(name) }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard name.unicodeScalars.allSatisfy(allowed.contains(_:)) else {
            throw ProfileWriteError.invalidName(name)
        }
        return name
    }

    private static func containsProfile(named: String, in toml: String) -> Bool {
        // Match `[profiles.<name>]` at the start of a line, allowing
        // surrounding whitespace. Comments (preceded by `#`) don't
        // count; a #-prefixed line isn't a real section header.
        let pattern = "(?m)^[[:space:]]*\\[profiles\\.\(NSRegularExpression.escapedPattern(for: named))\\][[:space:]]*$"
        let range = NSRange(toml.startIndex..., in: toml)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return regex.firstMatch(in: toml, range: range) != nil
    }

    private static func render(profile: Profile, deviceNames: [USBDevice: String?]) -> String {
        var out = "[profiles.\(profile.name)]\n"
        if let v = profile.audioInput {
            out += "audioInput  = \(tomlString(v))\n"
        }
        if let v = profile.audioOutput {
            out += "audioOutput = \(tomlString(v))\n"
        }
        if let v = profile.obsScene {
            out += "obsScene    = \(tomlString(v))\n"
        }
        if !profile.fingerprint.isEmpty {
            out += "fingerprint = [\n"
            for d in profile.fingerprint {
                var entry = "  { "
                entry += "vendorID = 0x\(String(format: "%04x", d.vendorID)), "
                entry += "productID = 0x\(String(format: "%04x", d.productID))"
                if let name = deviceNames[d] ?? nil, !name.isEmpty {
                    entry += ", name = \(tomlString(name))"
                }
                entry += " },\n"
                out += entry
            }
            out += "]\n"
        }
        return out
    }

    private static func tomlString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
