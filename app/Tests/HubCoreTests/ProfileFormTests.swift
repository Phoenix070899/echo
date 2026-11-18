import Foundation
import Testing
@testable import HubCore

/// naruto as `profiles.list` sends it: what it runs with here, and what its own file says.
private func naruto(level: String = "yours") throws -> WorkerProfile {
    try JSONDecoder().decode(WorkerProfile.self, from: Data("""
    {"name":"naruto","description":"Implementer.","face":"r01c01","writes":true,"lessons":false,"worktree":"new",
     "tools":["Bash","Read","Edit"],"skills":["tdd"],"context":["CONTEXT.md"],"role":"You implement.",
     "cli":"kiro","model":"claude-haiku-5.5","ownCli":"claude","ownModel":"anthropic/claude-sonnet-5-5",
     "effort":"low","ownEffort":"high","level":"\(level)","path":"/s/profiles/naruto.md","replaces":["built-in"]}
    """.utf8))
}

/// The payload as the JSON the daemon receives.
private func json(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}

@Test func aListedProfileFillsTheFormWithWhatItsOwnFileSays() throws {
    let form = ProfileForm(profile: try naruto())
    #expect((form.cli, form.model, form.effort) == ("claude", "anthropic/claude-sonnet-5-5", "high"),
            "the file's own, not what a Team or forceCli makes it run with")
    #expect(form.tools == ["Bash", "Read", "Edit"] && form.skills == ["tdd"] && form.context == ["CONTEXT.md"])
    #expect(!form.lessons && form.writes && form.worktree == "new")
    #expect(form.role == "You implement." && form.description == "Implementer.")
    #expect(form.face == "r01c01")
    #expect(!form.readOnly)
    #expect(ProfileForm(profile: try naruto(level: "built-in")).readOnly)
}

@Test func anOlderDaemonsProfileKeepsTheLessonsAndNoWorktree() {
    let old = WorkerProfile(name: "lee", description: "", model: "claude default", writes: false)
    let form = ProfileForm(profile: old)
    #expect(form.lessons && form.worktree.isEmpty && form.level == "built-in" && form.face.isEmpty)
}

@Test func theSaveSendsEveryFieldAndTheRole() throws {
    var form = ProfileForm(profile: try naruto())
    form.model = "  "
    form.description = " Builds. "
    let params = form.saveParams(repo: "/r")
    #expect(params["name"] as? String == "naruto" && params["level"] as? String == "yours")
    #expect(try json(params["fields"] as Any) == """
    {"cli":"claude","context":["CONTEXT.md"],"description":"Builds.","effort":"high","face":"r01c01","lessons":false,"model":"",\
    "role":"You implement.","skills":["tdd"],"tools":["Bash","Read","Edit"],"worktree":"new","writes":true}
    """)
}

@Test func anEmptyRoleOrATwoLineDescriptionBlocksASave() throws {
    var form = ProfileForm(profile: try naruto())
    #expect(form.blocker == nil)
    form.role = " \n "
    #expect(form.blocker?.contains("role") == true)
    form.role = "x"
    form.description = "one\ntwo"
    #expect(form.blocker == "The description is one line.")
    form.description = ""
    form.worktree = "far"
    #expect(form.blocker == "Worktree is current or new.")
}

@Test func changesAreCountedByField() throws {
    let saved = ProfileForm(profile: try naruto())
    var form = saved
    #expect(form.changeCount(from: saved) == 0)
    form.role += "\nMore."
    form.lessons = true
    form.tools = ProfileTools.toggled(form.tools, "Grep", on: true)
    form.face = "r06c05"
    #expect(form.changeCount(from: saved) == 4)
    #expect(form.tools == ["Read", "Grep", "Edit", "Bash"])
}

@Test func usedByListsTheTeamsAndMembersOnAProfile() {
    let teams = [
        Team(name: "claude-lean", origin: "shipped", members: [
            .init(id: "build", action: "execute", profile: "naruto"),
            .init(id: "build-ui", action: "execute", profile: "naruto"),
            .init(id: "check", action: "verify", profile: "sasuke"),
        ]),
        Team(name: "solo", origin: "user", members: [.init(id: "scan", action: "scan", profile: "hinata")]),
        Team(name: "mine", origin: "repo", members: [.init(id: "impl", action: "execute", profile: "naruto")]),
    ]
    #expect(ProfileUse.of("naruto", in: teams) == [
        ProfileUse(team: "claude-lean", origin: "shipped", members: ["build", "build-ui"]),
        ProfileUse(team: "mine", origin: "repo", members: ["impl"]),
    ])
    #expect(ProfileUse.of("lee", in: teams).isEmpty)
}

@Test func aProfileCopyNameFitsThirtyTwoCharacters() {
    #expect(ProfileForm.copyName(of: "naruto", taking: []) == "naruto-copy")
    #expect(ProfileForm.copyName(of: "naruto", taking: ["naruto-copy"]) == "naruto-copy-2")
    let long = ProfileForm.copyName(of: String(repeating: "a", count: 31) + "-b", taking: [])
    #expect(long.count <= 32 && long.hasSuffix("-copy") && ProfileForm.validName(long))
    #expect(!ProfileForm.validName("Bad Name") && ProfileForm.validName("code-reviewer"))
}

// MARK: Tools

@Test func checkingAToolKeepsTheChecklistsOrder() {
    #expect(ProfileTools.toggled(["Read", "Edit"], "Grep", on: true) == ["Read", "Grep", "Edit"])
    #expect(ProfileTools.toggled(["Read", "Grep", "Edit"], "Grep", on: false) == ["Read", "Edit"])
    #expect(ProfileTools.toggled(["Edit", "Read"], "Bash", on: true) == ["Read", "Edit", "Bash"])
    #expect(ProfileTools.toggled(["Read"], "Read", on: true) == ["Read"])
    #expect(ProfileTools.toggled([], "Read", on: true) == ["Read"])
}

@Test func theLastToolStaysChecked() {
    #expect(ProfileTools.toggled(["Read"], "Read", on: false) == ["Read"],
            "An empty list gives the Worker every tool of its CLI")
}

@Test func aToolTheChecklistDoesNotKnowIsKept() {
    #expect(ProfileTools.toggled(["Read", "NotebookEdit"], "Bash", on: true) == ["Read", "Bash", "NotebookEdit"])
    #expect(ProfileTools.toggled(["Read", "NotebookEdit"], "Read", on: false) == ["NotebookEdit"])
}

@Test func codexIgnoresTheListAndClaudeUsesIt() {
    #expect(ProfileTools.note(tools: ["Read", "Edit"], cli: "codex") == "Codex ignores a tool list and uses its own tools.")
    #expect(ProfileTools.note(tools: [], cli: "codex") == nil)
    #expect(ProfileTools.note(tools: ["Read", "Grep", "Glob"], cli: "claude") == nil)
}

@Test func kiroNamesTheToolsItCannotMap() {
    #expect(ProfileTools.note(tools: ["Read", "Edit", "Bash"], cli: "kiro") == nil)
    #expect(ProfileTools.note(tools: ["Read", "Grep"], cli: "kiro") == "Kiro has no Grep and leaves it out.")
    #expect(ProfileTools.note(tools: ["Read", "Grep", "Glob", "Edit"], cli: "kiro") == "Kiro has no Grep and Glob and leaves them out.")
    #expect(ProfileTools.note(tools: ["Grep", "Glob"], cli: "kiro") == "Kiro has no Grep and Glob, so it gets its whole set of tools.")
}

@Test func theChecklistIsTheEightToolsTheRolesName() {
    #expect(ProfileTools.all == ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "WebFetch", "WebSearch"])
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

// MARK: Skills

private let installed = [
    SkillOption(name: "graft", description: "Find code fast.", source: "yours"),
    SkillOption(name: "imagegen", description: "Make images.", source: "built-in"),
    SkillOption(name: "matt:tdd", description: "Red, green, refactor.", source: "plugin", plugin: "matt"),
    SkillOption(name: "release", description: "Ship it.", source: "repo"),
    SkillOption(name: "matt:grilling", description: "Grill the plan.", source: "plugin", plugin: "matt"),
]

@Test func theSkillChecklistGroupsByWhereEachComesFromWithTheMissingFirst() {
    let groups = ProfileSkills.groups(installed: installed, chosen: ["matt:tdd", "gone", "graft"])
    #expect(groups.map(\.title) == ["Not installed", "Yours", "This repo", "matt", "Built in"])
    #expect(groups[0].rows == [ProfileSkills.Row(name: "gone", description: "", installed: false)],
            "a named skill the CLI lacks stays in sight, so a save never drops it unseen")
    #expect(groups[3].rows.map(\.name) == ["matt:tdd", "matt:grilling"], "the daemon's order within a group")
    #expect(ProfileSkills.groups(installed: [], chosen: []).isEmpty)
}

@Test func theSkillFilterMatchesNameOrDescription() {
    let byName = ProfileSkills.groups(installed: installed, chosen: ["gone"], filter: " TDD ")
    #expect(byName.flatMap(\.rows).map(\.name) == ["matt:tdd"])
    let byAbout = ProfileSkills.groups(installed: installed, chosen: [], filter: "ship")
    #expect(byAbout.map(\.title) == ["This repo"])
}

@Test func checkingASkillAddsItLastAndUncheckingKeepsTheRestInOrder() {
    #expect(ProfileSkills.toggled(["b", "a"], "c", on: true) == ["b", "a", "c"])
    #expect(ProfileSkills.toggled(["b", "a", "c"], "a", on: false) == ["b", "c"])
    #expect(ProfileSkills.toggled(["b"], "b", on: true) == ["b"])
    #expect(ProfileSkills.none(cli: "kiro") == "Kiro has no skills.")
}

@Test func aBareNameIsOfferedTheOnePluginSkillWithThatName() {
    let groups = ProfileSkills.groups(installed: installed, chosen: ["tdd", "gone"])
    #expect(groups[0].rows.map(\.match) == ["matt:tdd", nil])
    let twice = installed + [SkillOption(name: "other:tdd", source: "plugin", plugin: "other")]
    #expect(ProfileSkills.match(for: "tdd", in: twice) == nil, "two plugins have it: no guess")
    #expect(ProfileSkills.match(for: "x:tdd", in: installed) == nil, "a prefixed name is not rewritten")
    #expect(ProfileSkills.replaced(["a", "tdd", "b"], "tdd", with: "matt:tdd") == ["a", "matt:tdd", "b"])
    #expect(ProfileSkills.replaced(["matt:tdd", "tdd"], "tdd", with: "matt:tdd") == ["matt:tdd"])
}

@Test func aSkillDecodesWithOrWithoutItsPlugin() throws {
    let skills = try JSONDecoder().decode([SkillOption].self, from: Data("""
    [{"name":"graft","description":"x","source":"yours"},
     {"name":"matt:tdd","description":"y","source":"plugin","plugin":"matt"}]
    """.utf8))
    #expect(skills[0].plugin == nil && ProfileSkills.title(of: skills[1]) == "matt")
}

@Test func aDraftFillsOnlyTheFieldsAnAgentMaySet() throws {
    var form = ProfileForm()
    form.name = "sai"
    form.cli = "codex"
    form.model = "openai/gpt-test"
    form.role = "Starter."
    let draft = try JSONDecoder().decode(ProfileDraft.self, from: Data("""
    {"fields": {"description": "Designs screens", "tools": ["Read"], "skills": ["frontend-design"],
                "context": ["CONTEXT.md"], "writes": true, "role": "You are Sai."},
     "summary": "Made a designer.", "dropped": ["Teleport"]}
    """.utf8))
    let drafted = form.applying(draft)
    #expect(drafted.role == "You are Sai." && drafted.writes && drafted.skills == ["frontend-design"])
    #expect(drafted.cli == "codex" && drafted.model == "openai/gpt-test", "what it runs on stays the human's")
    #expect(drafted.changeCount(from: form) == 6)
    #expect(draft.note == "Made a designer. Left out, as Echo does not offer them: Teleport.")
    #expect(form.draftForm["name"] as? String == "sai" && form.draftForm["cli"] == nil)
}

@Test func theDrafterIsTheRememberedCliWhileItIsSignedIn() {
    #expect(ProfileDrafter.cli(remembered: "codex", signedIn: ["claude", "codex"]) == "codex")
    #expect(ProfileDrafter.cli(remembered: "kiro", signedIn: ["claude", "codex"]) == "claude")
    let models = [ModelOption(id: "anthropic/claude-sonnet-5-5", name: "Sonnet 5.5")]
    #expect(ProfileDrafter.label(cli: "claude", model: "anthropic/claude-sonnet-5-5", models: models) == "Claude Code · Sonnet 5.5")
    #expect(ProfileDrafter.label(cli: "kiro", model: "", models: []) == "Kiro")
}
