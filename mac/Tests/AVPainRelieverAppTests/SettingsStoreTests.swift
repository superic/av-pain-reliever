import Testing
import Foundation
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
        #expect(store.showAudioCameraInMenu == true)
        #expect(store.debounceInterval == 1.5)
        #expect(store.profileSwitchCount == 0)
        #expect(store.suppressedWelcome == false)
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

    @Test("incrementSwitchCount persists across reloads")
    func switchCountIncrements() {
        let defaults = makeSuite()
        do {
            let store = SettingsStore(defaults: defaults)
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
}
