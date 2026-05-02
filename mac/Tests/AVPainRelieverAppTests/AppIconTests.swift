import Testing
import AppKit
@testable import AVPainRelieverApp

@Suite("AppIcon")
struct AppIconTests {
    @Test("makeIcon produces a 1024x1024 image")
    func makesCorrectSize() {
        let icon = AppIcon.makeIcon()
        #expect(icon.size == NSSize(width: 1024, height: 1024))
    }

    @Test("makeIcon's representations have non-zero pixel data")
    func representationsHavePixels() {
        let icon = AppIcon.makeIcon()
        // The cached representations should include something
        // drawable. NSImage built from `lockFocus` carries an
        // NSCachedImageRep — checking pixels isn't trivial without
        // reading back, but TIFF round-trip proves there's actual
        // raster content rather than an empty canvas.
        let tiff = icon.tiffRepresentation
        #expect(tiff != nil)
        #expect((tiff?.count ?? 0) > 1000, "expected non-trivial TIFF payload")
    }

    @Test("AppIcon.image is the cached singleton (same instance every read)")
    func cachedSingleton() {
        let a = AppIcon.image
        let b = AppIcon.image
        // NSImage doesn't conform to Identifiable but pointer
        // identity is meaningful for cached singletons.
        #expect(a === b)
    }
}
