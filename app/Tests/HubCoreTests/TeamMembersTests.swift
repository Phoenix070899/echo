import Foundation
import Testing
@testable import HubCore

/// scan, then build with its check after it, then run: the Standard Team.
private func standard() -> TeamForm {
    var form = TeamForm()
    form.name = "mine"
    form.members = [
        Team.Member(id: "scan", action: "scan", profile: "hinata"),
        Team.Member(id: "build", action: "execute", profile: "naruto"),
        Team.Member(id: "check", action: "verify", profile: "sasuke", after: [Team.HandOff(from: "build", auto: false)]),
        Team.Member(id: "run", action: "run", profile: "lee"),
    ]
    return form
}

private func profile(_ name: String, cli: String? = nil, model: String? = nil, effort: String? = nil) -> WorkerProfile {
    var found = WorkerProfile(name: name, description: "", model: model ?? "claude default", writes: false)
    found.ownCli = cli
    found.ownModel = model
    found.ownEffort = effort
    return found
}

// MARK: Rename

@Test func renamingAMemberPointsTheHandOffsFromItAtTheNewId() {
    var form = standard()
    #expect(form.renameMember("build", to: "write-code") == nil)
    #expect(form.members.map(\.id) == ["scan", "write-code", "check", "run"])
    #expect(form.member("check")?.after == [Team.HandOff(from: "write-code")])
    #expect(form.blocker == nil)
}

@Test func renamingToATakenOrBadIdIsRefusedAndChangesNothing() {
    var form = standard()
    let before = form.members
    #expect(form.renameMember("build", to: "scan")?.contains("another Member has this id") == true)
    #expect(form.renameMember("build", to: "Build Two")?.contains("lowercase letters") == true)
    #expect(form.renameMember("build", to: "-x") != nil)
    #expect(form.renameMember("build", to: "") != nil)
    #expect(form.renameMember("build", to: String(repeating: "a", count: 33)) != nil)
    #expect(form.renameMember("ghost", to: "other") != nil)
    #expect(form.members == before)
}

@Test func renamingToTheSameIdIsNotAChange() {
    var form = standard()
    let before = form
    #expect(form.renameMember("build", to: " build ") == nil)
    #expect(form == before)
}

// MARK: Action

@Test func changingAnActionKeepsTheTreeValid() {
    var form = standard()
    #expect(form.changeMemberAction("scan", to: "research") == nil)
    #expect(form.member("scan")?.action == "research")
    #expect(form.member("scan")?.profile == "hinata", "The Profile stays; it is offered, not swapped")
    #expect(form.blocker == nil)
}

@Test func anActionThatBreaksTheTreeIsRefused() {
    var form = standard()
    let before = form.members
    #expect(form.changeMemberAction("build", to: "run")?.contains("verify Member comes only after execute Members") == true,
            "A writer cannot change while a verifier comes after it")
    #expect(form.changeMemberAction("check", to: "verify") == nil)
    #expect(form.changeMemberAction("run", to: "verify")?.contains("comes only after execute Members") == true)
    #expect(form.changeMemberAction("scan", to: "deploy")?.contains("not an Action") == true)
    #expect(form.members == before)
}

@Test func aVerifierBecomesAnythingElseUnderItsWriter() {
    var form = standard()
    #expect(form.changeMemberAction("check", to: "custom") == nil)
    #expect(form.member("check")?.action == "custom")
}

@Test func theOfferedProfileIsTheActionsDefaultWhenItDiffers() {
    var form = standard()
    #expect(form.offeredProfile(for: "scan") == nil)
    _ = form.changeMemberAction("scan", to: "research")
    #expect(form.offeredProfile(for: "scan") == "jiraiya")
    form.updateMember("scan") { $0.profile = "jiraiya" }
    #expect(form.offeredProfile(for: "scan") == nil)
    _ = form.changeMemberAction("scan", to: "custom")
    #expect(form.offeredProfile(for: "scan") == nil, "custom has no default Profile")
    #expect(form.offeredProfile(for: "ghost") == nil)
    #expect(TeamForm.defaultProfile(for: "verify") == "sasuke")
    #expect(TeamForm.defaultProfile(for: "custom") == nil)
}

// MARK: Clearing

@Test func clearingAFieldTakesOnlyThatValueOut() {
    var form = standard()
    form.updateMember("build") {
        $0.cli = "kiro"
        $0.model = "claude-opus-5.5"
        $0.effort = "high"
    }
    let build = { form.member("build")! }
    #expect(MemberField.allCases.allSatisfy { build().isSet($0) })
    form.clearMember("build", .model)
    #expect(build().model == nil)
    #expect(build().isSet(.cli) && build().isSet(.effort))
    form.clearMember("build", .cli)
    form.clearMember("build", .effort)
    #expect(MemberField.allCases.allSatisfy { !build().isSet($0) })
    #expect(build() == Team.Member(id: "build", action: "execute", profile: "naruto"))
}

@Test func aMemberHoldsOnlyItsFlowAndWhatItRunsOn() throws {
    let text = #"{"id":"build","action":"execute","profile":"naruto","instructions":"x","tools":["Read"],"worktree":"new","model":"m"}"#
    let member = try JSONDecoder().decode(Team.Member.self, from: Data(text.utf8))
    #expect(member == Team.Member(id: "build", action: "execute", profile: "naruto", model: "m"),
            "the fields that moved into Profiles are not read (features/0094)")
}

@Test func clearingEditsTheDraftAndNothingElse() {
    var form = standard()
    form.updateMember("scan") { $0.model = "x" }
    form.clearMember("scan", .model)
    #expect(form.members == standard().members)
    form.clearMember("ghost", .model)
    #expect(form.members == standard().members)
}

// MARK: Custom Members

@Test func aCustomMemberIsNamedAfterItsProfileAfterTheOrchestrator() {
    var form = standard()
    #expect(form.addCustomMember(profile: "code-reviewer") == "code-reviewer")
    let added = form.members.last
    #expect(added?.id == "code-reviewer" && added?.action == "custom" && added?.profile == "code-reviewer")
    #expect(added?.after == nil && added?.x != nil, "it hangs from the Orchestrator, at a place on the canvas")
    #expect(form.addCustomMember(profile: "code-reviewer") == "code-reviewer-2")
    #expect(form.blocker == nil)
    #expect(form.addCustomMember(profile: "  ") == nil)
}

@Test func aCustomMemberCanComeAfterAMember() {
    var form = TeamForm()
    form.name = "tree"
    form.members = [Team.Member(id: "build", action: "execute", profile: "naruto")]
    #expect(form.addCustomMember(profile: "code-reviewer", after: "build") == "code-reviewer")
    #expect(form.members.last?.after == [Team.HandOff(from: "build")])
    #expect(form.addCustomMember(profile: "lost", after: "ghost") == nil)
    #expect(form.blocker == nil)
}

@Test func aFullTeamTakesNoCustomMember() {
    var form = TeamForm()
    form.name = "full"
    form.members = (0..<TeamForm.maxMembers).map { Team.Member(id: "m\($0)", action: "run", profile: "lee") }
    #expect(form.addCustomMember(profile: "extra") == nil)
    #expect(form.members.count == TeamForm.maxMembers)
}

// MARK: Where a value comes from

@Test func aMembersOwnChoiceComesFirst() {
    var form = standard()
    form.workersCli = "kiro"
    form.updateMember("build") { $0.cli = "claude" }
    let build = form.member("build")!
    let found = profile("naruto", cli: "claude", model: "anthropic/claude-sonnet-5-5", effort: "high")
    let defaults = MemberDefaults(cli: "kiro", model: "claude-sonnet-5.5")

    let cli = form.resolve(.cli, for: build, profile: found, defaults: defaults)
    #expect(cli == MemberValue("claude", from: .member))
    #expect(cli.sourceText == "this Member")
    #expect(cli.isOwn)

    form.clearMember("build", .cli)
    let workers = form.resolve(.cli, for: form.member("build")!, profile: found, defaults: defaults)
    #expect(workers == MemberValue("kiro", from: .teamWorkers))
    #expect(workers.sourceText == "this Team's Workers")
    #expect(!workers.isOwn)
}

@Test func belowTheTeamAProfileComesBeforeYourDefaults() {
    let form = standard()
    let build = form.member("build")!
    let found = profile("naruto", cli: "claude", model: "anthropic/claude-sonnet-5-5", effort: "high")
    let defaults = MemberDefaults(cli: "kiro", model: "claude-sonnet-5.5")
    let model = form.resolve(.model, for: build, profile: found, defaults: defaults)
    #expect(model == MemberValue("anthropic/claude-sonnet-5-5", from: .profile("naruto")))
    #expect(model.sourceText == "from naruto")
    #expect(form.resolve(.effort, for: build, profile: found, defaults: defaults) == MemberValue("high", from: .profile("naruto")))

    let bare = profile("naruto")
    let fallback = form.resolve(.model, for: build, profile: bare, defaults: defaults)
    #expect(fallback.sourceText == "your defaults")
    #expect(fallback.value == "claude-sonnet-5.5")
    #expect(form.resolve(.cli, for: build, profile: nil, defaults: defaults) == MemberValue("kiro", from: .defaults))
    #expect(form.resolve(.effort, for: build, profile: nil, defaults: defaults) == MemberValue("", from: .defaults))
}

@Test func forceCliSkipsTheProfileButNotWhatTheTeamNames() {
    var form = standard()
    let found = profile("naruto", cli: "claude", model: "anthropic/claude-sonnet-5-5", effort: "high")
    let defaults = MemberDefaults(cli: "kiro", model: "claude-haiku-5.5", forceCli: true)
    let build = form.member("build")!
    #expect(form.resolve(.cli, for: build, profile: found, defaults: defaults) == MemberValue("kiro", from: .defaults))
    #expect(form.resolve(.model, for: build, profile: found, defaults: defaults) == MemberValue("claude-haiku-5.5", from: .defaults))
    #expect(form.resolve(.effort, for: build, profile: found, defaults: defaults) == MemberValue("high", from: .profile("naruto")),
            "Only the CLI and model are forced")
    form.workersModel = "claude-sonnet-5.5"
    #expect(form.resolve(.model, for: build, profile: found, defaults: defaults) == MemberValue("claude-sonnet-5.5", from: .teamWorkers))
}

@Test func yourDefaultsReadFromTheSettings() throws {
    let settings = try JSONDecoder().decode(AgentSettings.self, from: Data("""
    {"cli":"kiro","model":"claude-sonnet-5.5","forceCli":true,
     "orchestrator":{"maxWorkers":3,"planApproval":true,"review":false,"mergeWithoutAsking":false}}
    """.utf8))
    #expect(MemberDefaults(settings: settings) == MemberDefaults(cli: "kiro", model: "claude-sonnet-5.5", forceCli: true))
    #expect(MemberDefaults(settings: nil) == MemberDefaults())
}

// MARK: The draft round trip

@Test func aMemberEditIsOnlyInTheDraftUntilItIsSaved() throws {
    let saved = standard()
    var form = saved
    form.updateMember("build") {
        $0.model = "claude-opus-5-5"
        $0.effort = "max"
    }
    #expect(form != saved)
    let members = try #require(form.fields["members"] as? [[String: Any]])
    let build = try #require(members.first { $0["id"] as? String == "build" })
    #expect(build["model"] as? String == "claude-opus-5-5")
    #expect(build["effort"] as? String == "max")
    form.clearMember("build", .model)
    form.clearMember("build", .effort)
    #expect(form == saved, "Clearing what was set puts the draft back to what was saved")
}
