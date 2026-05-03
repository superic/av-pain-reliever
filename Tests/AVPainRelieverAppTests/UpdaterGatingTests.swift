import Testing
@testable import AVPainRelieverApp

/// Cover every branch of `Updater.shouldEnable` so a regression in
/// the placeholder-detection logic can't ship silently. The cost of
/// getting this wrong is high: a placeholder slipping into a
/// release tag means Sparkle initializes against an invalid key and
/// pops "Unable to Check For Updates" at every user. That happened
/// in pre-v0.1.0 dev builds (see SWIFT_PORT.md "Lessons learned"),
/// which is why the gate exists at all.
@Suite("Updater gating")
struct UpdaterGatingTests {
    private let realKey = "0V1/jYajWQAtQxno6owk8+uWtbun2DjHy/j/o2pLPSQ="
    private let realBundle = Updater.expectedBundleIdentifier

    @Test("real release: matching bundle ID + real key → enabled")
    func enablesInRealRelease() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: realBundle,
            publicKey: realKey
        ) == true)
    }

    @Test("running via swift run: nil bundle ID → disabled")
    func disabledWithoutBundle() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: nil,
            publicKey: realKey
        ) == false)
    }

    @Test("foreign bundle ID → disabled even with a real-looking key")
    func disabledWithWrongBundle() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: "com.example.unrelated",
            publicKey: realKey
        ) == false)
    }

    @Test("unfinished release: __SPARKLE_PUBLIC_KEY__ placeholder → disabled")
    func disabledWithPlaceholderKey() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: realBundle,
            publicKey: Updater.publicKeyPlaceholder
        ) == false)
    }

    @Test("empty key → disabled")
    func disabledWithEmptyKey() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: realBundle,
            publicKey: ""
        ) == false)
    }

    @Test("nil key → disabled")
    func disabledWithNilKey() {
        #expect(Updater.shouldEnable(
            bundleIdentifier: realBundle,
            publicKey: nil
        ) == false)
    }

    @Test("placeholder constant matches what the build pipeline expects")
    func placeholderMatchesBuildPipeline() {
        // Resources/Info.plist ships __SPARKLE_PUBLIC_KEY__ as the
        // pre-Phase-4 placeholder. If anyone renames that constant
        // they must update both places. This guard catches the drift.
        #expect(Updater.publicKeyPlaceholder == "__SPARKLE_PUBLIC_KEY__")
    }
}
