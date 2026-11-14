import Foundation
import Testing
@testable import HubCore

/// The repo's `actions/` folder, found from this file's place in it.
private var actionsFolder: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("actions")
}

private func shape(_ members: [Team.Member]) -> [String] {
    members.map { "\($0.id):\($0.action):\($0.profile):\($0.parent ?? "-")" }
}

@Test func theShippedActionsTableEqualsTheActionFiles() throws {
    for action in Action.shipped {
        let data = try Data(contentsOf: actionsFolder.appendingPathComponent("\(action.id).json"))
        #expect(try JSONDecoder().decode(Action.self, from: data) == action, "\(action.id)")
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: actionsFolder.path).filter { $0.hasSuffix(".json") }
    #expect(files.count == Action.shipped.count)
    #expect(Action.shipped.map(\.id) == Action.shippedIDs)
}

@Test func theTemplatesHoldTheMembersTheirNamesPromise() {
    #expect(TeamTemplate.blank.members.isEmpty)
    #expect(shape(TeamTemplate.solo.members) == ["build:execute:naruto:-", "check:verify:sasuke:build"])
    #expect(shape(TeamTemplate.standard.members) == [
        "scan:scan:hinata:-", "build:execute:naruto:-", "check:verify:sasuke:build", "run:run:lee:-",
    ])
    #expect(shape(TeamTemplate.researchHeavy.members) == [
        "research:research:jiraiya:-", "scan:scan:hinata:-", "build:execute:naruto:-",
        "check:verify:sasuke:build", "run:run:lee:-",
    ])
}

@Test func aTemplateMemberCarriesOnlyItsActionAndProfile() {
    for member in TeamTemplate.researchHeavy.members {
        #expect(member.instructions == nil && member.model == nil && member.effort == nil && member.cli == nil)
        #expect(member.tools.isEmpty && member.skills.isEmpty && member.context.isEmpty)
    }
}

@Test func everyTemplateValidatesUnderEveryPreset() {
    for template in TeamTemplate.allCases {
        for preset in ProviderPreset.allCases {
            let form = TeamForm.starting(template: template, preset: preset, name: "mine")
            #expect(form.blocker == nil, "\(template) on \(preset)")
            #expect(TeamTree.isValid(form.members))
        }
    }
}

@Test func aStartingFormIsNewUnsavedAndNamedForTheSheet() {
    let form = TeamForm.starting(template: .solo, preset: .claude, name: "mine", level: TeamForm.repoLevel)
    #expect(form.isNew && form.name == "mine" && form.level == TeamForm.repoLevel)
    #expect(TeamForm.starting(template: .solo, preset: .claude, name: "mine").level == TeamForm.userLevel)
    #expect(TeamForm.starting(template: .solo, preset: .claude, name: " ").blocker == "Name the Team.")
}

@Test func claudeSetsTheOrchestratorAndLeavesTheWorkersToTheirProfiles() throws {
    let form = TeamForm.starting(template: .standard, preset: .claude, name: "mine")
    #expect(form.orchestratorCli == "claude" && form.orchestratorModel == "anthropic/claude-opus-5-5")
    #expect(form.orchestratorEffort == "high")
    #expect(form.workersCli.isEmpty && form.workersModel.isEmpty && form.workersEffort.isEmpty)
    #expect(form.members.allSatisfy { $0.model == nil && $0.effort == nil })
    let team = try #require(form.saveParams(repo: nil)["team"] as? [String: Any])
    #expect(team["workers"] == nil)
}

@Test func kiroPutsNarutoAndSasukeOnSonnetAndTheRestOnHaiku() {
    let form = TeamForm.starting(template: .standard, preset: .kiro, name: "mine")
    #expect(form.orchestratorCli == "kiro" && form.orchestratorModel == "claude-sonnet-5.5")
    #expect(form.orchestratorEffort == "medium")
    #expect(form.workersCli == "kiro" && form.workersModel == "claude-haiku-5.5" && form.workersEffort == "low")
    let byID = Dictionary(uniqueKeysWithValues: form.members.map { ($0.id, $0) })
    #expect(byID["build"]?.model == "claude-sonnet-5.5" && byID["build"]?.effort == "high")
    #expect(byID["check"]?.model == "claude-sonnet-5.5" && byID["check"]?.effort == "medium")
    #expect(byID["scan"]?.model == nil && byID["run"]?.model == nil)
}

@Test func kiroMatchesTheShippedKiroLeanTeam() throws {
    let file = actionsFolder.deletingLastPathComponent().appendingPathComponent("teams/kiro-lean.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    json["name"] = "kiro-lean"
    let team = try JSONDecoder().decode(Team.self, from: JSONSerialization.data(withJSONObject: json))
    let form = TeamForm.starting(template: .standard, preset: .kiro, name: "kiro-lean")
    #expect(form.orchestratorModel == team.orchestrator?.model && form.orchestratorEffort == team.orchestrator?.effort)
    #expect(form.workersModel == team.workers?.model && form.workersEffort == team.workers?.effort)
    for member in form.members {
        let shipped = try #require(team.members.first { $0.id == member.id })
        #expect(member.model == shipped.model && member.effort == shipped.effort, "\(member.id)")
    }
}

@Test func codexNamesTheCliAndLeavesModelsAndEffortsEmpty() {
    let form = TeamForm.starting(template: .solo, preset: .codex, name: "mine")
    #expect(form.orchestratorCli == "codex" && form.workersCli == "codex")
    #expect(form.orchestratorModel.isEmpty && form.workersModel.isEmpty)
    #expect(form.orchestratorEffort.isEmpty && form.workersEffort.isEmpty)
    #expect(form.members.allSatisfy { $0.model == nil && $0.effort == nil })
}

@Test func everyTemplateAndPresetHasItsWordsForTheSheet() {
    #expect(TeamTemplate.allCases.map(\.title) == ["Blank", "Solo", "Standard", "Research-heavy"])
    #expect(TeamTemplate.allCases.allSatisfy { !$0.summary.isEmpty })
    #expect(ProviderPreset.allCases.map(\.title) == ["Claude", "Kiro", "Codex"])
}
