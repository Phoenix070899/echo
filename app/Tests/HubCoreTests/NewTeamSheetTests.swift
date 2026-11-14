import Foundation
import Testing
@testable import HubCore

private let crew = Team(name: "crew", origin: "user", orchestrator: Team.Setup(cli: "codex", model: "gpt", effort: "low"),
                        members: TeamTemplate.solo.members)
private let shippedTeam = Team(name: "claude-opus", origin: "shipped")
private let repoTeam = Team(name: "ours", origin: "repo")
private let teams = [shippedTeam, crew, repoTeam]

private func sheet(_ name: String, start: NewTeamStart = .standard) -> NewTeamSheet {
    var sheet = NewTeamSheet()
    sheet.name = name
    sheet.start = start
    return sheet
}

@Test func theSheetStartsOnStandardAndClaudeAtYourLevel() {
    let fresh = NewTeamSheet()
    #expect(fresh.start == .standard && fresh.preset == .claude && fresh.level == TeamForm.userLevel)
    #expect(!fresh.canCreate(teams: teams, hasRepo: false))
}

@Test func keepInIsOfferedOnlyWithARepo() {
    #expect(NewTeamSheet.levels(hasRepo: false) == [TeamForm.userLevel])
    #expect(NewTeamSheet.levels(hasRepo: true) == [TeamForm.userLevel, TeamForm.repoLevel])
    var repoSheet = sheet("mine")
    repoSheet.level = TeamForm.repoLevel
    #expect(repoSheet.level(hasRepo: true) == TeamForm.repoLevel)
    #expect(repoSheet.level(hasRepo: false) == TeamForm.userLevel)
    #expect(repoSheet.form(teams: teams, hasRepo: false)?.level == TeamForm.userLevel)
}

@Test func everyStartingPointHasATitleAndOnePlainLine() {
    #expect(NewTeamStart.allCases.map(\.title) == ["Blank", "Solo", "Standard", "Research-heavy", "Copy of a Team"])
    for start in NewTeamStart.allCases {
        #expect(!start.summary.isEmpty && !start.summary.contains("\n") && !start.summary.contains("\u{2014}"), "\(start)")
    }
    #expect(NewTeamStart.standard.summary == TeamTemplate.standard.summary)
}

@Test func aCopyIsOfferedOnlyWhenThereIsATeamToCopy() {
    #expect(NewTeamSheet.starts(teams: teams) == NewTeamStart.allCases)
    #expect(NewTeamSheet.starts(teams: []) == [.blank, .solo, .standard, .researchHeavy])
}

@Test func theProviderIsHiddenForACopy() {
    #expect(sheet("mine").offersProvider)
    #expect(!sheet("mine", start: .copy).offersProvider)
}

@Test func anEmptyNameKeepsCreateOffWithoutScolding() {
    for text in ["", "   "] {
        let empty = sheet(text)
        #expect(empty.nameProblem(taking: teams, hasRepo: false) == nil)
        #expect(empty.problem(teams: teams, hasRepo: false) == nil)
        #expect(!empty.canCreate(teams: teams, hasRepo: false))
    }
}

@Test func theNameIsCheckedLiveWithTheDaemonsRules() {
    let rule = "Use lowercase letters, digits and -, and do not start with -."
    for bad in ["Mine", "my team", "-mine", "mine_2", "équipe"] {
        #expect(sheet(bad).nameProblem(taking: teams, hasRepo: false) == rule, "\(bad)")
        #expect(!sheet(bad).canCreate(teams: teams, hasRepo: false), "\(bad)")
    }
    let long = String(repeating: "a", count: 41)
    #expect(sheet(long).problem(teams: teams, hasRepo: false) == "A name is at most 40 characters.")
    #expect(sheet(String(repeating: "a", count: 40)).canCreate(teams: teams, hasRepo: false))
    #expect(sheet(" mine-2 ").canCreate(teams: teams, hasRepo: false))
}

@Test func aNameAlreadyKeptAtThatLevelIsRefusedButAShippedOneIsReplaced() {
    #expect(sheet("crew").problem(teams: teams, hasRepo: false) == "You already have a Team named crew.")
    #expect(sheet("claude-opus").canCreate(teams: teams, hasRepo: false))
    // The repo's Team is only in the way when the Team is kept in the repo.
    #expect(sheet("ours").canCreate(teams: teams, hasRepo: true))
    var inRepo = sheet("ours")
    inRepo.level = TeamForm.repoLevel
    #expect(inRepo.problem(teams: teams, hasRepo: true) == "This repo already has a Team named ours.")
    inRepo.name = "crew"
    #expect(inRepo.canCreate(teams: teams, hasRepo: true))
}

@Test func createBuildsTheTemplateOnTheProvider() throws {
    var kiro = sheet(" mine ", start: .solo)
    kiro.preset = .kiro
    let form = try #require(kiro.form(teams: teams, hasRepo: false))
    #expect(form == TeamForm.starting(template: .solo, preset: .kiro, name: "mine"))
    #expect(form.isNew && form.blocker == nil)
}

@Test func everyStartingPointOnEveryProviderCanBeCreated() throws {
    for start in NewTeamStart.allCases {
        for preset in ProviderPreset.allCases {
            var made = sheet("mine", start: start)
            made.preset = preset
            made.copyOf = "crew"
            #expect(try #require(made.form(teams: teams, hasRepo: true)).isNew, "\(start) \(preset)")
        }
    }
}

@Test func aCopyTakesTheSheetsNameAndLevelAndIgnoresTheProvider() throws {
    var copy = sheet("mine", start: .copy)
    copy.copyOf = "crew"
    copy.level = TeamForm.repoLevel
    copy.preset = .kiro
    let form = try #require(copy.form(teams: teams, hasRepo: true))
    #expect(form.name == "mine" && form.level == TeamForm.repoLevel && form.isNew)
    #expect(form.orchestratorCli == "codex" && form.workersCli.isEmpty)
    #expect(form.members == crew.members)
    copy.preset = .claude
    #expect(copy.form(teams: teams, hasRepo: true) == form)
}

@Test func aCopyWithNoTeamPickedTakesTheFirstAndWithNoneIsOff() throws {
    let copy = sheet("mine", start: .copy)
    #expect(copy.source(in: teams)?.name == "claude-opus")
    #expect(copy.canCreate(teams: teams, hasRepo: false))
    #expect(!copy.canCreate(teams: [], hasRepo: false))
}

@Test func aCopyOfABrokenTeamSaysWhyCreateIsOff() {
    let broken = Team(name: "broken", origin: "user", members: [Team.Member(id: "Bad Id", action: "execute", profile: "naruto")])
    var copy = sheet("mine", start: .copy)
    copy.copyOf = "broken"
    #expect(!copy.canCreate(teams: [broken], hasRepo: false))
    #expect(copy.problem(teams: [broken], hasRepo: false)?.contains("Bad Id") == true)
}

@Test func steppingStopsAtTheEnds() {
    let starts = NewTeamSheet.starts(teams: teams)
    #expect(NewTeamSheet.step(NewTeamStart.solo, in: starts, by: 1) == .standard)
    #expect(NewTeamSheet.step(NewTeamStart.blank, in: starts, by: -1) == .blank)
    #expect(NewTeamSheet.step(NewTeamStart.copy, in: starts, by: 1) == .copy)
    #expect(NewTeamSheet.step(NewTeamStart.copy, in: [NewTeamStart.blank], by: 1) == .blank)
    #expect(NewTeamSheet.step(ProviderPreset.claude, in: ProviderPreset.allCases, by: 1) == .kiro)
}
