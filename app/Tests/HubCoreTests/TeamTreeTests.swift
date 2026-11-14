import Foundation
import Testing
@testable import HubCore

private func member(_ id: String, _ action: String = "scan", under parent: String? = nil) -> Team.Member {
    let profile = Action.shipped.first { $0.id == action }?.profile ?? "mine"
    return Team.Member(id: id, action: action, profile: profile, parent: parent)
}

/// `id` for level 1 and `parent/id` below it, in order, so a tree reads as one line.
private func shape(_ members: [Team.Member]?) -> [String] {
    (members ?? []).map { "\($0.parent.map { "\($0)/" } ?? "")\($0.id)" }
}

/// scan, build > (check, notes), run.
private let sample = [
    member("scan"),
    member("build", "execute"),
    member("check", "verify", under: "build"),
    member("notes", "scan", under: "build"),
    member("run", "run"),
]

/// Whether every Member follows its parent and each subtree is the run of rows right after its Member.
private func isInTreeOrder(_ members: [Team.Member]) -> Bool {
    let rows = TeamTree.rows(members)
    for (at, row) in rows.enumerated() {
        if let parent = row.member.parent, !members[..<at].contains(where: { $0.id == parent }) { return false }
        let following = rows[(at + 1)...].prefix { $0.depth > row.depth }.map(\.member.id)
        if following != TeamTree.descendants(of: row.member.id, in: members).map(\.id) { return false }
    }
    return true
}

/// A chain three deep: a > b > c, then d.
private let chain = [member("a"), member("b", under: "a"), member("c", under: "b"), member("d")]

// MARK: Reading

@Test func rowsListEveryMemberWithItsDepth() {
    let rows = TeamTree.rows([member("scan"), member("build", "execute"), member("check", "verify", under: "build"),
                              member("deep", under: "check"), member("run", "run")])
    #expect(rows.map(\.member.id) == ["scan", "build", "check", "deep", "run"])
    #expect(rows.map(\.depth) == [1, 1, 2, 3, 1])
    #expect(TeamTree.rows([]).isEmpty)
}

@Test func descendantsFollowTheirMemberInTreeOrder() {
    #expect(TeamTree.descendants(of: "build", in: sample).map(\.id) == ["check", "notes"])
    #expect(TeamTree.descendants(of: "a", in: chain).map(\.id) == ["b", "c"])
    #expect(TeamTree.descendants(of: "run", in: sample).isEmpty)
    #expect(TeamTree.descendants(of: "nobody", in: sample).isEmpty)
}

// MARK: Add

@Test func addTakesItsIdAndProfileFromTheAction() throws {
    let added = try #require(TeamTree.add(action: "research", under: nil, to: sample))
    #expect(added.id == "research")
    #expect(shape(added.members) == shape(sample) + ["research"])
    let new = try #require(added.members.last)
    #expect(new.action == "research" && new.profile == "jiraiya")
    #expect(new.instructions == nil && new.model == nil && new.effort == nil && new.cli == nil)
    #expect(new.tools.isEmpty && new.skills.isEmpty && new.context.isEmpty && new.writes == nil)
}

@Test func addPutsTheMemberLastUnderItsParent() throws {
    let added = try #require(TeamTree.add(action: "run", under: "build", to: sample))
    #expect(added.id == "run-2")
    #expect(shape(added.members) == ["scan", "build", "build/check", "build/notes", "build/run-2", "run"])
}

@Test func addMakesTheIdUnique() throws {
    var members = sample
    for expected in ["scan-2", "scan-3", "scan-4"] {
        let added = try #require(TeamTree.add(action: "scan", to: members))
        #expect(added.id == expected)
        members = added.members
    }
}

@Test func addTakesAProfileForCustomAndRefusesCustomWithout() throws {
    #expect(TeamTree.add(action: Action.custom, to: sample) == nil)
    let added = try #require(TeamTree.add(action: Action.custom, profile: "reviewer", to: sample))
    #expect(added.id == "custom" && added.members.last?.profile == "reviewer")
    let named = try #require(TeamTree.add(action: "scan", profile: "mine", to: sample))
    #expect(named.members.last?.profile == "mine")
}

@Test func addRefusesWhatTheRulesRefuse() {
    #expect(TeamTree.add(action: "verify", under: nil, to: sample) == nil)
    #expect(TeamTree.add(action: "verify", under: "scan", to: sample) == nil)
    #expect(TeamTree.add(action: "verify", under: "build", to: sample)?.id == "verify")
    #expect(TeamTree.add(action: "scan", under: "nobody", to: sample) == nil)
    #expect(TeamTree.add(action: "scan", under: "c", to: chain) == nil, "a fourth level")
    #expect(TeamTree.add(action: "scan", under: "b", to: chain)?.id == "scan")
    #expect(TeamTree.add(action: "nonsense", profile: "x", to: sample) == nil)
    let full = (0..<TeamForm.maxMembers).map { member("m\($0)") }
    #expect(TeamTree.add(action: "scan", to: full) == nil)
    #expect(TeamTree.add(action: "scan", to: Array(full.dropLast()))?.members.count == TeamForm.maxMembers)
}

@Test func addToAnEmptyTeamMakesTheFirstMember() throws {
    let added = try #require(TeamTree.add(action: "execute", to: []))
    #expect(shape(added.members) == ["execute"])
}

// MARK: Remove

@Test func removeTakesTheMemberAndItsDescendantsAndReturnsThem() throws {
    let result = try #require(TeamTree.remove("build", from: sample))
    #expect(shape(result.members) == ["scan", "run"])
    #expect(result.removed.map(\.id) == ["build", "check", "notes"])
}

@Test func removeOfALeafTakesOnlyIt() throws {
    let result = try #require(TeamTree.remove("check", from: sample))
    #expect(shape(result.members) == ["scan", "build", "build/notes", "run"])
    #expect(result.removed == [sample[2]])
}

@Test func removeOfTheLastMemberLeavesAnEmptyTree() throws {
    let result = try #require(TeamTree.remove("scan", from: [member("scan")]))
    #expect(result.members.isEmpty)
}

@Test func removeOfAnUnknownMemberChangesNothing() {
    #expect(TeamTree.remove("nobody", from: sample) == nil)
}

// MARK: Duplicate

@Test func duplicateCopiesTheSubtreeRightAfterTheOriginal() throws {
    let copy = try #require(TeamTree.duplicate("build", in: sample))
    #expect(copy.id == "build-2")
    #expect(shape(copy.members) == [
        "scan", "build", "build/check", "build/notes", "build-2", "build-2/check-2", "build-2/notes-2", "run",
    ])
    #expect(copy.members.first { $0.id == "build-2" }?.profile == "naruto")
}

@Test func duplicateOfAChildStaysUnderTheSameParent() throws {
    let copy = try #require(TeamTree.duplicate("check", in: sample))
    #expect(copy.id == "check-2")
    #expect(shape(copy.members) == ["scan", "build", "build/check", "build/check-2", "build/notes", "run"])
}

@Test func duplicateKeepsEveryFieldButTheIdAndParent() throws {
    var writer = member("build", "execute")
    writer.model = "claude-sonnet-5.5"
    writer.instructions = "Small commits."
    writer.tools = ["Edit"]
    let copy = try #require(TeamTree.duplicate("build", in: [writer]))
    var expected = writer
    expected.id = "build-2"
    #expect(copy.members.last == expected)
}

@Test func duplicateCountsOnFromANumberedId() throws {
    var members = try #require(TeamTree.duplicate("scan", in: sample)).members
    #expect(members.contains { $0.id == "scan-2" })
    members = try #require(TeamTree.duplicate("scan-2", in: members)).members
    #expect(members.contains { $0.id == "scan-3" })
    #expect(Set(members.map(\.id)).count == members.count)
}

@Test func duplicateRefusesWhatWouldBeTooManyOrUnknown() {
    let full = (0..<TeamForm.maxMembers).map { member("m\($0)") }
    #expect(TeamTree.duplicate("m0", in: full) == nil)
    #expect(TeamTree.duplicate("nobody", in: sample) == nil)
    let almost = Array(full.prefix(23))
    #expect(TeamTree.duplicate("m0", in: almost)?.members.count == 24)
}

@Test func anIdKeepsWithinThirtyTwoCharacters() {
    let long = String(repeating: "a", count: 32)
    let id = TeamTree.uniqueID(from: long, taking: [long])
    #expect(id.count == 32 && id.hasSuffix("-2") && TeamForm.validID(id))
    #expect(TeamTree.uniqueID(from: "Custom Thing!", taking: []) == "customthing")
    #expect(TeamTree.uniqueID(from: "---", taking: []) == "member")
}

// MARK: Move

@Test func moveSwapsAmongSiblingsAndTheSubtreeGoesAlong() {
    #expect(shape(TeamTree.move("build", by: -1, in: sample)) == ["build", "build/check", "build/notes", "scan", "run"])
    #expect(shape(TeamTree.move("build", by: 1, in: sample)) == ["scan", "run", "build", "build/check", "build/notes"])
    #expect(shape(TeamTree.move("notes", by: -1, in: sample)) == ["scan", "build", "build/notes", "build/check", "run"])
    #expect(shape(TeamTree.move("check", by: 1, in: sample)) == ["scan", "build", "build/notes", "build/check", "run"])
}

@Test func moveStopsAtTheEndsAndAtOtherStepsThanOne() {
    #expect(TeamTree.move("scan", by: -1, in: sample) == nil)
    #expect(TeamTree.move("run", by: 1, in: sample) == nil)
    #expect(TeamTree.move("check", by: -1, in: sample) == nil, "it is the first child, not a level 1 Member")
    #expect(TeamTree.move("build", by: 0, in: sample) == nil)
    #expect(TeamTree.move("build", by: 2, in: sample) == nil)
    #expect(TeamTree.move("nobody", by: 1, in: sample) == nil)
}

// MARK: Indent and outdent

@Test func indentMakesTheMemberTheLastChildOfTheSiblingAbove() {
    #expect(shape(TeamTree.indent("run", in: sample)) == ["scan", "build", "build/check", "build/notes", "build/run"])
    #expect(shape(TeamTree.indent("build", in: sample)) == ["scan", "scan/build", "build/check", "build/notes", "run"])
}

@Test func indentNeedsASiblingAboveAndRoomBelow() {
    #expect(TeamTree.indent("scan", in: sample) == nil)
    #expect(TeamTree.indent("check", in: sample) == nil)
    #expect(shape(TeamTree.indent("d", in: chain)) == ["a", "a/b", "b/c", "a/d"])
    #expect(shape(TeamTree.indent("e", in: [member("a"), member("b", under: "a"), member("c", under: "b"), member("e", under: "a")]))
            == ["a", "a/b", "b/c", "b/e"])
    #expect(TeamTree.indent("a", in: [member("x"), member("a"), member("b", under: "a"), member("c", under: "b")]) == nil,
            "the subtree would reach a fourth level")
}

@Test func indentOfAVerifyMemberNeedsAnExecuteAbove() {
    #expect(shape(TeamTree.indent("w2", in: [member("w", "execute"), member("w2", "execute")])) == ["w", "w/w2"])
    let members = [member("w", "execute"), member("a", under: "w"), member("v", "verify", under: "w")]
    #expect(TeamTree.indent("v", in: members) == nil, "it would sit under a scan Member")
}

@Test func outdentPutsTheMemberRightAfterItsParent() {
    #expect(shape(TeamTree.outdent("notes", in: sample)) == ["scan", "build", "build/check", "notes", "run"])
    #expect(shape(TeamTree.outdent("c", in: chain)) == ["a", "a/b", "a/c", "d"])
}

@Test func outdentOfAVerifyMemberIsRefusedAndLevelOneHasNothingToOutdent() {
    #expect(TeamTree.outdent("check", in: sample) == nil)
    #expect(TeamTree.outdent("scan", in: sample) == nil)
    #expect(TeamTree.outdent("nobody", in: sample) == nil)
}

@Test func outdentKeepsTheSubtreeWithTheMember() {
    let members = [member("a"), member("b", under: "a"), member("c", under: "b")]
    #expect(shape(TeamTree.outdent("b", in: members)) == ["a", "b", "b/c"])
}

// MARK: Drop

@Test func dropAsChildMakesTheMemberTheLastChild() {
    #expect(shape(TeamTree.drop("run", onto: "build", as: .child, in: sample)) == ["scan", "build", "build/check", "build/notes", "build/run"])
    #expect(shape(TeamTree.drop("scan", onto: "run", as: .child, in: sample)) == ["build", "build/check", "build/notes", "run", "run/scan"])
}

@Test func dropBeforeAndAfterPutTheMemberAmongTheTargetsSiblings() {
    #expect(shape(TeamTree.drop("run", onto: "scan", as: .before, in: sample)) == ["run", "scan", "build", "build/check", "build/notes"])
    #expect(shape(TeamTree.drop("run", onto: "scan", as: .after, in: sample)) == ["scan", "run", "build", "build/check", "build/notes"])
    #expect(shape(TeamTree.drop("scan", onto: "build", as: .after, in: sample)) == ["build", "build/check", "build/notes", "scan", "run"])
    #expect(shape(TeamTree.drop("scan", onto: "notes", as: .before, in: sample)) == ["build", "build/check", "build/scan", "build/notes", "run"])
}

@Test func dropAfterAMemberWithChildrenLandsBelowItsSubtree() {
    let members = [member("build", "execute"), member("check", "verify", under: "build"), member("run", "run"),
                   member("scan")]
    #expect(shape(TeamTree.drop("scan", onto: "build", as: .after, in: members)) == ["build", "build/check", "scan", "run"])
    #expect(shape(TeamTree.drop("scan", onto: "build", as: .after, in: sample)) == ["build", "build/check", "build/notes", "scan", "run"])
}

@Test func dropToLevelOneByDroppingBesideALevelOneMember() {
    #expect(shape(TeamTree.drop("notes", onto: "run", as: .before, in: sample)) == ["scan", "build", "build/check", "notes", "run"])
}

@Test func aDroppedSubtreeTravelsWithItsMember() {
    #expect(shape(TeamTree.drop("build", onto: "scan", as: .before, in: sample)) == ["build", "build/check", "build/notes", "scan", "run"])
    #expect(shape(TeamTree.drop("build", onto: "run", as: .child, in: sample)) == ["scan", "run", "run/build", "build/check", "build/notes"])
}

@Test func aDropOnAPlaceItAlreadyHasIsRefused() {
    #expect(TeamTree.canDrop("scan", onto: "scan", as: .before, in: sample) == .refused("scan is already there."))
    #expect(TeamTree.canDrop("scan", onto: "build", as: .before, in: sample) == .refused("scan is already there."))
    #expect(TeamTree.canDrop("build", onto: "scan", as: .after, in: sample) == .refused("build is already there."))
    #expect(TeamTree.canDrop("notes", onto: "build", as: .child, in: sample) == .refused("notes is already there."))
    #expect(TeamTree.canDrop("check", onto: "notes", as: .before, in: sample) == .refused("check is already there."))
    #expect(TeamTree.drop("scan", onto: "build", as: .before, in: sample) == nil)
}

@Test func aMemberCannotBeItsOwnChild() {
    let verdict = TeamTree.canDrop("build", onto: "build", as: .child, in: sample)
    #expect(verdict == .refused("build cannot become its own child: its parents would lead back to itself."))
    #expect(TeamTree.drop("build", onto: "build", as: .child, in: sample) == nil)
}

@Test func aMemberCannotMoveIntoItsOwnSubtree() {
    let reason = "build cannot move into its own subtree."
    #expect(TeamTree.canDrop("build", onto: "check", as: .child, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("build", onto: "notes", as: .before, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("a", onto: "c", as: .child, in: chain) == .refused("a cannot move into its own subtree."))
    #expect(TeamTree.drop("a", onto: "c", as: .after, in: chain) == nil)
}

@Test func aDroppedVerifyMemberNeedsAnExecuteParent() {
    let reason = "check is a verify Member and needs an execute Member above it."
    #expect(TeamTree.canDrop("check", onto: "scan", as: .child, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("check", onto: "scan", as: .before, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("check", onto: "build", as: .before, in: sample) == .refused(reason))
    #expect(shape(TeamTree.drop("check", onto: "build", as: .child, in: sample)) == ["scan", "build", "build/notes", "build/check", "run"])
    let two = sample + [member("build2", "execute")]
    #expect(shape(TeamTree.drop("check", onto: "build2", as: .child, in: two)) == ["scan", "build", "build/notes", "run", "build2", "build2/check"])
    #expect(TeamTree.canDrop("check", onto: "run", as: .after, in: two) == .refused(reason))
}

@Test func theTreeCannotBecomeDeeperThanThree() {
    #expect(TeamTree.canDrop("d", onto: "c", as: .child, in: chain)
            == .refused("The tree can be at most 3 deep; this drop would make it 4."))
    #expect(TeamTree.canDrop("b", onto: "d", as: .child, in: chain).isOK)
    #expect(TeamTree.canDrop("d", onto: "b", as: .child, in: chain).isOK)
    #expect(TeamTree.canDrop("d", onto: "c", as: .after, in: chain).isOK, "beside c is depth 3")
    #expect(TeamTree.drop("d", onto: "c", as: .child, in: chain) == nil)
}

@Test func aSubtreeCountsWithItsOwnHeightAgainstTheLimit() {
    let members = [member("top"), member("mid", under: "top"), member("x"), member("y", under: "x")]
    #expect(TeamTree.canDrop("x", onto: "mid", as: .child, in: members)
            == .refused("The tree can be at most 3 deep; this drop would make it 4."))
    #expect(TeamTree.canDrop("x", onto: "top", as: .child, in: members).isOK)
    #expect(TeamTree.canDrop("y", onto: "mid", as: .child, in: members).isOK)
}

@Test func aDropWithAnUnknownMemberIsRefused() {
    let reason = "That Member is not in the tree."
    #expect(TeamTree.canDrop("nobody", onto: "scan", as: .child, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("scan", onto: "nobody", as: .child, in: sample) == .refused(reason))
    #expect(TeamTree.canDrop("scan", onto: "nobody", as: .child, in: sample).reason == reason)
    #expect(TeamTree.canDrop("scan", onto: "run", as: .child, in: sample).reason == nil)
}

@Test func canDropAndDropAgree() {
    for id in sample.map(\.id) {
        for target in sample.map(\.id) {
            for position in [TeamTree.Position.child, .before, .after] {
                let verdict = TeamTree.canDrop(id, onto: target, as: position, in: sample)
                let result = TeamTree.drop(id, onto: target, as: position, in: sample)
                #expect(verdict.isOK == (result != nil), "\(id) \(target) \(position)")
                if let result { #expect(TeamTree.isValid(result)) }
            }
        }
    }
}

// MARK: Order and invalid input

@Test func everyOperationWritesTheTreeBackInTreeOrder() throws {
    let scrambled = [member("check", "verify", under: "build"), member("scan"), member("build", "execute")]
    let moved = try #require(TeamTree.move("build", by: -1, in: scrambled))
    #expect(shape(moved) == ["build", "build/check", "scan"])
    #expect(isInTreeOrder(moved))
}

@Test func aTreeThatIsNotAValidTreeIsLeftAlone() {
    let cycle = [member("a", under: "b"), member("b", under: "a")]
    #expect(TeamTree.add(action: "scan", to: cycle) == nil)
    #expect(TeamTree.remove("a", from: cycle) == nil)
    let orphan = [member("a", under: "ghost")]
    #expect(TeamTree.duplicate("a", in: orphan) == nil)
    let twins = [member("a"), member("a")]
    #expect(TeamTree.move("a", by: 1, in: twins) == nil)
}

// MARK: The property

/// A small deterministic generator, so a failing run can be run again.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func fiveHundredRandomOperationsNeverYieldAnInvalidTree() throws {
    var random = SplitMix64(state: 20_261_114)
    var members = TeamTemplate.standard.members
    let actions = Action.shippedIDs + [Action.custom]
    var applied = 0
    var refused = 0
    for step in 0..<500 {
        let ids = members.map(\.id)
        func pick() -> String { ids.randomElement(using: &random) ?? "nobody" }
        let before = members
        var next: [Team.Member]?
        switch Int.random(in: 0..<8, using: &random) {
        case 0:
            let parent = Bool.random(using: &random) ? pick() : nil
            let action = actions.randomElement(using: &random) ?? "scan"
            next = TeamTree.add(action: action, profile: "mine", under: parent, to: members)?.members
        case 1: next = TeamTree.remove(pick(), from: members)?.members
        case 2: next = TeamTree.duplicate(pick(), in: members)?.members
        case 3: next = TeamTree.move(pick(), by: Bool.random(using: &random) ? 1 : -1, in: members)
        case 4: next = TeamTree.indent(pick(), in: members)
        case 5: next = TeamTree.outdent(pick(), in: members)
        default:
            let position = [TeamTree.Position.child, .before, .after].randomElement(using: &random) ?? .child
            let (id, target) = (pick(), pick())
            let verdict = TeamTree.canDrop(id, onto: target, as: position, in: members)
            next = TeamTree.drop(id, onto: target, as: position, in: members)
            #expect(verdict.isOK == (next != nil), "step \(step): the verdict and the drop disagree")
        }
        if let next {
            applied += 1
            #expect(TeamTree.isValid(next), "step \(step) made an invalid tree")
            #expect(isInTreeOrder(next), "step \(step) left the tree out of order")
            #expect(Set(next.map(\.id)).count == next.count)
            members = next
        } else {
            refused += 1
            #expect(members == before)
        }
        if members.isEmpty, let seeded = TeamTree.add(action: "execute", to: members) { members = seeded.members }
    }
    #expect(applied > 150 && refused > 50, "applied \(applied), refused \(refused)")
}
