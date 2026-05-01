import Foundation

/// Errors thrown by `ConfigImporter`.
public enum ImporterError: Error, Equatable {
    /// The Lua source didn't match the shape `profiles.lua` is expected
    /// to have (a single `return { ... }` table of `["name"] = { ... }`
    /// entries). The reason is human-readable.
    case syntax(reason: String)
    /// A fingerprint entry was missing a required key (`vendorID` or
    /// `productID`).
    case missingFingerprintField(profile: String, field: String)
}

/// One-shot converter from the Hammerspoon engine's `profiles.lua` to
/// the Swift app's TOML schema. Used by the menu-bar app's first-run
/// wizard to bootstrap a `profiles.toml` from a user's existing
/// Hammerspoon setup, so they don't have to retype location names,
/// audio device names, OBS scene names, or USB fingerprints.
///
/// The implementation is **not** a general Lua parser: it targets the
/// well-defined shape that Phase 1's `wizard.sh` produces (and that
/// users hand-edit). That gets us a robust enough conversion in ~150
/// lines instead of the ~500+ a full Lua parser would need. If users
/// hand-write profiles outside that shape, the importer will reject
/// them with a `.syntax` error and fall through to the "create from
/// scratch" wizard path.
///
/// Recognized shape:
///
/// ```lua
/// -- comments allowed anywhere
/// return {
///   ["profile-name"] = {
///     fingerprint = {
///       { vendorID = 0x..., productID = 0x..., name = "..." },  -- name optional
///       ...
///     },
///     audioInput  = "...",      -- optional
///     audioOutput = "...",      -- optional
///     obsScene    = "...",      -- optional
///   },
///   ...
/// }
/// ```
public struct ConfigImporter {
    /// Literal placeholder string the Phase 1 wizard writes for
    /// audio fields when generating a profile stub the user hasn't
    /// configured yet (work-office, conference-room, etc.).
    /// Profiles with this value in either audio field are filtered
    /// out by `parse(_:)` and `convertToTOML(_:)` so they don't
    /// shadow real profiles in the resolver's alphabetical
    /// tiebreak.
    private static let unconfiguredPlaceholder = "FILL ME IN"

    public init() {}

    /// Parse Lua into the engine's `Profile` model. Drops fingerprint
    /// device names (the resolver doesn't use them) AND drops profiles
    /// the wizard generated as `FILL ME IN` stubs that the user hasn't
    /// filled in yet — those would otherwise shadow `laptop`
    /// alphabetically when undocked, since both have empty
    /// fingerprints with specificity 0.
    /// For the name-preserving path, use `convertToTOML` instead.
    /// Use `parseAll(_:)` if you specifically want unconfigured stubs
    /// included (tests, diagnostic tools).
    public func parse(_ luaSource: String) throws -> [Profile] {
        try parseImported(luaSource)
            .filter(Self.isConfigured)
            .map(\.profile)
    }

    /// Like `parse(_:)` but does NOT filter `FILL ME IN` stubs.
    /// Useful for diagnostics ("which profiles in the config are
    /// unconfigured?") and for tests.
    public func parseAll(_ luaSource: String) throws -> [Profile] {
        try parseImported(luaSource).map(\.profile)
    }

    /// Convert Lua source into a TOML string matching `ConfigLoader`'s
    /// schema. Preserves fingerprint device names (the schema's
    /// optional `name` field). Drops `FILL ME IN` stubs, same as
    /// `parse(_:)` — emitting them into the TOML would just propagate
    /// the bug to the new format.
    public func convertToTOML(_ luaSource: String) throws -> String {
        let profiles = try parseImported(luaSource).filter(Self.isConfigured)
        return encodeTOML(profiles)
    }

    private static func isConfigured(_ profile: ImportedProfile) -> Bool {
        if profile.audioInput == unconfiguredPlaceholder { return false }
        if profile.audioOutput == unconfiguredPlaceholder { return false }
        return true
    }

    /// Render a `[Profile]` list as TOML matching `ConfigLoader`'s
    /// schema. No device names (the engine model doesn't carry them);
    /// use `convertToTOML` if you need them.
    public func encodeTOML(_ profiles: [Profile]) -> String {
        encodeTOML(profiles.map { ImportedProfile(profile: $0) })
    }

    // MARK: - Lua parse

    private func parseImported(_ luaSource: String) throws -> [ImportedProfile] {
        let stripped = stripComments(luaSource)
        guard let returnRange = stripped.range(of: "return") else {
            throw ImporterError.syntax(reason: "no `return` keyword found")
        }
        let afterReturn = stripped[returnRange.upperBound...]
        guard let openBrace = afterReturn.firstIndex(of: "{") else {
            throw ImporterError.syntax(reason: "no `{` after `return`")
        }
        let bodyStart = afterReturn.index(after: openBrace)
        // Find the matching outer `}`.
        let bodyEnd = try matchingClosingBrace(in: afterReturn, openAt: openBrace)

        let body = afterReturn[bodyStart..<bodyEnd]
        return try parseProfileEntries(in: body)
    }

    private func parseProfileEntries(in body: Substring) throws -> [ImportedProfile] {
        var profiles: [ImportedProfile] = []
        var i = body.startIndex
        while let header = nextProfileHeader(in: body, from: i) {
            // header.bodyOpenBrace points at the `{` opening the profile
            // body. Find the matching `}`.
            let close = try matchingClosingBrace(in: body, openAt: header.bodyOpenBrace)
            let profileBody = body[body.index(after: header.bodyOpenBrace)..<close]
            let profile = try parseProfileBody(name: header.name, body: profileBody)
            profiles.append(profile)
            i = body.index(after: close)
        }
        return profiles
    }

    private struct ProfileHeader {
        let name: String
        let bodyOpenBrace: Substring.Index
    }

    /// Find the next `["name"] = {` profile header from `start`.
    /// Returns nil when no more headers exist in the slice.
    private func nextProfileHeader(in body: Substring, from start: Substring.Index) -> ProfileHeader? {
        // Regex: \[\s*"([^"]+)"\s*\]\s*=\s*\{
        // We can't use NSRegularExpression cleanly with Substring; do a
        // small scan instead.
        var i = start
        while i < body.endIndex {
            guard body[i] == "[" else {
                i = body.index(after: i)
                continue
            }
            // Try to match `[ "..." ] = {`.
            var j = body.index(after: i)
            j = skipWhitespace(in: body, from: j)
            guard j < body.endIndex, body[j] == "\"" else {
                i = body.index(after: i); continue
            }
            let nameStart = body.index(after: j)
            guard let nameEnd = body[nameStart...].firstIndex(of: "\"") else {
                return nil
            }
            let name = String(body[nameStart..<nameEnd])
            j = body.index(after: nameEnd)
            j = skipWhitespace(in: body, from: j)
            guard j < body.endIndex, body[j] == "]" else {
                i = body.index(after: i); continue
            }
            j = body.index(after: j)
            j = skipWhitespace(in: body, from: j)
            guard j < body.endIndex, body[j] == "=" else {
                i = body.index(after: i); continue
            }
            j = body.index(after: j)
            j = skipWhitespace(in: body, from: j)
            guard j < body.endIndex, body[j] == "{" else {
                i = body.index(after: i); continue
            }
            return ProfileHeader(name: name, bodyOpenBrace: j)
        }
        return nil
    }

    private func parseProfileBody(name: String, body: Substring) throws -> ImportedProfile {
        let audioInput = extractStringField("audioInput", in: body)
        let audioOutput = extractStringField("audioOutput", in: body)
        let obsScene = extractStringField("obsScene", in: body)
        let fingerprint = try extractFingerprint(in: body, profileName: name)
        return ImportedProfile(
            name: name,
            fingerprint: fingerprint,
            audioInput: audioInput,
            audioOutput: audioOutput,
            obsScene: obsScene
        )
    }

    /// Match `<key> = "..."` inside the slice. Honors backslash-escaped
    /// quotes (`\"`) inside the string literal.
    private func extractStringField(_ key: String, in body: Substring) -> String? {
        guard let keyRange = body.range(of: key) else { return nil }
        var i = keyRange.upperBound
        i = skipWhitespace(in: body, from: i)
        guard i < body.endIndex, body[i] == "=" else { return nil }
        i = body.index(after: i)
        i = skipWhitespace(in: body, from: i)
        guard i < body.endIndex, body[i] == "\"" else { return nil }
        let valueStart = body.index(after: i)
        var j = valueStart
        while j < body.endIndex {
            let c = body[j]
            if c == "\\" {
                let after = body.index(after: j)
                if after < body.endIndex {
                    j = body.index(after: after)
                    continue
                }
            }
            if c == "\"" {
                let raw = String(body[valueStart..<j])
                return unescapeLuaString(raw)
            }
            j = body.index(after: j)
        }
        return nil
    }

    private func extractFingerprint(
        in body: Substring,
        profileName: String
    ) throws -> [ImportedDevice] {
        guard let kRange = body.range(of: "fingerprint") else { return [] }
        var i = kRange.upperBound
        i = skipWhitespace(in: body, from: i)
        guard i < body.endIndex, body[i] == "=" else { return [] }
        i = body.index(after: i)
        i = skipWhitespace(in: body, from: i)
        guard i < body.endIndex, body[i] == "{" else { return [] }
        let close = try matchingClosingBrace(in: body, openAt: i)
        let inner = body[body.index(after: i)..<close]

        var entries: [ImportedDevice] = []
        var j = inner.startIndex
        while j < inner.endIndex {
            j = skipWhitespace(in: inner, from: j)
            guard j < inner.endIndex else { break }
            if inner[j] == "," {
                j = inner.index(after: j); continue
            }
            guard inner[j] == "{" else {
                // A non-`{` token here means malformed input. Skip
                // forward to next `,` or `{` to be tolerant of weird
                // whitespace.
                j = inner.index(after: j); continue
            }
            let entryClose = try matchingClosingBrace(in: inner, openAt: j)
            let entryBody = inner[inner.index(after: j)..<entryClose]
            let device = try parseFingerprintEntry(entryBody, profileName: profileName)
            entries.append(device)
            j = inner.index(after: entryClose)
        }
        return entries
    }

    private func parseFingerprintEntry(
        _ entryBody: Substring,
        profileName: String
    ) throws -> ImportedDevice {
        let vid = extractIntField("vendorID", in: entryBody)
        let pid = extractIntField("productID", in: entryBody)
        let name = extractStringField("name", in: entryBody)
        guard let vid else {
            throw ImporterError.missingFingerprintField(profile: profileName, field: "vendorID")
        }
        guard let pid else {
            throw ImporterError.missingFingerprintField(profile: profileName, field: "productID")
        }
        return ImportedDevice(vendorID: vid, productID: pid, name: name)
    }

    private func extractIntField(_ key: String, in body: Substring) -> Int? {
        guard let kRange = body.range(of: key) else { return nil }
        var i = kRange.upperBound
        i = skipWhitespace(in: body, from: i)
        guard i < body.endIndex, body[i] == "=" else { return nil }
        i = body.index(after: i)
        i = skipWhitespace(in: body, from: i)
        // Try hex first: `0x` or `0X`.
        if i < body.endIndex, body[i] == "0",
           body.index(after: i) < body.endIndex,
           body[body.index(after: i)] == "x" || body[body.index(after: i)] == "X"
        {
            let hexStart = body.index(i, offsetBy: 2)
            var j = hexStart
            while j < body.endIndex, body[j].isHexDigit {
                j = body.index(after: j)
            }
            return Int(body[hexStart..<j], radix: 16)
        }
        // Decimal.
        var j = i
        while j < body.endIndex, body[j].isNumber {
            j = body.index(after: j)
        }
        return j > i ? Int(body[i..<j]) : nil
    }

    // MARK: - Lua plumbing

    /// Strip Lua line comments (`-- ...` to end of line) outside string
    /// literals. Block comments (`--[[ ... ]]`) are not handled because
    /// the wizard never produces them and supporting them isn't worth
    /// the parser complexity.
    private func stripComments(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var inString = false
        var i = source.startIndex
        while i < source.endIndex {
            let c = source[i]
            if inString {
                out.append(c)
                if c == "\\" {
                    let n = source.index(after: i)
                    if n < source.endIndex {
                        out.append(source[n])
                        i = source.index(after: n)
                        continue
                    }
                }
                if c == "\"" { inString = false }
                i = source.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = source.index(after: i)
                continue
            }
            if c == "-",
               source.index(after: i) < source.endIndex,
               source[source.index(after: i)] == "-"
            {
                // Line comment — skip to newline (preserve it so line
                // numbers don't shift, helps any future error messages).
                while i < source.endIndex, source[i] != "\n" {
                    i = source.index(after: i)
                }
                continue
            }
            out.append(c)
            i = source.index(after: i)
        }
        return out
    }

    private func skipWhitespace<S: StringProtocol>(in s: S, from start: S.Index) -> S.Index {
        var i = start
        while i < s.endIndex, s[i].isWhitespace {
            i = s.index(after: i)
        }
        return i
    }

    /// Find the `}` that matches the `{` at `openAt`, tracking nesting.
    /// Honors string literals so braces inside `"..."` don't confuse
    /// the depth counter.
    private func matchingClosingBrace<S: StringProtocol>(
        in s: S,
        openAt: S.Index
    ) throws -> S.Index {
        var depth = 0
        var i = openAt
        var inString = false
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if c == "\\", s.index(after: i) < s.endIndex {
                    i = s.index(after: s.index(after: i))
                    continue
                }
                if c == "\"" { inString = false }
                i = s.index(after: i)
                continue
            }
            switch c {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
            i = s.index(after: i)
        }
        throw ImporterError.syntax(reason: "unbalanced braces — no matching `}` for `{`")
    }

    private func unescapeLuaString(_ raw: String) -> String {
        // Lua's escape set overlaps with TOML's enough that we just
        // handle the four common ones: \", \\, \n, \t. Anything else
        // passes through unchanged.
        var out = ""
        out.reserveCapacity(raw.count)
        var i = raw.startIndex
        while i < raw.endIndex {
            let c = raw[i]
            if c == "\\", raw.index(after: i) < raw.endIndex {
                let next = raw[raw.index(after: i)]
                switch next {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "n":  out.append("\n")
                case "t":  out.append("\t")
                default:   out.append(next)
                }
                i = raw.index(i, offsetBy: 2)
                continue
            }
            out.append(c)
            i = raw.index(after: i)
        }
        return out
    }

    // MARK: - TOML emit

    private func encodeTOML(_ profiles: [ImportedProfile]) -> String {
        // Stable output for diffability — sort by profile name.
        let sorted = profiles.sorted { $0.name < $1.name }
        return sorted.map(encodeProfile).joined(separator: "\n")
    }

    private func encodeProfile(_ profile: ImportedProfile) -> String {
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
                entry += "vendorID = 0x\(hex4(d.vendorID)), "
                entry += "productID = 0x\(hex4(d.productID))"
                if let name = d.name {
                    entry += ", name = \(tomlString(name))"
                }
                entry += " },\n"
                out += entry
            }
            out += "]\n"
        }
        return out
    }

    private func hex4(_ n: Int) -> String {
        String(format: "%04x", n)
    }

    private func tomlString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - Internal richer model

private struct ImportedProfile {
    let name: String
    let fingerprint: [ImportedDevice]
    let audioInput: String?
    let audioOutput: String?
    let obsScene: String?

    init(
        name: String,
        fingerprint: [ImportedDevice],
        audioInput: String?,
        audioOutput: String?,
        obsScene: String?
    ) {
        self.name = name
        self.fingerprint = fingerprint
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.obsScene = obsScene
    }

    init(profile: Profile) {
        self.name = profile.name
        self.fingerprint = profile.fingerprint.map {
            ImportedDevice(vendorID: $0.vendorID, productID: $0.productID, name: nil)
        }
        self.audioInput = profile.audioInput
        self.audioOutput = profile.audioOutput
        self.obsScene = profile.obsScene
    }

    var profile: Profile {
        Profile(
            name: name,
            fingerprint: fingerprint.map { USBDevice(vendorID: $0.vendorID, productID: $0.productID) },
            audioInput: audioInput,
            audioOutput: audioOutput,
            obsScene: obsScene
        )
    }
}

private struct ImportedDevice {
    let vendorID: Int
    let productID: Int
    let name: String?
}
