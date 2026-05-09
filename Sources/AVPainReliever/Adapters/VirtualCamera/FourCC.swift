import Foundation

/// Pretty-print helper for `OSType` four-character codes
/// (`kCVPixelFormatType_*`, FourCC media tags, etc.). The host's
/// capture pipeline and the CMIO sink writer both log incoming pixel
/// formats this way; centralising the conversion keeps the log
/// output consistent and avoids per-call-site byte-shift gymnastics.
enum FourCC {
    /// Render a four-character code as a 4-byte ASCII string.
    /// Returns "????" if any byte isn't printable ASCII (which
    /// shouldn't happen for real CV/CM format types — they're all
    /// human-typed FourCCs by design).
    static func pretty(_ code: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
