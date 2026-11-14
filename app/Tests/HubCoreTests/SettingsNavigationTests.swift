import Testing
@testable import HubCore

@Suite struct SettingsNavigationTests {
    @Test func theOldAgentsNameMeansTeams() {
        #expect(SettingsSectionName.canonical("agents") == "teams")
    }

    @Test func otherNamesStayAsTheyAre() {
        for name in ["teams", "window", "theme", "remote", "nonsense", ""] {
            #expect(SettingsSectionName.canonical(name) == name)
        }
    }

    @Test func aTeamWithoutEditsIsLeftWithoutAsking() {
        #expect(!UnsavedChanges.needsAsk(changed: false, asking: false))
    }

    @Test func aTeamWithEditsAsksOnce() {
        #expect(UnsavedChanges.needsAsk(changed: true, asking: false))
        #expect(!UnsavedChanges.needsAsk(changed: true, asking: true))
    }

    @Test func eachAnswerHasItsStep() {
        #expect(UnsavedChanges.step(for: .save) == .save)
        #expect(UnsavedChanges.step(for: .discard) == .discardAndGo)
        #expect(UnsavedChanges.step(for: .cancel) == .stay)
    }

    @Test func aRefusedSaveStaysAndASavedOneGoesOn() {
        #expect(UnsavedChanges.afterSave(succeeded: true) == .goOn)
        #expect(UnsavedChanges.afterSave(succeeded: false) == .stay)
    }
}
