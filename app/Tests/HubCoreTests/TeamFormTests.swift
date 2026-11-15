import Foundation
import Testing
@testable import HubCore

private let kiroLean = Team(
    name: "kiro-lean", origin: "shipped", description: "Everything on Kiro.",
    orchestrator: .init(cli: "kiro", model: "claude-sonnet-5.5", effort: "medium", rotateAt: 150000),
    workers: .init(cli: "kiro", model: "claude-haiku-5.5", effort: "low", profiles: [
        "sasuke": .init(model: "claude-sonnet-5.5", effort: "medium"),
        "naruto": .init(model: "claude-sonnet-5.5", effort: "high"),
    ]),
    rules: .init(maxWorkers: 3, planApproval: true, review: false, mergeWithoutAsking: false),
    instructions: "Keep reports short.")

/// The payload as the JSON the daemon receives.
private func json(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}

@Test func aBlankFormSavesNothingButItsName() throws {
    var form = TeamForm()
    form.name = " my-team "
    let params = form.saveParams(repo: "/r")
    #expect(try json(params) == #"{"level":"user","name":"my-team","team":{}}"#)
}

@Test func theSavePayloadLeavesOutWhatIsUnset() throws {
    var form = TeamForm()
    form.name = "lean"
    form.orchestratorModel = "anthropic/claude-sonnet-5-5"
    form.orchestratorEffort = "medium"
    form.rotateAt = " 150000 "
    form.workersCli = "kiro"
    form.review = false
    form.instructions = "  \n"
    #expect(try json(form.fields) == """
    {"orchestrator":{"effort":"medium","model":"anthropic\\/claude-sonnet-5-5","rotateAt":150000},\
    "rules":{"review":false},"workers":{"cli":"kiro"}}
    """)
}

@Test func aLoadedTeamFillsEveryField() throws {
    let form = TeamForm(team: kiroLean)
    #expect(form.name == "kiro-lean")
    #expect(!form.isNew)
    #expect(form.level == "user", "Echo's own Team is saved at the human's level")
    #expect(form.description == "Everything on Kiro.")
    #expect(form.orchestratorCli == "kiro")
    #expect(form.rotateAt == "150000")
    #expect(form.workersModel == "claude-haiku-5.5")
    #expect(form.overrides.map(\.profile) == ["naruto", "sasuke"])
    #expect(form.overrides[0].effort == "high")
    #expect(form.overrides[0].cli == "")
    #expect(form.maxWorkers == 3)
    #expect(form.planApproval == true)
    #expect(form.review == false)
    #expect(form.instructions == "Keep reports short.")
}

@Test func aLoadedTeamSendsBackWhatItHad() throws {
    let params = TeamForm(team: kiroLean).saveParams(repo: nil)
    let sent = try #require(params["team"] as? [String: Any])
    #expect(try json(sent) == """
    {"description":"Everything on Kiro.","instructions":"Keep reports short.",\
    "orchestrator":{"cli":"kiro","effort":"medium","model":"claude-sonnet-5.5","rotateAt":150000},\
    "rules":{"maxWorkers":3,"mergeWithoutAsking":false,"planApproval":true,"review":false},\
    "workers":{"cli":"kiro","effort":"low","model":"claude-haiku-5.5","profiles":\
    {"naruto":{"effort":"high","model":"claude-sonnet-5.5"},"sasuke":{"effort":"medium","model":"claude-sonnet-5.5"}}}}
    """)
}

@Test func aBareTeamLoadsEmpty() {
    let form = TeamForm(team: Team(name: "bare", origin: "repo"))
    #expect(form.level == "repo")
    #expect(form.overrides.isEmpty)
    #expect(form.maxWorkers == nil)
    #expect(form.review == nil)
    #expect(form.fields.isEmpty)
}

@Test func aRepoTeamIsSavedWithItsRepo() throws {
    var form = TeamForm(team: Team(name: "mine", origin: "repo"))
    #expect(try json(form.saveParams(repo: "/r")) == #"{"level":"repo","name":"mine","repo":"\/r","team":{}}"#)
    form.level = "user"
    #expect(form.saveParams(repo: "/r")["repo"] == nil)
}

@Test func addingAnOverrideTakesTheFirstProfileNotYetSet() {
    var form = TeamForm()
    let profiles = ["lee", "naruto", "sasuke"]
    form.addOverride(from: profiles)
    form.addOverride(from: profiles)
    #expect(form.overrides.map(\.profile) == ["lee", "naruto"])
    form.overrides[1].model = "claude-sonnet-5.5"
    #expect(form.fields["workers"] != nil)
    form.addOverride(from: profiles)
    form.addOverride(from: profiles)
    #expect(form.overrides.count == 3, "No row is added once every Profile has one")
}

@Test func removingAnOverrideKeepsTheOthers() throws {
    var form = TeamForm()
    form.addOverride(from: ["lee", "naruto"])
    form.addOverride(from: ["lee", "naruto"])
    form.removeOverride(form.overrides[0].id)
    #expect(form.overrides.map(\.profile) == ["naruto"])
    form.addOverride(from: ["lee", "naruto"])
    #expect(form.overrides.map(\.profile) == ["naruto", "lee"])
    #expect(Set(form.overrides.map(\.id)).count == 2, "A new row never reuses a removed row's id")
    form.removeOverride(form.overrides[0].id)
    form.removeOverride(form.overrides[0].id)
    #expect(form.overrides.isEmpty)
    #expect(form.fields["workers"] == nil, "A Team with no override and no Worker setting has no workers group")
}

@Test func anOverrideWithNothingSetIsStillSent() throws {
    var form = TeamForm()
    form.addOverride(from: ["lee"])
    let workers = try #require(form.fields["workers"] as? [String: Any])
    #expect(try json(workers) == #"{"profiles":{"lee":{}}}"#)
}

@Test func aCopyIsNamedAfterItsOriginalAndIsNew() {
    let copy = TeamForm(copying: kiroLean, taking: ["kiro-lean", "claude-opus"])
    #expect(copy.name == "kiro-lean-copy")
    #expect(copy.isNew)
    #expect(copy.orchestratorModel == "claude-sonnet-5.5")
    #expect(copy.overrides.count == 2)
}

@Test func copyNamesCountUpFromTwo() {
    #expect(TeamForm.copyName(of: "lean", taking: []) == "lean-copy")
    #expect(TeamForm.copyName(of: "lean", taking: ["lean", "lean-copy"]) == "lean-copy-2")
    #expect(TeamForm.copyName(of: "lean", taking: ["lean-copy", "lean-copy-2"]) == "lean-copy-3")
    #expect(TeamForm.copyName(of: "lean-copy", taking: ["lean-copy"]) == "lean-copy-copy")
}

@Test func aCopyOfALongNameStaysWithinFortyCharacters() {
    let long = String(repeating: "a", count: 40)
    let first = TeamForm.copyName(of: long, taking: [])
    #expect(first.count == 40 && first.hasSuffix("-copy"))
    let second = TeamForm.copyName(of: long, taking: [first])
    #expect(second.count == 40 && second.hasSuffix("-copy-2"))
}

@Test func onlyARequiredFieldBlocksASave() {
    var form = TeamForm()
    #expect(form.blocker == "Name the Team.")
    form.name = "x"
    #expect(form.blocker == nil)
    form.maxWorkers = 0
    #expect(form.blocker == nil, "The daemon says what is wrong with a rule's value")
    form.rotateAt = "lots"
    #expect(form.blocker == "Renew at is a number of tokens, like 150000.")
    form.rotateAt = ""
    form.addOverride(from: ["lee"])
    form.overrides.append(TeamForm.Override(id: 99, profile: "lee"))
    #expect(form.blocker == "lee is set twice. Keep one row for each Profile.")
}

private let everyField = Team.Member(
    id: "build", action: "execute", profile: "naruto", instructions: "Small commits.", replaceRole: true,
    cli: "kiro", model: "claude-sonnet-5.5", effort: "high", tools: ["read", "write"], skills: ["tdd"],
    context: ["CONTEXT.md"], lessons: false, writes: true, worktree: "new")

private func crew(_ members: [Team.Member]) -> TeamForm {
    var form = TeamForm()
    form.name = "crew"
    form.members = members
    return form
}

private func member(_ id: String, _ action: String = "execute", after: String...) -> Team.Member {
    Team.Member(id: id, action: action, profile: "naruto", after: after.isEmpty ? nil : after.map { Team.HandOff(from: $0) })
}

private func member(_ id: String, _ action: String = "execute", handOffs: [Team.HandOff]) -> Team.Member {
    Team.Member(id: id, action: action, profile: "naruto", after: handOffs)
}

@Test func aFormSavedWithoutEditsSendsEveryMemberFieldBack() throws {
    let check = Team.Member(id: "check", action: "verify", profile: "sasuke", after: [Team.HandOff(from: "build")])
    let test = Team.Member(id: "test", action: "run", profile: "lee",
                           after: [Team.HandOff(from: "build", auto: true), Team.HandOff(from: "orchestrator")], x: -96, y: 272)
    let loaded = Team(name: "crew", origin: "user", members: [everyField, check, test])
    let params = TeamForm(team: loaded).saveParams(repo: nil)
    let sent = try #require(params["team"] as? [String: Any])
    let members = try #require(sent["members"] as? [[String: Any]])
    #expect(try json(members[0]) == """
    {"action":"execute","cli":"kiro","context":["CONTEXT.md"],"effort":"high","id":"build",\
    "instructions":"Small commits.","lessons":false,"model":"claude-sonnet-5.5","profile":"naruto",\
    "replaceRole":true,"skills":["tdd"],"tools":["read","write"],"worktree":"new","writes":true}
    """)
    #expect(try json(members[1]) == #"{"action":"verify","after":[{"from":"build"}],"id":"check","profile":"sasuke"}"#)
    #expect(try json(members[2])
        == #"{"action":"run","after":[{"auto":true,"from":"build"},{"from":"orchestrator"}],"id":"test","profile":"lee","x":-96,"y":272}"#)
    let decoded = try JSONDecoder().decode([Team.Member].self, from: JSONSerialization.data(withJSONObject: members))
    #expect(decoded == loaded.members, "What is sent decodes to the Members that were loaded")
}

@Test func membersAreSentInOrderAndOnlyWhenThereAreAny() throws {
    let form = crew([member("b"), member("a"), member("c", "run", after: "b")])
    let members = try #require(form.fields["members"] as? [[String: Any]])
    #expect(members.compactMap { $0["id"] as? String } == ["b", "a", "c"])
    #expect(TeamForm().fields["members"] == nil)
}

@Test func aMemberLeavesOutWhatIsUnset() throws {
    var blank = member("a")
    blank.instructions = "  \n"
    blank.model = ""
    blank.cli = " "
    let sent = try #require(crew([blank]).fields["members"] as? [[String: Any]])
    #expect(try json(sent[0]) == #"{"action":"execute","id":"a","profile":"naruto"}"#)
}

@Test func aFormFromAPureRoundTripIsNotChanged() {
    let team = Team(name: "crew", members: [everyField])
    let saved = TeamForm(team: team)
    var form = TeamForm(team: team)
    #expect(form == saved)
    form.addOverride(from: ["lee"])
    #expect(form != saved)
    form.removeOverride(form.overrides[0].id)
    #expect(form == saved, "A row added and removed again leaves no change, whatever the counter says")
    form.members[0].model = "other"
    #expect(form != saved)
}

@Test func aCopyKeepsTheMembers() {
    let copy = TeamForm(copying: Team(name: "crew", members: [everyField]), taking: [])
    #expect(copy.members == [everyField])
}

@Test func aSoundGraphHasNoBlocker() {
    let form = crew([member("a"), member("b", after: "a"), member("v", "verify", after: "b", "a"),
                     member("x", "custom"), member("r", "run", handOffs: [.init(from: "x", auto: true), .init(from: "b")]),
                     member("d", "scan", after: "r")])
    #expect(form.blocker == nil, "no depth limit, and a Member may come after several")
}

@Test func aBadMemberIdBlocks() {
    for id in ["", "Build", "-x", "a b", String(repeating: "a", count: 33)] {
        #expect(crew([member(id)]).blocker?.contains("An id is 1 to 32") == true, "\(id)")
    }
    #expect(crew([member(String(repeating: "a", count: 32)), member("0-9")]).blocker == nil)
}

@Test func twoMembersWithOneIdBlock() {
    #expect(crew([member("a"), member("a")]).blocker == "a: another Member has this id. Give each Member its own.")
}

@Test func aHandOffFromNoMemberBlocks() {
    #expect(crew([member("a", after: "ghost")]).blocker == #"a: it comes after "ghost", which is not a Member of this Team."#)
}

@Test func aMemberWithNoHandOffInBlocks() {
    #expect(crew([member("a", handOffs: [])]).blocker == "a: no Hand-off comes into it, so the Orchestrator cannot reach it.")
}

@Test func theOrchestratorsIdIsNotAMembers() {
    #expect(crew([member("orchestrator")]).blocker == "orchestrator is the Orchestrator's own id. Give the Member another.")
}

@Test func twoHandOffsFromOneMemberBlock() {
    let form = crew([member("a"), member("b", handOffs: [.init(from: "a"), .init(from: "a", auto: true)])])
    #expect(form.blocker == "b: two Hand-offs come from a.")
}

@Test func handOffsThatLoopBlock() {
    #expect(crew([member("a", after: "a")]).blocker == "a: its Hand-offs lead back to itself.")
    let loop = crew([member("a", after: "orchestrator", "c"), member("b", after: "a"), member("c", after: "b")])
    #expect(loop.blocker == "a: its Hand-offs lead back to itself.")
}

@Test func aVerifyMemberComesOnlyAfterExecuteMembers() {
    let message = "v: a verify Member comes only after execute Members."
    #expect(crew([member("v", "verify")]).blocker == message)
    #expect(crew([member("s", "scan"), member("v", "verify", after: "s")]).blocker == message)
    #expect(crew([member("e"), member("s", "scan"), member("v", "verify", after: "e", "s")]).blocker == message)
    #expect(crew([member("e"), member("v", "verify", after: "e")]).blocker == nil)
}

@Test func automaticHandOffsKeepTheirRules() {
    #expect(crew([member("a", handOffs: [.init(from: "orchestrator", auto: true)])]).blocker
        == "a: a Hand-off from the Orchestrator cannot be automatic.")
    #expect(crew([member("e"), member("v", "verify", handOffs: [.init(from: "e", auto: true)])]).blocker
        == "v: a Hand-off into a verify Member runs through --verify and cannot be automatic.")
    let twice = crew([member("a"), member("b"), member("c", "run", handOffs: [.init(from: "a", auto: true), .init(from: "b", auto: true)])])
    #expect(twice.blocker == "c: at most one automatic Hand-off comes into a Member.")
}

@Test func anUnknownActionBlocks() {
    #expect(crew([member("a", "deploy")]).blocker?.hasPrefix(#"a: "deploy" is not an Action."#) == true)
}

@Test func aMemberWithoutAProfileBlocks() {
    var bare = member("a")
    bare.profile = " "
    #expect(crew([bare]).blocker == "a: name the Profile it starts from.")
}

@Test func twentyFiveMembersBlock() {
    let ids = (0..<25).map { "m\($0)" }
    #expect(crew(ids.dropLast().map { member($0) }).blocker == nil)
    #expect(crew(ids.map { member($0) }).blocker == "A Team holds at most 24 Members; this one has 25.")
}

@Test func theNameIsAskedForBeforeTheTreeIsChecked() {
    var form = crew([member("a", after: "ghost")])
    form.name = ""
    #expect(form.blocker == "Name the Team.")
}
