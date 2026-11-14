import Testing
@testable import HubCore

private func member(_ id: String, _ action: String = "scan", under parent: String? = nil) -> Team.Member {
    let profile = Action.shipped.first { $0.id == action }?.profile ?? "mine"
    return Team.Member(id: id, action: action, profile: profile, parent: parent)
}

private func shape(_ members: [Team.Member]) -> [String] {
    members.map { "\($0.parent.map { "\($0)/" } ?? "")\($0.id)" }
}

/// scan, build > (check, notes), run.
private let sample = [
    member("scan"),
    member("build", "execute"),
    member("check", "verify", under: "build"),
    member("notes", "scan", under: "build"),
    member("run", "run"),
]

// MARK: Parsing

@Test func aMemberPayloadNamesTheMember() {
    #expect(DropPayload.parse("member:build") == .member("build"))
    #expect(DropPayload.parse("member:build-2") == .member("build-2"))
    #expect(DropPayload.member("build").text == "member:build")
}

@Test func aChipPayloadNamesTheActionAndTheProfile() {
    #expect(DropPayload.parse("chip:execute:naruto") == .chip(action: "execute", profile: "naruto"))
    #expect(DropPayload.parse("chip:scan:") == .chip(action: "scan", profile: nil))
    #expect(DropPayload.parse("chip:custom:") == .chip(action: "custom", profile: nil))
    #expect(DropPayload.parse("chip:custom:code-reviewer") == .chip(action: "custom", profile: "code-reviewer"))
    #expect(DropPayload.chip(action: "scan", profile: nil).text == "chip:scan:")
    #expect(DropPayload.chip(action: "scan", profile: "hinata").text == "chip:scan:hinata")
}

@Test func everyPayloadParsesBackFromItsText() {
    for payload in [DropPayload.member("a"), .chip(action: "verify", profile: "sasuke"), .chip(action: "custom", profile: nil)] {
        #expect(DropPayload.parse(payload.text) == payload)
    }
}

@Test func aStringThatIsNoPayloadParsesToNothing() {
    for text in ["", "member", "member:", "member:Build", "member:-a", "member:a:b", "member:a b",
                 "chip", "chip:", "chip:execute", "chip::naruto", "chip:fly:naruto", "chip:Execute:naruto",
                 "chip:execute:Not A Profile", "chip:execute:../etc", "chip:execute:naruto:extra",
                 "root:build", "/Users/me/file.txt", "build", "MEMBER:build"] {
        #expect(DropPayload.parse(text) == nil, "\(text)")
    }
}

@Test func theFilePreviewsOwnDragIsNotATreePayload() {
    #expect(DropPayload.parse("/Users/me/repo\nsrc/main.swift") == nil)
}

// MARK: The palette

@Test func theChipsAreTheSixActionsTheSixWorkersAndCustom() {
    let chips = Palette.chips()
    #expect(chips.count == 13)
    #expect(chips.filter { $0.kind == .action }.map(\.action) == Action.shippedIDs)
    #expect(chips.filter { $0.kind == .worker }.map(\.title) == ["naruto", "sasuke", "hinata", "jiraiya", "lee", "ino"])
    #expect(chips.last?.kind == .custom)
    #expect(chips.last?.payload == .chip(action: "custom", profile: nil))
}

@Test func aWorkerChipAddsTheActionThatWorkerIsTheDefaultOf() {
    let chips = Palette.chips().filter { $0.kind == .worker }
    #expect(chips.first { $0.title == "sasuke" }?.payload == .chip(action: "verify", profile: "sasuke"))
    #expect(chips.first { $0.title == "hinata" }?.payload == .chip(action: "scan", profile: "hinata"))
}

@Test func everyChipParsesBackAndHasItsOwnId() {
    let chips = Palette.chips()
    for chip in chips { #expect(DropPayload.parse(chip.payload.text) == chip.payload) }
    #expect(Set(chips.map(\.id)).count == chips.count)
}

// MARK: Zones

@Test func theTopQuarterIsBeforeTheMiddleIsChildAndTheBottomQuarterIsAfter() {
    #expect(DropSpot.at(row: "a", x: 60, y: 2, height: 36) == .onto("a", .before))
    #expect(DropSpot.at(row: "a", x: 60, y: 8.9, height: 36) == .onto("a", .before))
    #expect(DropSpot.at(row: "a", x: 60, y: 9.5, height: 36) == .onto("a", .child))
    #expect(DropSpot.at(row: "a", x: 60, y: 18, height: 36) == .onto("a", .child))
    #expect(DropSpot.at(row: "a", x: 60, y: 26, height: 36) == .onto("a", .child))
    #expect(DropSpot.at(row: "a", x: 60, y: 27.5, height: 36) == .onto("a", .after))
    #expect(DropSpot.at(row: "a", x: 60, y: 35, height: 36) == .onto("a", .after))
}

@Test func theLeftEdgeIsLevelOneWhateverTheHeight() {
    #expect(DropSpot.at(row: "a", x: 0, y: 18, height: 36) == .leftEdge("a"))
    #expect(DropSpot.at(row: "a", x: 13.9, y: 2, height: 36) == .leftEdge("a"))
    #expect(DropSpot.at(row: "a", x: 14, y: 18, height: 36) == .onto("a", .child))
}

@Test func aRowWithNoHeightYetIsDroppedOnAsAChild() {
    #expect(DropSpot.at(row: "a", x: 40, y: 0, height: 0) == .onto("a", .child))
}

// MARK: A Member dropped

@Test func aMemberDroppedOnAMemberBecomesItsChild() {
    let outcome = TeamTreeDrop.evaluate(.member("scan"), at: .onto("build", .child), in: sample)
    #expect(outcome.isOK)
    #expect(shape(outcome.members) == ["build", "build/check", "build/notes", "build/scan", "run"])
    #expect(outcome.selected == "scan")
    #expect(outcome.mark == .fill("build"))
}

@Test func aMemberDroppedBeforeOrAfterAMemberLandsAmongItsSiblings() {
    let before = TeamTreeDrop.evaluate(.member("run"), at: .onto("scan", .before), in: sample)
    #expect(shape(before.members) == ["run", "scan", "build", "build/check", "build/notes"])
    #expect(before.mark == .line(row: "scan", below: false, depth: 1))

    let after = TeamTreeDrop.evaluate(.member("run"), at: .onto("scan", .after), in: sample)
    #expect(shape(after.members) == ["scan", "run", "build", "build/check", "build/notes"])
    #expect(after.mark == .line(row: "scan", below: true, depth: 1))

    let deep = TeamTreeDrop.evaluate(.member("scan"), at: .onto("build", .after), in: sample)
    #expect(shape(deep.members) == ["build", "build/check", "build/notes", "scan", "run"])
    #expect(deep.mark == .line(row: "notes", below: true, depth: 1))
}

@Test func aMemberDroppedBetweenChildrenTakesTheirLevel() {
    let outcome = TeamTreeDrop.evaluate(.member("run"), at: .onto("notes", .before), in: sample)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "build/run", "build/notes"])
    #expect(outcome.mark == .line(row: "notes", below: false, depth: 2))
}

@Test func aMemberDroppedOnItsOwnSubtreeOrItselfIsRefusedAndNothingChanges() {
    let cycle = TeamTreeDrop.evaluate(.member("build"), at: .onto("notes", .child), in: sample)
    #expect(cycle.refusal == "build cannot move into its own subtree.")
    #expect(cycle.members == sample)
    #expect(cycle.selected == nil)

    let itself = TeamTreeDrop.evaluate(.member("scan"), at: .onto("scan", .child), in: sample)
    #expect(itself.refusal != nil)
    #expect(itself.members == sample)
}

@Test func aVerifyMemberOnlyGoesUnderAnExecuteMember() {
    let refused = TeamTreeDrop.evaluate(.member("check"), at: .onto("scan", .child), in: sample)
    #expect(refused.refusal == "check is a verify Member and needs an execute Member above it.")
    #expect(refused.members == sample)
    #expect(refused.mark == .fill("scan"))

    let between = TeamTreeDrop.evaluate(.member("check"), at: .onto("scan", .after), in: sample)
    #expect(between.refusal == "check is a verify Member and needs an execute Member above it.")
}

@Test func aDropThatMakesTheTreeTooDeepIsRefused() {
    let deep = [member("a", "execute"), member("b", "scan", under: "a"), member("c", "scan", under: "b"), member("d", "scan")]
    let outcome = TeamTreeDrop.evaluate(.member("d"), at: .onto("c", .child), in: deep)
    #expect(outcome.refusal == "The tree can be at most 3 deep; this drop would make it 4.")
    #expect(outcome.members == deep)
}

@Test func aMemberThatIsNotInTheTreeIsRefused() {
    let outcome = TeamTreeDrop.evaluate(.member("ghost"), at: .onto("scan", .child), in: sample)
    #expect(outcome.refusal == "That Member is not in the tree.")
    #expect(outcome.members == sample)
}

@Test func aMemberDroppedOnAMemberThatIsGoneIsRefused() {
    let outcome = TeamTreeDrop.evaluate(.member("scan"), at: .onto("ghost", .child), in: sample)
    #expect(outcome.refusal != nil)
    #expect(outcome.members == sample)
}

// MARK: The left edge and empty space

@Test func theLeftEdgePromotesAMemberToLevelOneJustAfterItsTopParent() {
    let outcome = TeamTreeDrop.evaluate(.member("notes"), at: .leftEdge("run"), in: sample)
    #expect(outcome.isOK)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "notes", "run"])
    #expect(outcome.selected == "notes")
    #expect(outcome.mark == .line(row: "notes", below: true, depth: 1))
}

@Test func theLeftEdgePromotesFromAnyDepth() {
    let deep = [member("a", "execute"), member("b", "execute", under: "a"), member("c", "scan", under: "b"), member("d")]
    let outcome = TeamTreeDrop.evaluate(.member("c"), at: .leftEdge("d"), in: deep)
    #expect(shape(outcome.members) == ["a", "a/b", "c", "d"])
}

@Test func theLeftEdgeRefusesAVerifyMemberWithTheReason() {
    let outcome = TeamTreeDrop.evaluate(.member("check"), at: .leftEdge("scan"), in: sample)
    #expect(outcome.refusal == "check is a verify Member and needs an execute Member above it.")
    #expect(outcome.members == sample)
}

@Test func theLeftEdgeSaysAMemberAtLevelOneIsAlreadyThere() {
    let outcome = TeamTreeDrop.evaluate(.member("run"), at: .leftEdge("build"), in: sample)
    #expect(outcome.refusal == "run is already at level 1.")
    #expect(outcome.members == sample)
}

@Test func emptySpaceMovesAMemberToTheEndOfLevelOne() {
    let outcome = TeamTreeDrop.evaluate(.member("notes"), at: .empty, in: sample)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "run", "notes"])
    #expect(outcome.mark == .line(row: "run", below: true, depth: 1))

    let first = TeamTreeDrop.evaluate(.member("scan"), at: .empty, in: sample)
    #expect(shape(first.members) == ["build", "build/check", "build/notes", "run", "scan"])
}

@Test func emptySpaceRefusesAMemberThatIsAlreadyLastAtLevelOne() {
    let outcome = TeamTreeDrop.evaluate(.member("run"), at: .empty, in: sample)
    #expect(outcome.refusal == "run is already there.")
    #expect(outcome.members == sample)
}

@Test func emptySpaceRefusesAVerifyMember() {
    let outcome = TeamTreeDrop.evaluate(.member("check"), at: .empty, in: sample)
    #expect(outcome.refusal == "check is a verify Member and needs an execute Member above it.")
}

// MARK: A chip dropped

private let scanChip = DropPayload.chip(action: "scan", profile: nil)

@Test func aChipDroppedOnAMemberAddsItsLastChild() {
    let outcome = TeamTreeDrop.evaluate(.chip(action: "scan", profile: "hinata"), at: .onto("build", .child), in: sample)
    #expect(outcome.isOK)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "build/notes", "build/scan-2", "run"])
    #expect(outcome.selected == "scan-2")
    #expect(outcome.parent == "build")
    #expect(outcome.mark == .fill("build"))
    #expect(outcome.members.first { $0.id == "scan-2" }?.profile == "hinata")
}

@Test func aChipTakesItsActionsDefaultProfileWhenItHasNone() {
    let outcome = TeamTreeDrop.evaluate(.chip(action: "research", profile: nil), at: .empty, in: sample)
    #expect(outcome.members.last?.id == "research")
    #expect(outcome.members.last?.profile == "jiraiya")
}

@Test func aChipDroppedBetweenRowsIsInsertedThere() {
    let before = TeamTreeDrop.evaluate(scanChip, at: .onto("build", .before), in: sample)
    #expect(shape(before.members) == ["scan", "scan-2", "build", "build/check", "build/notes", "run"])
    #expect(before.parent == nil)
    #expect(before.placement == DropPlacement(target: "build", position: .before))
    #expect(before.mark == .line(row: "build", below: false, depth: 1))

    let after = TeamTreeDrop.evaluate(scanChip, at: .onto("build", .after), in: sample)
    #expect(shape(after.members) == ["scan", "build", "build/check", "build/notes", "scan-2", "run"])
    #expect(after.mark == .line(row: "notes", below: true, depth: 1))

    let among = TeamTreeDrop.evaluate(scanChip, at: .onto("check", .after), in: sample)
    #expect(shape(among.members) == ["scan", "build", "build/check", "build/scan-2", "build/notes", "run"])
    #expect(among.parent == "build")
    #expect(among.selected == "scan-2")
}

@Test func aChipDroppedAfterTheLastSiblingIsStillAdded() {
    let outcome = TeamTreeDrop.evaluate(scanChip, at: .onto("run", .after), in: sample)
    #expect(outcome.isOK)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "build/notes", "run", "scan-2"])
    #expect(outcome.selected == "scan-2")
}

@Test func aChipDroppedOnEmptySpaceAddsAtLevelOne() {
    let outcome = TeamTreeDrop.evaluate(scanChip, at: .empty, in: sample)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "build/notes", "run", "scan-2"])
    #expect(outcome.parent == nil)
    #expect(outcome.placement == nil)
    #expect(outcome.mark == .line(row: "run", below: true, depth: 1))

    let first = TeamTreeDrop.evaluate(scanChip, at: .empty, in: [])
    #expect(shape(first.members) == ["scan"])
    #expect(first.mark == .root)
}

@Test func aChipDroppedAtTheLeftEdgeAddsAtLevelOneAfterTheTopParent() {
    let outcome = TeamTreeDrop.evaluate(scanChip, at: .leftEdge("notes"), in: sample)
    #expect(shape(outcome.members) == ["scan", "build", "build/check", "build/notes", "scan-2", "run"])
    #expect(outcome.mark == .line(row: "notes", below: true, depth: 1))
}

@Test func aVerifyChipNeedsAnExecuteMemberToGoUnder() {
    let chip = DropPayload.chip(action: "verify", profile: "sasuke")
    let refused = TeamTreeDrop.evaluate(chip, at: .onto("scan", .child), in: sample)
    #expect(refused.refusal == "A verify Member needs an execute Member above it.")
    #expect(refused.members == sample)

    #expect(TeamTreeDrop.evaluate(chip, at: .empty, in: sample).refusal != nil)
    #expect(TeamTreeDrop.evaluate(chip, at: .leftEdge("check"), in: sample).refusal != nil)
    #expect(TeamTreeDrop.evaluate(chip, at: .onto("scan", .before), in: sample).refusal != nil)

    let fine = TeamTreeDrop.evaluate(chip, at: .onto("check", .after), in: sample)
    #expect(fine.isOK)
    #expect(shape(fine.members) == ["scan", "build", "build/check", "build/verify", "build/notes", "run"])
}

@Test func aChipIsRefusedUnderTheDeepestLevelAndInAFullTeam() {
    let deep = [member("a", "execute"), member("b", "scan", under: "a"), member("c", "scan", under: "b")]
    let tooDeep = TeamTreeDrop.evaluate(scanChip, at: .onto("c", .child), in: deep)
    #expect(tooDeep.refusal == "c is at level 3, the deepest the tree goes, so nothing can go under it.")
    #expect(tooDeep.members == deep)

    let full = (0..<TeamForm.maxMembers).map { member("m\($0)") }
    let outcome = TeamTreeDrop.evaluate(scanChip, at: .empty, in: full)
    #expect(outcome.refusal == "A Team holds at most \(TeamForm.maxMembers) Members.")
    #expect(outcome.members == full)
}

@Test func aChipDroppedOnAMemberThatIsGoneIsRefused() {
    #expect(TeamTreeDrop.evaluate(scanChip, at: .onto("ghost", .child), in: sample).refusal != nil)
    #expect(TeamTreeDrop.evaluate(scanChip, at: .leftEdge("ghost"), in: sample).refusal != nil)
}

@Test func aCustomChipAsksForAProfileUntilItHasOne() {
    let chip = DropPayload.chip(action: "custom", profile: nil)
    let asks = TeamTreeDrop.evaluate(chip, at: .onto("check", .after), in: sample)
    #expect(asks.isOK)
    #expect(asks.asksForProfile)
    #expect(asks.members == sample)
    #expect(asks.parent == "build")
    #expect(asks.placement == DropPlacement(target: "check", position: .after))

    let named = TeamTreeDrop.evaluate(chip, at: .onto("check", .after), in: sample, customProfile: "code-reviewer")
    #expect(!named.asksForProfile)
    #expect(shape(named.members) == ["scan", "build", "build/check", "build/custom", "build/notes", "run"])
    #expect(named.members.first { $0.id == "custom" }?.profile == "code-reviewer")
}

@Test func aCustomChipIsStillJudgedByTheTreesRules() {
    let chip = DropPayload.chip(action: "custom", profile: nil)
    let deep = [member("a", "execute"), member("b", "scan", under: "a"), member("c", "scan", under: "b")]
    #expect(TeamTreeDrop.evaluate(chip, at: .onto("c", .child), in: deep).refusal != nil)
}

// MARK: Synthetic drops, as the view hands them over

@Test func aDroppedStringIsParsedAndDoneTheWayTheViewDoesIt() {
    func drop(_ text: String, _ spot: DropSpot) -> DropOutcome? {
        DropPayload.parse(text).map { TeamTreeDrop.evaluate($0, at: spot, in: sample) }
    }
    #expect(drop("member:run", .onto("scan", .before)).map { shape($0.members) } == ["run", "scan", "build", "build/check", "build/notes"])
    #expect(drop("chip:run:lee", .onto("build", .child))?.parent == "build")
    #expect(drop("chip:custom:", .empty)?.asksForProfile == true)
    #expect(drop("member:check", .leftEdge("notes"))?.refusal != nil)
    #expect(drop("nonsense", .empty) == nil)
}

// MARK: The Move to menu

@Test func aMemberCanBeMovedUnderEachMemberTheTreeAllowsAndToLevelOne() {
    #expect(TeamTreeDrop.moveDestinations(of: "notes", in: sample) == [nil, "scan", "check", "run"])
    #expect(TeamTreeDrop.moveDestinations(of: "scan", in: sample) == ["build", "check", "notes", "run"])
}

@Test func aVerifyMemberCanOnlyBeMovedUnderAnotherExecuteMember() {
    let two = sample + [member("build-2", "execute")]
    #expect(TeamTreeDrop.moveDestinations(of: "check", in: two) == ["build-2"])
    #expect(TeamTreeDrop.moveDestinations(of: "check", in: sample).isEmpty)
}

@Test func theMoveMenuHasNothingForAMemberThatIsNotThere() {
    #expect(TeamTreeDrop.moveDestinations(of: "ghost", in: sample).isEmpty)
}

@Test func movingUnderAParentOrToLevelOneIsTheSameAsADrop() {
    let under = TeamTreeDrop.move("scan", under: "build", in: sample)
    #expect(shape(under.members) == ["build", "build/check", "build/notes", "build/scan", "run"])
    let top = TeamTreeDrop.move("notes", under: nil, in: sample)
    #expect(shape(top.members) == ["scan", "build", "build/check", "run", "notes"])
}

@Test func everyMoveTheMenuOffersIsAllowed() {
    for member in sample {
        for parent in TeamTreeDrop.moveDestinations(of: member.id, in: sample) {
            #expect(TeamTreeDrop.move(member.id, under: parent, in: sample).isOK, "\(member.id) under \(parent ?? "level 1")")
        }
    }
}

@Test func aLevelOneAncestorIsFoundFromAnyDepth() {
    #expect(TeamTreeDrop.levelOneAncestor(of: "check", in: sample) == "build")
    #expect(TeamTreeDrop.levelOneAncestor(of: "build", in: sample) == "build")
    #expect(TeamTreeDrop.levelOneAncestor(of: "ghost", in: sample) == nil)
}
