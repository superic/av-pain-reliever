import Testing
import Foundation
@testable import AVPainReliever
@testable import AVPainRelieverApp

@Suite("SettingsStore")
struct SettingsStoreTests {
    /// A throwaway UserDefaults suite so each test starts clean.
    /// Built fresh per test to avoid cross-test interference.
    private func makeSuite() -> UserDefaults {
        let suiteName = "AVPainRelieverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("defaults match the locked product behavior")
    func defaultsAreCorrect() {
        let store = SettingsStore(defaults: makeSuite())
        #expect(store.notificationsEnabled == true)
        #expect(store.showProfileNameInMenuBar == true)
        #expect(store.debounceInterval == 1.5)
        #expect(store.profileSwitchCount == 0)
        #expect(store.suppressedWelcome == false)
        // Launch-at-login defaults off — fresh users opt in, per
        // macOS background-task etiquette.
        #expect(store.launchAtLogin == false)
        // Virtual camera defaults off — installs a system extension,
        // so opt-in is mandatory both for principle and for
        // notarization etiquette.
        #expect(store.virtualCameraEnabled == false)
        // Experimental updates default off — only the stable channel
        // is consumed unless the user explicitly opts in.
        #expect(store.experimentalUpdates == false)
        // Stats tracking ships off — privacy-first default. All
        // counter / dictionary fields stay empty until the user opts in.
        #expect(store.statsTrackingEnabled == false)
        #expect(store.statsStartDate == nil)
        #expect(store.perProfileCounts.isEmpty)
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
        #expect(store.manualOverrideCount == 0)
        #expect(store.currentStreakDays == 0)
        #expect(store.longestStreakDays == 0)
        #expect(store.activeDaysCount == 0)
        #expect(store.uniqueDevicesSeenCount == 0)
    }

    @Test("launchAtLogin persists across reloads")
    func launchAtLoginPersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.launchAtLogin = true
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.launchAtLogin == true)
    }

    @Test("flipping a default-on toggle to false survives a reload")
    func togglePersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.notificationsEnabled = false
        }
        // Re-create against the same UserDefaults to simulate restart.
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.notificationsEnabled == false)
    }

    @Test("debounce interval persists across reloads")
    func debouncePersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.debounceInterval = 2.5
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.debounceInterval == 2.5)
    }

    @Test("incrementSwitchCount persists across reloads when tracking is enabled")
    func switchCountIncrements() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.statsTrackingEnabled = true
            store.incrementSwitchCount()
            store.incrementSwitchCount()
            store.incrementSwitchCount()
            #expect(store.profileSwitchCount == 3)
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.profileSwitchCount == 3)
    }

    @Test("suppressedWelcome persists once flipped")
    func welcomeSuppressionPersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.suppressedWelcome = true
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.suppressedWelcome == true)
    }

    @Test("virtualCameraEnabled persists across reloads")
    func virtualCameraEnabledPersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.virtualCameraEnabled = true
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.virtualCameraEnabled == true)
    }

    @Test("experimentalUpdates persists across reloads")
    func experimentalUpdatesPersists() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.experimentalUpdates = true
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.experimentalUpdates == true)
    }

    // MARK: - Stats tracking

    @Test("with tracking off, every record/increment method is a no-op")
    func gatedMethodsNoOpWhenDisabled() {
        let store = SettingsStore(defaults: makeSuite())
        // Default state: tracking off.
        #expect(store.statsTrackingEnabled == false)

        store.incrementSwitchCount()
        store.incrementManualOverrideCount()
        store.recordSwitch(toSlug: "home-office")
        store.recordDevicesSeen([USBDevice(vendorID: 0x2188, productID: 0x6533)])

        #expect(store.profileSwitchCount == 0)
        #expect(store.manualOverrideCount == 0)
        #expect(store.perProfileCounts.isEmpty)
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
        #expect(store.currentStreakDays == 0)
        #expect(store.longestStreakDays == 0)
        #expect(store.activeDaysCount == 0)
        #expect(store.uniqueDevicesSeenCount == 0)
    }

    @Test("first opt-in stamps statsStartDate; toggling off-on does not re-stamp")
    func optInStampsStartDateOnce() {
        let store = SettingsStore(defaults: makeSuite())
        #expect(store.statsStartDate == nil)

        let beforeFirst = Date()
        store.statsTrackingEnabled = true
        let stampedFirst = store.statsStartDate
        #expect(stampedFirst != nil)
        // Stamp must be at-or-after the pre-flip moment.
        #expect((stampedFirst ?? .distantPast) >= beforeFirst)

        // Off → on again: should NOT re-stamp.
        store.statsTrackingEnabled = false
        store.statsTrackingEnabled = true
        #expect(store.statsStartDate == stampedFirst)
    }

    @Test("recordSwitch updates per-profile counts and last-switch fields")
    func recordSwitchUpdatesBasics() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true

        let t = Date()
        store.recordSwitch(toSlug: "home-office", at: t)
        store.recordSwitch(toSlug: "home-office", at: t)
        store.recordSwitch(toSlug: "conference-room", at: t)

        #expect(store.perProfileCounts["home-office"] == 2)
        #expect(store.perProfileCounts["conference-room"] == 1)
        #expect(store.lastSwitchSlug == "conference-room")
        #expect(store.lastSwitchDate == t)
    }

    @Test("streak: same calendar day does not advance currentStreak or activeDays")
    func streakSameDayNoOp() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        let morning = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let afternoon = morning.addingTimeInterval(5 * 3600)

        store.recordSwitch(toSlug: "a", at: morning)
        #expect(store.currentStreakDays == 1)
        #expect(store.activeDaysCount == 1)

        store.recordSwitch(toSlug: "b", at: afternoon)
        // Same day — no streak advance, no activeDays increment.
        #expect(store.currentStreakDays == 1)
        #expect(store.activeDaysCount == 1)
    }

    @Test("streak: consecutive days advance; gap resets; longest tracks max")
    func streakAdvanceGapAndLongest() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        let day1 = cal.date(byAdding: .day, value: 1, to: day0)!
        let day2 = cal.date(byAdding: .day, value: 2, to: day0)!
        let day5 = cal.date(byAdding: .day, value: 5, to: day0)!

        store.recordSwitch(toSlug: "a", at: day0)
        store.recordSwitch(toSlug: "a", at: day1)
        store.recordSwitch(toSlug: "a", at: day2)
        #expect(store.currentStreakDays == 3)
        #expect(store.longestStreakDays == 3)
        #expect(store.activeDaysCount == 3)

        // Gap of 2 days resets the streak; longest is preserved.
        store.recordSwitch(toSlug: "a", at: day5)
        #expect(store.currentStreakDays == 1)
        #expect(store.longestStreakDays == 3)
        #expect(store.activeDaysCount == 4)
    }

    @Test("recordDevicesSeen deduplicates and only writes when set grows")
    func uniqueDevicesDedup() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let cam = USBDevice(vendorID: 0x046d, productID: 0x085e)

        store.recordDevicesSeen([dock])
        #expect(store.uniqueDevicesSeenCount == 1)

        // Re-seeing the same device shouldn't grow the set.
        store.recordDevicesSeen([dock])
        #expect(store.uniqueDevicesSeenCount == 1)

        store.recordDevicesSeen([dock, cam])
        #expect(store.uniqueDevicesSeenCount == 2)
    }

    @Test("forgetProfile drops per-slug count and clears last-switch fields if they match")
    func forgetProfileClearsPerSlugData() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "conference-room")

        // Aggregates that should NOT be touched by a per-profile delete.
        let totalBefore = store.profileSwitchCount
        let activeDaysBefore = store.activeDaysCount
        let streakBefore = store.currentStreakDays

        store.forgetProfile(slug: "home-office")

        #expect(store.perProfileCounts["home-office"] == nil)
        #expect(store.perProfileCounts["conference-room"] == 1)
        #expect(store.profileSwitchCount == totalBefore)
        #expect(store.activeDaysCount == activeDaysBefore)
        #expect(store.currentStreakDays == streakBefore)
    }

    @Test("forgetProfile clears lastSwitchSlug only when it matches the deleted slug")
    func forgetProfilePreservesUnrelatedLastSwitch() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "conference-room")
        // conference-room was the most recent switch.
        #expect(store.lastSwitchSlug == "conference-room")

        store.forgetProfile(slug: "home-office")
        // Unrelated last-switch is untouched.
        #expect(store.lastSwitchSlug == "conference-room")
        #expect(store.lastSwitchDate != nil)

        store.forgetProfile(slug: "conference-room")
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
    }

    @Test("forgetProfile is a no-op for an unknown slug")
    func forgetProfileUnknownSlug() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.forgetProfile(slug: "never-existed")
        #expect(store.perProfileCounts["home-office"] == 1)
        #expect(store.lastSwitchSlug == "home-office")
    }

    @Test("resetStats wipes counters; tracking flag is preserved")
    func resetStatsWipes() {
        let defaults = makeSuite()
        let store = SettingsStore(defaults: defaults)
        store.statsTrackingEnabled = true
        store.incrementSwitchCount()
        store.recordSwitch(toSlug: "home-office")
        store.incrementManualOverrideCount()
        store.recordDevicesSeen([USBDevice(vendorID: 0x2188, productID: 0x6533)])

        let stampBeforeReset = store.statsStartDate
        store.resetStats()

        #expect(store.profileSwitchCount == 0)
        #expect(store.perProfileCounts.isEmpty)
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
        #expect(store.manualOverrideCount == 0)
        #expect(store.currentStreakDays == 0)
        #expect(store.longestStreakDays == 0)
        #expect(store.activeDaysCount == 0)
        #expect(store.uniqueDevicesSeenCount == 0)
        // Tracking stays on; statsStartDate gets re-stamped to "now"
        // (>= the stamp the original opt-in produced).
        #expect(store.statsTrackingEnabled == true)
        #expect((store.statsStartDate ?? .distantPast) >= (stampBeforeReset ?? .distantPast))
    }

    @Test("hasRecordedStats reflects user-meaningful data, not bookkeeping")
    func hasRecordedStatsIgnoresStartDate() {
        let store = SettingsStore(defaults: makeSuite())
        // Fresh store: nothing.
        #expect(store.hasRecordedStats == false)

        // Pure opt-in stamps statsStartDate but doesn't count as
        // recorded data. Off → on → off should NOT trigger the
        // disable-reset prompt for a user who never actually used
        // the feature.
        store.statsTrackingEnabled = true
        #expect(store.statsStartDate != nil)
        #expect(store.hasRecordedStats == false)

        // Toggling off doesn't change the picture.
        store.statsTrackingEnabled = false
        #expect(store.hasRecordedStats == false)
    }

    @Test("post-reset state is not considered recorded data")
    func hasRecordedStatsAfterReset() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        #expect(store.hasRecordedStats == true)

        store.resetStats()
        // resetStats stamps statsStartDate to "now" while tracking
        // is on, but every counter / collection is back to zero.
        // The disable-reset prompt MUST not fire just because the
        // start date is set.
        #expect(store.hasRecordedStats == false)
    }

    @Test("recordSwitch and recordDevicesSeen both flip hasRecordedStats true")
    func hasRecordedStatsTrueOnRealActivity() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true

        store.recordSwitch(toSlug: "home-office")
        #expect(store.hasRecordedStats == true)

        store.resetStats()
        #expect(store.hasRecordedStats == false)

        store.recordDevicesSeen([USBDevice(vendorID: 0x2188, productID: 0x6533)])
        #expect(store.hasRecordedStats == true)
    }

    @Test("stats fields persist across reloads")
    func statsFieldsRoundTrip() {
        let defaults = makeSuite()
        let date = Date()
        do {
            let store = SettingsStore(defaults: defaults)
            store.statsTrackingEnabled = true
            store.recordSwitch(toSlug: "home-office", at: date)
            store.recordSwitch(toSlug: "conference-room", at: date)
            store.incrementManualOverrideCount()
            store.recordDevicesSeen([USBDevice(vendorID: 0x2188, productID: 0x6533)])
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.statsTrackingEnabled == true)
        #expect(reopened.statsStartDate != nil)
        #expect(reopened.perProfileCounts["home-office"] == 1)
        #expect(reopened.perProfileCounts["conference-room"] == 1)
        #expect(reopened.lastSwitchSlug == "conference-room")
        #expect(reopened.manualOverrideCount == 1)
        #expect(reopened.uniqueDevicesSeenCount == 1)
    }
}
