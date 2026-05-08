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
/// through `ConfigLoader` → mutate → re-encode would erase all of
/// that. Appending preserves prior content verbatim, which is the
/// right default for a config-file workflow where the file IS the
/// canonical source of truth.
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

    /// True if a `[profiles.<name>]` section already exists in the
    /// file at `url`. Returns false if the file doesn't exist or
    /// can't be read.
    public func profileExists(named name: String, in url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return Self.containsProfile(named: name, in: content)
    }

    /// Find the first available `<base>-<n>` slug that doesn't collide
    /// with an existing profile in the file. Returns `base` itself if
    /// nothing collides. Used by the wizard's "Save as new" path
    /// after a duplicate-name dialog.
    public func nextAvailableName(base: String, in url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return base
        }
        if !Self.containsProfile(named: base, in: content) { return base }
        var n = 2
        while Self.containsProfile(named: "\(base)-\(n)", in: content) {
            n += 1
        }
        return "\(base)-\(n)"
    }

    /// Remove the `[profiles.<name>]` section from the TOML file at
    /// `url`. The section header line through everything before the
    /// next `[...]` section (or end of file) is excised; surrounding
    /// content (other profiles, header banner, comments) is preserved.
    /// Throws `.duplicateProfile` (re-using the "expected this section
    /// to be present, it wasn't" code path) when the section is
    /// missing — the caller has already established it's there, so
    /// missing means a concurrent edit raced us.
    public func delete(named name: String, in url: URL) throws {
        let validatedName = try Self.validateName(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileWriteError.writeFailed(reason: "no file to edit at \(url.path)")
        }
        let existing: String
        do {
            existing = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ProfileWriteError.writeFailed(
                reason: "couldn't read \(url.path): \(error.localizedDescription)"
            )
        }
        guard let span = Self.sectionRange(named: validatedName, in: existing) else {
            throw ProfileWriteError.duplicateProfile(name: validatedName)
        }
        var output = existing
        output.replaceSubrange(span, with: "")
        // Trailing whitespace from a removed-last-section can leave a
        // blank tail; tidy that up so the file looks clean.
        while output.hasSuffix("\n\n\n") {
            output.removeLast()
        }
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ProfileWriteError.writeFailed(
                reason: "couldn't write \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Replace an existing `[profiles.<name>]` section's body with the
    /// rendered output for `profile`. The section header line through
    /// the line just before the next `[...]` section (or end of file)
    /// is overwritten in place; everything else in the file is
    /// preserved verbatim.
    ///
    /// `profile.name` must equal the existing section's name — the
    /// caller has already established this is the section to replace.
    /// Throws `.duplicateProfile` if no matching section is found
    /// (use `append` for the new-profile case).
    public func replace(
        profile: Profile,
        deviceNames: [USBDevice: String?] = [:],
        in url: URL
    ) throws {
        let validatedName = try Self.validateName(profile.name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileWriteError.writeFailed(reason: "no file to replace at \(url.path)")
        }
        let existing: String
        do {
            existing = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ProfileWriteError.writeFailed(
                reason: "couldn't read \(url.path): \(error.localizedDescription)"
            )
        }
        guard let span = Self.sectionRange(named: validatedName, in: existing) else {
            // Caller invariant: replace assumes the section is there.
            // Surface this as duplicateProfile-shaped because the
            // higher-level wizard already routed here based on a
            // collision check; if the file changed under us, fall
            // back to caller-handled flow.
            throw ProfileWriteError.duplicateProfile(name: validatedName)
        }
        let rendered = Self.render(profile: profile, deviceNames: deviceNames)
        var output = existing
        output.replaceSubrange(span, with: rendered)

        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ProfileWriteError.writeFailed(
                reason: "couldn't write \(url.path): \(error.localizedDescription)"
            )
        }
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

    /// Find the file range covering an existing `[profiles.<name>]`
    /// section: from the section header line through everything before
    /// the next `[...]` line (or to end of file). Returns nil if no
    /// matching section is found.
    private static func sectionRange(named: String, in toml: String) -> Range<String.Index>? {
        let headerPattern = "(?m)^[[:space:]]*\\[profiles\\.\(NSRegularExpression.escapedPattern(for: named))\\][[:space:]]*$"
        let nsRange = NSRange(toml.startIndex..., in: toml)
        guard let headerRegex = try? NSRegularExpression(pattern: headerPattern),
              let headerMatch = headerRegex.firstMatch(in: toml, range: nsRange),
              let headerRange = Range(headerMatch.range, in: toml) else {
            return nil
        }
        // Scan from after the header line for the next line that
        // starts with `[`. That's the start of the next section, OR
        // end of file.
        let afterHeader = headerRange.upperBound
        let afterRange = NSRange(afterHeader..<toml.endIndex, in: toml)
        let nextSectionPattern = "(?m)^[[:space:]]*\\["
        if let nextRegex = try? NSRegularExpression(pattern: nextSectionPattern),
           let nextMatch = nextRegex.firstMatch(in: toml, range: afterRange),
           let nextRange = Range(nextMatch.range, in: toml) {
            return headerRange.lowerBound..<nextRange.lowerBound
        }
        // No next section — span runs to EOF.
        return headerRange.lowerBound..<toml.endIndex
    }

    private static func render(profile: Profile, deviceNames: [USBDevice: String?]) -> String {
        var out = "[profiles.\(profile.name)]\n"
        if let v = profile.audioInput {
            out += "audioInput  = \(tomlString(v))\n"
        }
        if let v = profile.audioOutput {
            out += "audioOutput = \(tomlString(v))\n"
        }
        if let v = profile.camera {
            out += "camera      = \(tomlString(v))\n"
        }
        if let v = profile.icon {
            out += "icon        = \(tomlString(v))\n"
        }
        if !profile.fingerprint.isEmpty {
            out += "fingerprint = [\n"
            for d in profile.fingerprint {
                var entry = "  { "
                entry += "vendorID = 0x\(String(format: "%04x", d.vendorID)), "
                entry += "productID = 0x\(String(format: "%04x", d.productID))"
                if let serial = d.serialNumber, !serial.isEmpty {
                    entry += ", serialNumber = \(tomlString(serial))"
                }
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
