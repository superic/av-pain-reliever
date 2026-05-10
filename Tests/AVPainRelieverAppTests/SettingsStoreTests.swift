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

    @Test("reconcileProfiles drops stats for slugs not in the current set")
    func reconcileProfilesDropsOrphans() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "conference-room")
        store.recordSwitch(toSlug: "ghost-from-old-build")

        let aggregateBefore = store.profileSwitchCount
        store.reconcileProfiles(currentSlugs: ["home-office", "conference-room"])

        #expect(store.perProfileCounts["home-office"] == 1)
        #expect(store.perProfileCounts["conference-room"] == 1)
        #expect(store.perProfileCounts["ghost-from-old-build"] == nil)
        // Aggregates untouched by reconcile, just like forgetProfile.
        #expect(store.profileSwitchCount == aggregateBefore)
    }

    @Test("reconcileProfiles clears lastSwitch fields when the slug is orphaned")
    func reconcileProfilesClearsOrphanedLastSwitch() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "ghost")
        // ghost is the most recent.
        #expect(store.lastSwitchSlug == "ghost")

        store.reconcileProfiles(currentSlugs: ["home-office"])
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
    }

    @Test("reconcileProfiles preserves lastSwitch fields when the slug is still present")
    func reconcileProfilesPreservesLiveLastSwitch() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "ghost")
        store.recordSwitch(toSlug: "home-office")
        #expect(store.lastSwitchSlug == "home-office")

        store.reconcileProfiles(currentSlugs: ["home-office"])
        #expect(store.lastSwitchSlug == "home-office")
        #expect(store.lastSwitchDate != nil)
    }

    @Test("reconcileProfiles is a no-op when every slug is still present")
    func reconcileProfilesAllPresent() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "conference-room")
        let snapshot = store.perProfileCounts

        store.reconcileProfiles(currentSlugs: ["home-office", "conference-room", "unused-extra"])
        #expect(store.perProfileCounts == snapshot)
        #expect(store.lastSwitchSlug == "conference-room")
    }

    @Test("reconcileProfiles with an empty set drops everything per-slug, leaves aggregates")
    func reconcileProfilesEmptySet() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.recordSwitch(toSlug: "conference-room")
        let aggregateBefore = store.profileSwitchCount
        let streakBefore = store.currentStreakDays

        store.reconcileProfiles(currentSlugs: [])
        #expect(store.perProfileCounts.isEmpty)
        #expect(store.lastSwitchSlug == nil)
        #expect(store.lastSwitchDate == nil)
        #expect(store.profileSwitchCount == aggregateBefore)
        #expect(store.currentStreakDays == streakBefore)
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

    // MARK: - Per-profile state migration (delete / rename / reconcile)

    @Test("forgetProfile clears the deleted profile's remembered-device caches")
    func forgetProfileClearsRememberedDeviceCaches() {
        // Regression for the orphan-on-delete bug surfaced by slop
        // review: deleting a profile used to leave its three
        // remembered-* dict entries dangling in UserDefaults until
        // the user found the Forget Unused Devices button.
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "conference-room",
            audioInputs: ["Yeti"],
            audioOutputs: ["Conference Speakers"],
            cameras: ["Conference Cam"]
        )
        // Sanity: the entries exist before the delete.
        #expect(store.rememberedAudioInputs["conference-room"] == ["Yeti"])

        store.forgetProfile(slug: "conference-room")

        #expect(store.rememberedAudioInputs["conference-room"] == nil)
        #expect(store.rememberedAudioOutputs["conference-room"] == nil)
        #expect(store.rememberedCameras["conference-room"] == nil)
    }

    @Test("forgetProfile leaves other profiles' caches intact")
    func forgetProfileSpared() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "conference-room",
            audioInputs: ["Yeti"], audioOutputs: [], cameras: []
        )
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["CalDigit"], audioOutputs: [], cameras: []
        )
        store.forgetProfile(slug: "conference-room")
        #expect(store.rememberedAudioInputs["home-office"] == ["CalDigit"])
    }

    @Test("reconcileProfiles drops cache entries for slugs not in the current set")
    func reconcileProfilesDropsCacheOrphans() {
        // Regression for the orphan-survives-reboot path: a profile
        // deleted out-of-band (hand-edit of profiles.toml, missed
        // forgetProfile call) should have its cache cleaned up at
        // the next bootEngine via reconcileProfiles.
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "ghost-from-old-build",
            audioInputs: ["Old Mic"], audioOutputs: [], cameras: []
        )
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["CalDigit"],
            audioOutputs: ["CalDigit"],
            cameras: ["BRIO"]
        )

        store.reconcileProfiles(currentSlugs: ["home-office"])

        #expect(store.rememberedAudioInputs["ghost-from-old-build"] == nil)
        #expect(store.rememberedAudioInputs["home-office"] == ["CalDigit"])
        #expect(store.rememberedCameras["home-office"] == ["BRIO"])
    }

    @Test("renameProfile moves stats and remembered-device caches to the new slug")
    func renameProfileMovesAllPerSlugState() {
        // Regression for the orphan-on-rename bug: renaming Home
        // Office to Apartment should carry the per-profile cache so
        // the wizard's dropdowns keep showing the saved selections
        // under the new identity.
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "home-office")
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti", "AT2020"],
            audioOutputs: ["CalDigit"],
            cameras: ["BRIO"]
        )

        store.renameProfile(from: "home-office", to: "apartment")

        // Old slug is gone.
        #expect(store.perProfileCounts["home-office"] == nil)
        #expect(store.rememberedAudioInputs["home-office"] == nil)
        #expect(store.rememberedAudioOutputs["home-office"] == nil)
        #expect(store.rememberedCameras["home-office"] == nil)
        // New slug carries the migrated state.
        #expect(store.perProfileCounts["apartment"] == 1)
        #expect(store.rememberedAudioInputs["apartment"] == ["Yeti", "AT2020"])
        #expect(store.rememberedAudioOutputs["apartment"] == ["CalDigit"])
        #expect(store.rememberedCameras["apartment"] == ["BRIO"])
        // lastSwitchSlug follows the rename.
        #expect(store.lastSwitchSlug == "apartment")
    }

    @Test("renameProfile is a no-op when old and new slugs match")
    func renameProfileNoOpForSameSlug() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"], audioOutputs: [], cameras: []
        )
        store.renameProfile(from: "home-office", to: "home-office")
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti"])
    }

    @Test("renameProfile leaves lastSwitchSlug alone when it doesn't point at the renamed profile")
    func renameProfileLeavesUnrelatedLastSwitchAlone() {
        let store = SettingsStore(defaults: makeSuite())
        store.statsTrackingEnabled = true
        store.recordSwitch(toSlug: "conference-room")
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"], audioOutputs: [], cameras: []
        )
        store.renameProfile(from: "home-office", to: "apartment")
        #expect(store.lastSwitchSlug == "conference-room")
    }

    // MARK: - Remembered devices (wizard pickers, per-profile cache)

    @Test("remembered-device caches default to empty dicts")
    func rememberedDevicesDefaultEmpty() {
        let store = SettingsStore(defaults: makeSuite())
        #expect(store.rememberedAudioInputs.isEmpty)
        #expect(store.rememberedAudioOutputs.isEmpty)
        #expect(store.rememberedCameras.isEmpty)
        #expect(store.hasRememberedDevices == false)
    }

    @Test("rememberDevices appends new names under the profile's slug and dedupes")
    func rememberDevicesAppendsAndDedupes() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti", "MacBook Pro Microphone"],
            audioOutputs: ["MacBook Pro Speakers"],
            cameras: ["Built-in", "Logitech BRIO"]
        )
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti", "MacBook Pro Microphone"])
        #expect(store.rememberedAudioOutputs["home-office"] == ["MacBook Pro Speakers"])
        #expect(store.rememberedCameras["home-office"] == ["Built-in", "Logitech BRIO"])
        #expect(store.hasRememberedDevices == true)

        // Second call for the same profile with overlap + a new entry
        // only appends the new one.
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti", "Shure MV7"],
            audioOutputs: ["MacBook Pro Speakers"],
            cameras: ["Logitech BRIO"]
        )
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti", "MacBook Pro Microphone", "Shure MV7"])
        #expect(store.rememberedAudioOutputs["home-office"] == ["MacBook Pro Speakers"])
        #expect(store.rememberedCameras["home-office"] == ["Built-in", "Logitech BRIO"])
    }

    @Test("rememberDevices keeps profiles' caches isolated from each other")
    func rememberDevicesIsolatesProfiles() {
        // The headline behavior for the per-profile redesign: Home
        // Office's CalDigit must NEVER leak into Conference Room's
        // dropdown when the user opens Conference Room's wizard.
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["CalDigit TS3 Audio"],
            audioOutputs: ["CalDigit TS3 Audio"],
            cameras: ["Logitech BRIO"]
        )
        store.rememberDevices(
            forProfile: "conference-room",
            audioInputs: ["Yeti Stereo Microphone"],
            audioOutputs: ["Conference Room Speakers"],
            cameras: ["Conference Cam"]
        )
        // Each profile only sees its own entries.
        #expect(store.rememberedAudioInputs["home-office"] == ["CalDigit TS3 Audio"])
        #expect(store.rememberedAudioInputs["conference-room"] == ["Yeti Stereo Microphone"])
        #expect(store.rememberedCameras["home-office"] == ["Logitech BRIO"])
        #expect(store.rememberedCameras["conference-room"] == ["Conference Cam"])
    }

    @Test("rememberDevices drops empty-string inputs defensively")
    func rememberDevicesIgnoresEmptyNames() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["", "Yeti"],
            audioOutputs: [""],
            cameras: ["", "Built-in"]
        )
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti"])
        #expect(store.rememberedAudioOutputs["home-office"] == nil)
        #expect(store.rememberedCameras["home-office"] == ["Built-in"])
    }

    @Test("remembered-device caches persist across reloads")
    func rememberedDevicesPersist() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
            store.rememberDevices(
                forProfile: "home-office",
                audioInputs: ["Yeti"],
                audioOutputs: ["Studio Display Speakers"],
                cameras: ["Logitech BRIO"]
            )
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.rememberedAudioInputs["home-office"] == ["Yeti"])
        #expect(reopened.rememberedAudioOutputs["home-office"] == ["Studio Display Speakers"])
        #expect(reopened.rememberedCameras["home-office"] == ["Logitech BRIO"])
        #expect(reopened.hasRememberedDevices == true)
    }

    @Test("forget with an empty profiles list wipes every cache entry")
    func forgetWithEmptyProfilesWipes() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"],
            audioOutputs: ["Speakers"],
            cameras: ["BRIO"]
        )
        store.forgetRememberedDevices(currentProfiles: [])
        #expect(store.rememberedAudioInputs.isEmpty)
        #expect(store.rememberedAudioOutputs.isEmpty)
        #expect(store.rememberedCameras.isEmpty)
        #expect(store.hasRememberedDevices == false)
    }

    @Test("forget trims each profile's cache to its current selections")
    func forgetTrimsToCurrentSelections() {
        // Models the journal a profile builds up: Yeti was originally
        // saved, later swapped for AT2020. Both are in the cache
        // (history), but only AT2020 is the current saved value.
        // Forget should drop Yeti and keep AT2020.
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti", "AT2020"],
            audioOutputs: ["Studio Display Speakers", "MacBook Pro Speakers"],
            cameras: ["Logitech BRIO", "Built-in"]
        )
        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "AT2020",
            audioOutput: "MacBook Pro Speakers",
            camera: "Built-in"
        )
        store.forgetRememberedDevices(currentProfiles: [homeOffice])

        #expect(store.rememberedAudioInputs["home-office"] == ["AT2020"])
        #expect(store.rememberedAudioOutputs["home-office"] == ["MacBook Pro Speakers"])
        #expect(store.rememberedCameras["home-office"] == ["Built-in"])
    }

    @Test("forget drops cache entries for profiles that no longer exist")
    func forgetDropsOrphanProfileCaches() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "deleted-profile",
            audioInputs: ["Old Mic"],
            audioOutputs: [],
            cameras: []
        )
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"],
            audioOutputs: [],
            cameras: []
        )
        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "Yeti"
        )
        store.forgetRememberedDevices(currentProfiles: [homeOffice])

        // Deleted profile's entry is gone; live profile is preserved.
        #expect(store.rememberedAudioInputs["deleted-profile"] == nil)
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti"])
    }

    @Test("forget keeps profiles' caches with empty saved selections by dropping them entirely")
    func forgetEmptyProfileSelectionWipesProfileEntry() {
        // Profile with nil audioInput etc. has nothing to preserve.
        // The trimming function should drop the cache entry entirely
        // (empty arrays produce nothing meaningful to keep).
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "minimal",
            audioInputs: ["Yeti"],
            audioOutputs: ["Speakers"],
            cameras: ["BRIO"]
        )
        let minimal = Profile(name: "minimal", fingerprint: []) // all selections nil
        store.forgetRememberedDevices(currentProfiles: [minimal])

        #expect(store.rememberedAudioInputs["minimal"] == nil)
        #expect(store.rememberedAudioOutputs["minimal"] == nil)
        #expect(store.rememberedCameras["minimal"] == nil)
        #expect(store.hasRememberedDevices == false)
    }

    @Test("forget is a no-op when every profile's cache already matches its current selections")
    func forgetNoOpWhenEverythingInUse() {
        let store = SettingsStore(defaults: makeSuite())
        store.rememberDevices(
            forProfile: "home-office",
            audioInputs: ["Yeti"],
            audioOutputs: ["MacBook Pro Speakers"],
            cameras: ["Built-in"]
        )
        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "Yeti",
            audioOutput: "MacBook Pro Speakers",
            camera: "Built-in"
        )
        store.forgetRememberedDevices(currentProfiles: [homeOffice])
        // Nothing changed.
        #expect(store.rememberedAudioInputs["home-office"] == ["Yeti"])
        #expect(store.rememberedAudioOutputs["home-office"] == ["MacBook Pro Speakers"])
        #expect(store.rememberedCameras["home-office"] == ["Built-in"])
    }

    @Test("constructing a fresh SettingsStore does not write defaults to disk")
    func freshStoreDoesNotPersistDefaults() {
        let defaults = makeSuite()
        _ = SettingsStore(defaults: defaults)
        // The remembered-device caches use the lazy-default-on-read
        // pattern (locked behavior per CLAUDE.md). A construction-only
        // pass must NOT write `[:]` to disk — that would lock in the
        // default and break future evolution of the schema.
        #expect(defaults.object(forKey: SettingsStore.Key.rememberedAudioInputs) == nil)
        #expect(defaults.object(forKey: SettingsStore.Key.rememberedAudioOutputs) == nil)
        #expect(defaults.object(forKey: SettingsStore.Key.rememberedCameras) == nil)
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
