import Foundation

/// A USB device descriptor — vendor ID, product ID, and an optional
/// serial number for disambiguating physically-identical devices at
/// different locations (e.g., two of the same LG monitor at home and
/// work).
///
/// The resolver does *asymmetric* serial matching:
///
/// - A `Profile.fingerprint` entry with a non-nil `serialNumber`
///   only matches an attached device with the same serial.
/// - A `Profile.fingerprint` entry with `serialNumber == nil`
///   matches *any* attached device with the same `(vendorID,
///   productID)`, regardless of that device's actual serial.
///
/// This keeps existing serial-less profiles working unchanged while
/// letting new profiles capture serial-specificity when the user
/// wants it (see the Add-Profile wizard, which fills in the serial
/// from IOKit when available).
///
/// Hashable/Equatable use all three fields. Two attached devices
/// with the same `(vid, pid)` but different serials are correctly
/// treated as distinct — they're different physical units.
public struct USBDevice: Hashable, Sendable {
    public let vendorID: Int
    public let productID: Int
    /// USB Serial Number string, if the device exposes one. Many
    /// devices (cheap hubs, generic peripherals) don't, so callers
    /// must tolerate `nil` everywhere.
    public let serialNumber: String?

    public init(vendorID: Int, productID: Int, serialNumber: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
    }

    /// Asymmetric "fingerprint entry → attached device" match.
    /// `self` is the fingerprint entry from a profile (whose serial
    /// may be nil to mean "any unit of this model"); `other` is the
    /// actually-attached device (whose serial is whatever IOKit
    /// reported).
    public func matchesAttachedDevice(_ other: USBDevice) -> Bool {
        guard vendorID == other.vendorID, productID == other.productID else {
            return false
        }
        // Loose match: fingerprint entry didn't pin a serial, so any
        // unit of this (vid, pid) is acceptable.
        guard let mySerial = serialNumber else { return true }
        // Strict match: serials must match exactly.
        return other.serialNumber == mySerial
    }
}
