import Foundation
import Testing
@testable import HubCore

/// scan, then build with its check under it, then run: the Standard Team's tree.
private func standard() -> TeamForm {
    var form = TeamForm()
    form.name = "mine"
    form.members = [
        Team.Member(id: "scan", action: "scan", profile: "hinata"),
        Team.Member(id: "build", action: "execute", profile: "naruto"),
        Team.Member(id: "check", action: "verify", profile: "sasuke", parent: "build"),
        Team.Member(id: "run", action: "run", profile: "lee"),
    ]
    return form
}

private func profile(_ name: String, cli: String? = nil, model: String? = nil, effort: String? = nil,
                     tools: [String]? = nil, writes: Bool = false) -> WorkerProfile {
    var found = WorkerProfile(name: name, description: "", model: model ?? "claude default", writes: writes)
    found.ownCli = cli
    found.ownModel = model
    found.ownEffort = effort
    found.tools = tools
    return found
}

// MARK: Rename

@Test func renamingAMemberPointsItsChildrenAtTheNewId() {
    var form = standard()
    #expect(form.renameMember("build", to: "write-code") == nil)
    #expect(form.members.map(\.id) == ["scan", "write-code", "check", "run"])
    #expect(form.member("check")?.parent == "write-code")
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
    #expect(form.changeMemberAction("build", to: "run")?.contains("verify Member sits under an execute Member") == true,
            "A writer cannot change while a verifier sits under it")
    #expect(form.changeMemberAction("check", to: "verify") == nil)
    #expect(form.changeMemberAction("run", to: "verify")?.contains("sits under an execute Member") == true)
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
        $0.instructions = "Keep diffs small."
        $0.replaceRole = true
        $0.model = "claude-opus-5-5"
        $0.tools = ["Read"]
        $0.skills = ["a"]
        $0.context = ["CLAUDE.md"]
        $0.lessons = false
        $0.writes = true
        $0.worktree = "new"
    }
    let build = { form.member("build")! }
    #expect(MemberField.allCases.allSatisfy { build().isSet($0) || $0 == .cli || $0 == .effort })
    form.clearMember("build", .model)
    #expect(build().model == nil)
    #expect(build().isSet(.instructions) && build().isSet(.tools))
    form.clearMember("build", .instructions)
    #expect(build().instructions == nil && build().replaceRole == nil, "The replace choice goes with the instruction")
    form.clearMember("build", .tools)
    form.clearMember("build", .skills)
    form.clearMember("build", .context)
    form.clearMember("build", .lessons)
    form.clearMember("build", .writes)
    form.clearMember("build", .worktree)
    #expect(MemberField.allCases.allSatisfy { !build().isSet($0) })
    #expect(build() == Team.Member(id: "build", action: "execute", profile: "naruto"))
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

@Test func aCustomMemberIsNamedAfterItsProfileAtLevelOne() {
    var form = standard()
    #expect(form.addCustomMember(profile: "code-reviewer") == "code-reviewer")
    #expect(form.members.last == Team.Member(id: "code-reviewer", action: "custom", profile: "code-reviewer"))
    #expect(form.addCustomMember(profile: "code-reviewer") == "code-reviewer-2")
    #expect(form.blocker == nil)
    #expect(form.addCustomMember(profile: "  ") == nil)
}

@Test func aCustomMemberCanGoUnderAMember() {
    var form = TeamForm()
    form.name = "tree"
    form.members = [Team.Member(id: "build", action: "execute", profile: "naruto")]
    #expect(form.addCustomMember(profile: "code-reviewer", under: "build") == "code-reviewer")
    #expect(form.members.last?.parent == "build")
    #expect(form.addCustomMember(profile: "lost", under: "ghost") == nil)
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
    form.addOverride(from: ["naruto"])
    form.overrides[0].cli = "codex"
    form.updateMember("build") { $0.cli = "claude" }
    let build = form.member("build")!
    let found = profile("naruto", cli: "claude", model: "anthropic/claude-sonnet-5-5", effort: "high")
    let defaults = MemberDefaults(cli: "kiro", model: "claude-sonnet-5.5")

    let cli = form.resolve(.cli, for: build, profile: found, defaults: defaults)
    #expect(cli == MemberValue("claude", from: .member))
    #expect(cli.sourceText == "this Member")
    #expect(cli.isOwn)

    form.clearMember("build", .cli)
    let apart = form.resolve(.cli, for: form.member("build")!, profile: found, defaults: defaults)
    #expect(apart == MemberValue("codex", from: .teamProfile("naruto")))
    #expect(apart.sourceText == "this Team, set apart for naruto")

    form.overrides.removeAll()
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

@Test func aListIsTheMembersOwnOrTheProfiles() {
    var form = standard()
    let found = profile("naruto", tools: ["Read", "Grep", "Edit"])
    let build = form.member("build")!
    #expect(build.listValue(.tools, profile: found) == MemberValue(["Read", "Grep", "Edit"], from: .profile("naruto")))
    form.updateMember("build") { $0.tools = ["Read"] }
    let own = form.member("build")!.listValue(.tools, profile: found)
    #expect(own == MemberValue(["Read"], from: .member))
    #expect(own.sourceText == "this Member")
    #expect(build.listValue(.skills, profile: nil) == MemberValue([], from: .profile("naruto")))
}

@Test func theOtherFieldsSayWhereTheyComeFrom() {
    var build = Team.Member(id: "build", action: "execute", profile: "naruto")
    #expect(build.lessonsValue == MemberValue(true, from: .standard))
    #expect(build.lessonsValue.sourceText == "the default")
    build.lessons = false
    #expect(build.lessonsValue == MemberValue(false, from: .member))

    #expect(build.writesValue(profile: profile("naruto", writes: true)) == MemberValue(true, from: .profile("naruto")))
    build.writes = false
    #expect(build.writesValue(profile: profile("naruto", writes: true)) == MemberValue(false, from: .member))

    #expect(build.worktreeValue() == MemberValue("new", from: .action("execute")))
    #expect(build.worktreeValue().sourceText == "from the execute Action")
    build.worktree = "current"
    #expect(build.worktreeValue() == MemberValue("current", from: .member))
    let custom = Team.Member(id: "x", action: "custom", profile: "x")
    #expect(custom.worktreeValue() == MemberValue("current", from: .standard))
}

@Test func theInstructionNoteSaysWhatItDoesToTheRole() {
    var build = Team.Member(id: "build", action: "execute", profile: "naruto")
    #expect(build.instructionNote(roleOf: "naruto") == "Empty: naruto's role is used as it is.")
    build.instructions = "Keep diffs small."
    #expect(build.instructionNote(roleOf: "naruto") == "Added after naruto's role.")
    build.replaceRole = true
    #expect(build.instructionNote(roleOf: "naruto") == "Replaces naruto's role.")
}

@Test func yourDefaultsReadFromTheSettings() throws {
    let settings = try JSONDecoder().decode(AgentSettings.self, from: Data("""
    {"cli":"kiro","model":"claude-sonnet-5.5","forceCli":true,
     "orchestrator":{"maxWorkers":3,"planApproval":true,"review":false,"mergeWithoutAsking":false}}
    """.utf8))
    #expect(MemberDefaults(settings: settings) == MemberDefaults(cli: "kiro", model: "claude-sonnet-5.5", forceCli: true))
    #expect(MemberDefaults(settings: nil) == MemberDefaults())
}

// MARK: Tools

@Test func checkingAToolKeepsTheChecklistsOrder() {
    #expect(MemberTools.toggled(["Read", "Edit"], "Grep", on: true) == ["Read", "Grep", "Edit"])
    #expect(MemberTools.toggled(["Read", "Grep", "Edit"], "Grep", on: false) == ["Read", "Edit"])
    #expect(MemberTools.toggled(["Edit", "Read"], "Bash", on: true) == ["Read", "Edit", "Bash"])
    #expect(MemberTools.toggled(["Read"], "Read", on: true) == ["Read"])
}

@Test func theLastToolStaysChecked() {
    #expect(MemberTools.toggled(["Read"], "Read", on: false) == ["Read"],
            "An empty list would hand the choice back to the Profile")
}

@Test func aToolTheChecklistDoesNotKnowIsKept() {
    #expect(MemberTools.toggled(["Read", "NotebookEdit"], "Bash", on: true) == ["Read", "Bash", "NotebookEdit"])
    #expect(MemberTools.toggled(["Read", "NotebookEdit"], "Read", on: false) == ["NotebookEdit"])
}

@Test func codexIgnoresTheListAndClaudeUsesIt() {
    #expect(MemberTools.note(tools: ["Read", "Edit"], cli: "codex") == "Codex ignores a tool list and uses its own tools.")
    #expect(MemberTools.note(tools: [], cli: "codex") == nil)
    #expect(MemberTools.note(tools: ["Read", "Grep", "Glob"], cli: "claude") == nil)
}

@Test func kiroNamesTheToolsItCannotMap() {
    #expect(MemberTools.note(tools: ["Read", "Edit", "Bash"], cli: "kiro") == nil)
    #expect(MemberTools.note(tools: ["Read", "Grep"], cli: "kiro") == "Kiro has no Grep and leaves it out.")
    #expect(MemberTools.note(tools: ["Read", "Grep", "Glob", "Edit"], cli: "kiro") == "Kiro has no Grep and Glob and leaves them out.")
    #expect(MemberTools.note(tools: ["Grep", "Glob"], cli: "kiro") == "Kiro has no Grep and Glob, so it gets its whole set of tools.")
    #expect(MemberTools.note(tools: ["Glob"], cli: "kiro") == "Kiro has no Glob, so it gets its whole set of tools.")
}

@Test func theChecklistIsTheEightToolsTheRolesName() {
    #expect(MemberTools.all == ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "WebFetch", "WebSearch"])
}

// MARK: Comma lists

@Test func aCommaListIsTrimmedWithoutBlanksOrRepeats() {
    #expect(CommaList.parse(" CONTEXT.md ,, CLAUDE.md,CONTEXT.md , ") == ["CONTEXT.md", "CLAUDE.md"])
    #expect(CommaList.parse("") == [])
    #expect(CommaList.parse(" , ") == [])
    #expect(CommaList.parse("solo") == ["solo"])
}

@Test func aCommaListFormatsAndParsesBack() {
    let names = ["a", "b c", "d.md"]
    #expect(CommaList.format(names) == "a, b c, d.md")
    #expect(CommaList.parse(CommaList.format(names)) == names)
    #expect(CommaList.format([]) == "")
}

// MARK: The draft round trip

@Test func aMemberEditIsOnlyInTheDraftUntilItIsSaved() throws {
    let saved = standard()
    var form = saved
    form.updateMember("build") {
        $0.instructions = "Keep diffs small."
        $0.skills = CommaList.parse("a, b")
    }
    #expect(form != saved)
    let members = try #require(form.fields["members"] as? [[String: Any]])
    let build = try #require(members.first { $0["id"] as? String == "build" })
    #expect(build["instructions"] as? String == "Keep diffs small.")
    #expect(build["skills"] as? [String] == ["a", "b"])
    form.clearMember("build", .instructions)
    form.clearMember("build", .skills)
    #expect(form == saved, "Clearing what was set puts the draft back to what was saved")
}
