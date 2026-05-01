import Foundation

/// A USB device fingerprint — vendor ID and product ID. Matches the
/// `(vendorID, productID)` pairs the engine uses for profile resolution.
///
/// The current `init.lua` engine uses only `(vendorID, productID)` for
/// matching; serial numbers are intentionally ignored (see
/// `SWIFT_PORT.md` → "Validated design decisions"). If a future user
/// reports two distinct dock setups colliding on identical
/// `(vid, pid)` pairs, we'll add `serialNumber` here and to
/// `Profile.fingerprint`.
public struct USBDevice: Hashable, Sendable {
    public let vendorID: Int
    public let productID: Int

    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }
}
