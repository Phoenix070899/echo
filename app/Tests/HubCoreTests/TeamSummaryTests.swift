import Testing
@testable import HubCore

private func member(_ id: String, _ action: String = "execute", parent: String? = nil, model: String? = nil) -> Team.Member {
    Team.Member(id: id, action: action, profile: "naruto", parent: parent, model: model)
}

@Test func changeCountCountsFieldsAndMembers() {
    var saved = TeamForm()
    saved.name = "lean"
    saved.members = [member("build"), member("check", "verify", parent: "build")]
    var form = saved
    #expect(form.changeCount(from: saved) == 0)
    form.description = "fast"
    form.orchestratorModel = "anthropic/claude-opus-5-5"
    #expect(form.changeCount(from: saved) == 2)
    form.members[1].model = "anthropic/claude-opus-5-5"
    form.members.append(member("notes", "scribe"))
    #expect(form.changeCount(from: saved) == 4)
    #expect(form.memberChanged("check", from: saved))
    #expect(form.memberChanged("notes", from: saved))
    #expect(!form.memberChanged("build", from: saved))
}

@Test func reorderedMembersCountOnce() {
    var saved = TeamForm()
    saved.members = [member("a"), member("b")]
    var form = saved
    form.members.reverse()
    #expect(form.changeCount(from: saved) == 1)
}

@Test func modelFamilies() {
    #expect(ModelMix.family("anthropic/claude-sonnet-5-5") == "sonnet")
    #expect(ModelMix.family("claude-haiku-5.5") == "haiku")
    #expect(ModelMix.family("openai/gpt-5.6-terra") == "gpt")
    #expect(ModelMix.family("") == "default")
}

@Test func tallyPutsTheMostFirst() {
    let mix = ModelMix.tally(["claude-opus-5-5", "anthropic/claude-sonnet-5-5", "claude-sonnet-5.5", "", "claude-haiku-5-5"])
    #expect(mix.map(\.family) == ["sonnet", "opus", "default", "haiku"])
    #expect(mix.map(\.count) == [2, 1, 1, 1])
}

@Test func nodeInitials() {
    #expect(ActionLook.initials("Write code") == "WC")
    #expect(ActionLook.initials("Research") == "RE")
    #expect(ActionLook.initials("Custom") == "CU")
}
