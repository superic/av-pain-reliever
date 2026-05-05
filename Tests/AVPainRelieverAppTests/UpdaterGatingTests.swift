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

    // MARK: - Experimental version classifier
    //
    // Mirrors the workflow's tag-prefix dispatch:
    // v0.0.x / v0.1.x → stable, anything else → experimental.

    @Test("0.1.x versions are stable")
    func zeroOneIsStable() {
        #expect(Updater.isExperimentalVersion("0.1.0") == false)
        #expect(Updater.isExperimentalVersion("0.1.15") == false)
    }

    @Test("0.2.x versions are experimental")
    func zeroTwoIsExperimental() {
        #expect(Updater.isExperimentalVersion("0.2.0") == true)
        #expect(Updater.isExperimentalVersion("0.2.0.2") == true)
    }

    @Test("0.0.x dryrun versions are stable")
    func zeroZeroIsStable() {
        #expect(Updater.isExperimentalVersion("0.0.0-dryrun") == false)
    }

    @Test("1.x and beyond is experimental until graduated")
    func futureMajorVersionsAreExperimental() {
        #expect(Updater.isExperimentalVersion("1.0.0") == true)
        #expect(Updater.isExperimentalVersion("2.5.7") == true)
    }

    @Test("malformed version strings classify as stable (defensive)")
    func malformedVersionsAreStable() {
        #expect(Updater.isExperimentalVersion("") == false)
        #expect(Updater.isExperimentalVersion("garbage") == false)
        #expect(Updater.isExperimentalVersion("0") == false)
    }

    @Test("iter-suffixed dev versions match their numeric prefix")
    func iterSuffixedVersionsParse() {
        #expect(Updater.isExperimentalVersion("0.2.0-iter-m3") == true)
        #expect(Updater.isExperimentalVersion("0.1.14-rc1") == false)
    }
}
