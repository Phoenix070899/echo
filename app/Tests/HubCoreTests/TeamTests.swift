import Foundation
import Testing
@testable import HubCore

private func team(_ json: String) throws -> Team {
    try JSONDecoder().decode(Team.self, from: Data(json.utf8))
}

@Test func decodesATeamWithEveryField() throws {
    let decoded = try team("""
    {"name":"kiro-lean","origin":"shipped","path":"/r/teams/kiro-lean.json","replaces":[],"problem":null,
     "description":"Everything on Kiro.",
     "orchestrator":{"cli":"kiro","model":"claude-sonnet-5.5","effort":"medium","rotateAt":150000},
     "workers":{"cli":"kiro","model":"claude-haiku-5.5","effort":"low",
                "profiles":{"naruto":{"model":"claude-sonnet-5.5","effort":"high"}}},
     "rules":{"maxWorkers":3,"planApproval":true,"review":false,"mergeWithoutAsking":false},
     "instructions":"Keep reports short."}
    """)
    #expect(decoded.name == "kiro-lean")
    #expect(decoded.orchestrator == Team.Setup(cli: "kiro", model: "claude-sonnet-5.5", effort: "medium", rotateAt: 150000))
    #expect(decoded.workers?.profiles?["naruto"]?.effort == "high")
    #expect(decoded.rules == Team.Rules(maxWorkers: 3, planApproval: true, review: false, mergeWithoutAsking: false))
    #expect(decoded.instructions == "Keep reports short.")
    #expect(decoded.usable)
}

@Test func decodesATeamWithoutItsOptionalFields() throws {
    let decoded = try team(#"{"name":"bare","origin":"user","path":"/h/.echo/teams/bare.json","replaces":["shipped"],"problem":null}"#)
    #expect(decoded.orchestrator == nil)
    #expect(decoded.workers == nil)
    #expect(decoded.rules == nil)
    #expect(decoded.description == nil)
    #expect(decoded.replaces == ["shipped"])
    #expect(try team(#"{"name":"bare"}"#).origin == "", "Even origin and replaces may be absent")
}

@Test func decodesATeamWithUnknownFields() throws {
    let decoded = try team("""
    {"name":"future","origin":"repo","replaces":[],"problem":null,"budget":12,
     "orchestrator":{"model":"m","temperature":0.2},"workers":{"effort":"low","pool":{"size":2}},
     "rules":{"review":true,"autoFix":true}}
    """)
    #expect(decoded.orchestrator?.model == "m")
    #expect(decoded.workers?.effort == "low")
    #expect(decoded.rules?.review == true)
}

@Test func aTeamWithAProblemCannotBeUsed() throws {
    let broken = try team(#"{"name":"oops","origin":"user","replaces":[],"problem":"/h/.echo/teams/oops.json: expected a string"}"#)
    #expect(!broken.usable)
    #expect(broken.problem?.contains("expected a string") == true)
}

@Test func theSummaryReadsInOneLine() throws {
    let lean = try team(#"{"name":"claude-lean","orchestrator":{"model":"claude-sonnet-5.5","effort":"medium"}}"#)
    #expect(lean.summary == "Orchestrator: claude-sonnet-5.5, medium. Workers: by their Profiles.")
    #expect(Team(name: "x").summary == "Orchestrator: the settings. Workers: by their Profiles.")
    let kiro = try team("""
    {"name":"kiro-lean","orchestrator":{"cli":"kiro","model":"claude-sonnet-5.5","effort":"medium"},
     "workers":{"cli":"kiro","model":"claude-haiku-5.5","effort":"low","profiles":{"naruto":{},"sasuke":{}}}}
    """)
    #expect(kiro.summary == "Orchestrator: kiro, claude-sonnet-5.5, medium. Workers: kiro, claude-haiku-5.5, low, 2 Profiles set apart.")
}

@Test func theAgentCarriesItsTeam() throws {
    let agents = try JSONDecoder().decode([Agent].self, from: Data(
        #"[{"id":1,"kind":"orchestrator","name":null,"model":null,"live":true,"team":"claude-lean"},{"id":2,"kind":"claude","live":false}]"#.utf8))
    #expect(agents[0].team == "claude-lean")
    #expect(agents[1].team == nil)
}

@Test func openParamsCarryTheTeamOfAnOrchestratorOnly() {
    let orchestrator = openAgentParams(repo: "/r", kind: .orchestrator, name: "Rerank", model: "claude-opus-5-5",
                                       team: "claude-lean", request: "Go", newBranch: "feat/x", base: "main")
    #expect(orchestrator["team"] as? String == "claude-lean")
    #expect(orchestrator["model"] == nil, "A model picked for an Orchestrator would override its Team")
    #expect(orchestrator["name"] as? String == "Rerank")
    #expect(orchestrator["new_branch"] as? String == "feat/x")
    #expect(orchestrator["base"] as? String == "main")
    #expect(orchestrator["request"] as? String == "Go")

    let without = openAgentParams(repo: "/r", kind: .orchestrator, name: "", model: "", team: nil)
    #expect(Set(without.keys) == ["repo", "kind"])
    #expect(without["team"] == nil)
    #expect(without["model"] == nil)
    #expect(openAgentParams(repo: "/r", kind: .orchestrator, team: "")["team"] == nil, "An empty Team is none")

    let normal = openAgentParams(repo: "/r", kind: .claude, model: "claude-sonnet-5-5", team: "claude-lean")
    #expect(normal["team"] == nil, "A Normal session has no Team")
    #expect(normal["model"] as? String == "claude-sonnet-5-5", "Normal mode keeps its model")
    #expect(openAgentParams(repo: "/r", kind: .terminal, team: "claude-lean")["team"] == nil)
}

@Test func theLastTeamUsedIsRemembered() throws {
    let suite = "dev.agenthub.Echo.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(TeamChoice.remembered(in: defaults) == nil)
    TeamChoice.remember("kiro-lean", in: defaults)
    #expect(TeamChoice.remembered(in: defaults) == "kiro-lean")
}

@Test func theSheetStartsOnTheRememberedTeamElseClaudeOpus() {
    let teams = [Team(name: "claude-lean"), Team(name: "claude-opus"), Team(name: "kiro-lean"),
                 Team(name: "broken", problem: "bad file")]
    #expect(TeamChoice.pick(from: teams, current: nil, remembered: nil) == "claude-opus")
    #expect(TeamChoice.pick(from: teams, current: nil, remembered: "kiro-lean") == "kiro-lean")
    #expect(TeamChoice.pick(from: teams, current: "claude-lean", remembered: "kiro-lean") == "claude-lean", "What is shown stays")
    #expect(TeamChoice.pick(from: teams, current: nil, remembered: "gone") == "claude-opus", "A deleted Team is forgotten")
    #expect(TeamChoice.pick(from: teams, current: nil, remembered: "broken") == "claude-opus", "A Team with a problem is not picked")
    #expect(TeamChoice.pick(from: [Team(name: "mine")], current: nil, remembered: nil) == "mine")
    #expect(TeamChoice.pick(from: [Team(name: "broken", problem: "x")], current: nil, remembered: nil) == nil)
    #expect(TeamChoice.pick(from: [], current: nil, remembered: nil) == nil)
}
