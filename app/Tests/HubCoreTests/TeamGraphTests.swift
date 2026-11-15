import Foundation
import Testing
@testable import HubCore

private func member(_ id: String, _ action: String = "execute", after: [Team.HandOff]? = nil,
                    x: Int? = nil, y: Int? = nil) -> Team.Member {
    let profile = Action.shipped.first { $0.id == action }?.profile ?? "mine"
    return Team.Member(id: id, action: action, profile: profile, after: after, x: x, y: y)
}

private func from(_ id: String, auto: Bool = false) -> Team.HandOff { Team.HandOff(from: id, auto: auto) }

/// build, then check (verify) and test (run, automatic) after it, then notes after test.
private func chain() -> [Team.Member] {
    [member("build"), member("check", "verify", after: [from("build")]),
     member("test", "run", after: [from("build", auto: true)]), member("notes", "scribe", after: [from("test")])]
}

private func ids(_ members: [Team.Member]) -> [String] { members.map(\.id) }

// MARK: Layout

@Test func echoLaysOutRowsByTheLongestChainCentredUnderTheOrchestrator() {
    let at = TeamGraph.positions(chain())
    #expect(at["build"] == .init(x: -96, y: 136))
    #expect(at["check"] == .init(x: -208, y: 272) && at["test"] == .init(x: 8, y: 272))
    #expect(at["notes"] == .init(x: -96, y: 408))
    #expect(TeamGraph.orchestratorPoint == .init(x: -96, y: 0))
    for point in at.values { #expect(point.x % 8 == 0 && point.y % 8 == 0) }
}

@Test func aWideRowWrapsAndEachWrappedNodeSitsUnderAGap() {
    let members = ["a", "b", "c", "d", "e", "f", "g"].map { member($0) }
    let at = TeamGraph.positions(members)
    #expect(["a", "b", "c"].map { at[$0]!.y } == [136, 136, 136])
    #expect(["d", "e", "f"].map { at[$0]!.y } == [272, 272, 272] && at["g"]!.y == 408)
    let above = Set(["a", "b", "c"].map { at[$0]!.x })
    for id in ["d", "e", "f", "g"] {
        let centre = at[id]!.x + TeamGraph.nodeWidth / 2
        #expect(!above.contains { centre > $0 && centre < $0 + TeamGraph.nodeWidth }, "\(id) under a node")
    }
}

@Test func aMembersOwnPlaceIsKeptAndPlacingWritesEveryOne() {
    var members = chain()
    members[0].x = 400
    members[0].y = 40
    #expect(TeamGraph.positions(members)["build"] == .init(x: 400, y: 40))
    let placed = TeamGraph.placed(members)
    #expect(placed.allSatisfy { $0.x != nil && $0.y != nil })
    #expect(TeamGraph.positions(placed) == TeamGraph.positions(members))
}

@Test func aMemberAfterSeveralSitsBelowTheFurthest() {
    let members = [member("a"), member("b", after: [from("a")]), member("c", "run", after: [from("a"), from("b")])]
    #expect(TeamGraph.levels(members) == ["a": 1, "b": 2, "c": 3])
}

@Test func theLinesAreEveryHandOffAndAnUnreachableMemberIsFound() {
    #expect(TeamGraph.lines(chain()) == [
        .init(from: "orchestrator", to: "build", auto: false), .init(from: "build", to: "check", auto: false),
        .init(from: "build", to: "test", auto: true), .init(from: "test", to: "notes", auto: false),
    ])
    #expect(TeamGraph.unreachable(chain()).isEmpty)
    var cut = chain()
    cut[2].after = []
    #expect(TeamGraph.unreachable(cut) == ["test", "notes"])
}

@Test func aLineGoesDownWithRightAnglesOrRoundTheSide() {
    #expect(TeamGraph.route(from: .init(x: 0, y: 0), to: .init(x: 200, y: 136)) == [
        .init(x: 96, y: 64), .init(x: 96, y: 96), .init(x: 296, y: 96), .init(x: 296, y: 136),
    ])
    #expect(TeamGraph.route(from: .init(x: 0, y: 0), to: .init(x: 0, y: 80))[1].y == 72, "midway when the gap is short")
    // A node in a row between takes the line round it, in a lane half a step over.
    let round = TeamGraph.route(from: .init(x: 0, y: 0), to: .init(x: 0, y: 272), avoiding: [.init(x: 0, y: 136)])
    #expect(round == [.init(x: 96, y: 64), .init(x: 96, y: 96), .init(x: -12, y: 96), .init(x: -12, y: 240),
                      .init(x: 96, y: 240), .init(x: 96, y: 272)])
    let up = TeamGraph.route(from: .init(x: 0, y: 136), to: .init(x: 0, y: 0))
    #expect(up.count == 6 && up.first == .init(x: 96, y: 200) && up.last == .init(x: 96, y: 0))
    #expect(up[2].x == 208, "round the right of both nodes")
}

// MARK: Members

@Test func addingPutsTheMemberAfterThePickedOneWithAHint() {
    let edit = TeamGraph.add(action: "run", after: "build", to: chain())
    #expect(edit.notice == nil && edit.selected == "run")
    let added = edit.members.last!
    #expect(added.after == [from("build")] && added.profile == "lee")
    #expect(added.y == 272 && added.x.map { $0 % 8 } == 0, "a row under build, in a free place")
    let below = edit.members.filter { $0.y == 272 && $0.id != "run" }
    #expect(below.allSatisfy { abs($0.x! - added.x!) >= TeamGraph.nodeWidth })
    #expect(edit.members.allSatisfy { $0.x != nil }, "the others keep where Echo had laid them out")
}

@Test func addingWithNothingPickedHangsItFromTheOrchestrator() {
    let edit = TeamGraph.add(action: "scan", after: nil, to: [])
    #expect(edit.members == [Team.Member(id: "scan", action: "scan", profile: "hinata", x: -96, y: 136)])
    #expect(TeamGraph.add(action: "scan", after: nil, to: edit.members).selected == "scan-2")
}

@Test func addingIsRefusedWithItsReason() {
    #expect(TeamGraph.add(action: "verify", after: "test", to: chain()).notice
        == "A verify Member comes after an execute Member. Pick one first.")
    #expect(TeamGraph.add(action: "deploy", after: nil, to: []).notice == #""deploy" is not an Action."#)
    #expect(TeamGraph.add(action: "custom", after: nil, to: []).notice?.contains("Profile of its own") == true)
    let full = (0..<24).map { member("m\($0)") }
    #expect(TeamGraph.add(action: "scan", after: nil, to: full).notice == "A Team holds at most 24 Members.")
}

@Test func aCopySitsBesideTheOriginalWithItsHandOffsInAsHints() {
    let edit = TeamGraph.duplicate("test", in: chain())
    #expect(edit.selected == "test-2" && edit.notice == nil)
    #expect(ids(edit.members) == ["build", "check", "test", "test-2", "notes"])
    let copy = edit.members[3]
    #expect(copy.after == [from("build")])
    #expect(copy.x == edit.members[2].x! + TeamGraph.columnStep && copy.y == edit.members[2].y)
    #expect(!edit.members.contains { $0.after?.contains(from("test-2")) == true }, "no Hand-off out is copied")
}

@Test func removingLeavesAMemberWithNoHandOffInFlagged() {
    let edit = TeamGraph.remove("test", from: chain())
    #expect(ids(edit.members) == ["build", "check", "notes"])
    #expect(edit.members[2].after == [])
    #expect(TeamGraph.unreachable(edit.members) == ["notes"])
    #expect(TeamForm.problem(with: edit.members)?.contains("cannot reach it") == true)
    #expect(edit.selected == "build", "the Member it came after is picked")
    #expect(TeamGraph.remove("build", from: [member("build")]).selected == nil)
}

@Test func movingSnapsToTheGridAndNudgingStepsOneCell() {
    let moved = TeamGraph.move("build", to: .init(x: 13, y: 99), in: chain())
    #expect(moved[0].x == 16 && moved[0].y == 96)
    let nudged = TeamGraph.nudge("build", .left, in: moved)
    #expect(nudged[0].x == 8 && nudged[0].y == 96)
    #expect(TeamGraph.nudge("build", .down, in: nudged)[0].y == 104)
}

// MARK: Hand-offs

@Test func drawingALineReplacesTheOrchestratorsDefaultButNotANamedOne() {
    let members = [member("a"), member("b", "run"), member("c", "scan", after: [from("orchestrator")])]
    let drawn = TeamGraph.connect("a", to: "b", in: members)
    #expect(drawn.notice == nil && drawn.members[1].after == [from("a")])
    let kept = TeamGraph.connect("a", to: "c", in: members)
    #expect(kept.members[2].after == [from("orchestrator"), from("a")])
}

@Test func aLineThatCannotBeIsRefusedWithItsReason() {
    let members = chain()
    #expect(TeamGraph.connect("test", to: "build", in: members).notice
        == "test already comes after build, so this Hand-off would make a loop.")
    #expect(TeamGraph.connect("notes", to: "notes", in: members).notice == "notes cannot come after itself.")
    #expect(TeamGraph.connect("build", to: "test", in: members).notice == "test already comes after build.")
    #expect(TeamGraph.connect("test", to: "check", in: members).notice
        == "check is a verify Member and comes only after execute Members.")
    #expect(TeamGraph.connect("build", to: "orchestrator", in: members).notice == "Nothing comes before the Orchestrator.")
    #expect(TeamGraph.connect("orchestrator", to: "notes", in: members).notice == nil)
}

@Test func removingTheLastLineInFlagsTheMember() {
    let edit = TeamGraph.disconnect("test", to: "notes", in: chain())
    #expect(edit.members[3].after == [])
    #expect(TeamGraph.disconnect("orchestrator", to: "build", in: chain()).members[0].after == [])
}

@Test func aLineIsMadeAutomaticWithinItsRules() {
    let on = TeamGraph.setAutomatic(true, from: "test", to: "notes", in: chain())
    #expect(on.notice == nil && on.members[3].after == [from("test", auto: true)])
    #expect(TeamGraph.setAutomatic(false, from: "build", to: "test", in: chain()).members[2].after == [from("build")])
    #expect(TeamGraph.setAutomatic(true, from: "orchestrator", to: "build", in: chain()).notice?
        .hasPrefix("A Hand-off from the Orchestrator cannot be automatic") == true)
    #expect(TeamGraph.setAutomatic(true, from: "build", to: "check", in: chain()).notice?.contains("--verify") == true)
    let two = TeamGraph.connect("check", to: "test", in: chain()).members
    #expect(TeamGraph.setAutomatic(true, from: "check", to: "test", in: two).notice
        == "test already has an automatic Hand-off in, from build. A Member has at most one.")
}

@Test func theAddPickerOffersOnlyLinesThatCanBe() {
    #expect(TeamGraph.sources(for: "notes", in: chain()) == ["orchestrator", "build", "check"])
    #expect(TeamGraph.sources(for: "check", in: chain() + [member("other")]) == ["other"])
    #expect(TeamGraph.sources(for: "build", in: chain()).isEmpty)
}

// MARK: Keys

@Test func theArrowsPickTheNearestNodeThatWay() {
    let members = chain()
    #expect(TeamGraph.nearest(.down, from: nil, in: members) == "build")
    #expect(TeamGraph.nearest(.up, from: "build", in: members) == nil)
    #expect(TeamGraph.nearest(.right, from: "check", in: members) == "test")
    #expect(TeamGraph.nearest(.left, from: "check", in: members) == "check", "nothing that way keeps the pick")
    #expect(TeamGraph.nearest(.down, from: "test", in: members) == "notes")
}

@Test func theKeysMapToCanvasCommands() {
    #expect(CanvasKeys.command(for: .arrow(.up), modifiers: []) == .select(.up))
    #expect(CanvasKeys.command(for: .arrow(.left), modifiers: .option) == .nudge(.left))
    #expect(CanvasKeys.command(for: .enter, modifiers: []) == .rename)
    #expect(CanvasKeys.command(for: .delete, modifiers: []) == .remove)
    #expect(CanvasKeys.command(for: .character("a"), modifiers: []) == .add("execute"))
    #expect(CanvasKeys.command(for: .character("d"), modifiers: []) == .duplicate)
    #expect(CanvasKeys.command(for: .character("d"), modifiers: .command) == nil)
    #expect(!CanvasCommand.select(.up).edits && CanvasCommand.nudge(.up).edits)
}

@Test func aCommandOnTheOrchestratorIsRefused() {
    #expect(TeamGraph.apply(.remove, to: chain(), selected: nil).notice == "The Orchestrator stays where it is. Pick a Member first.")
    #expect(TeamGraph.apply(.nudge(.up), to: chain(), selected: "build").members[0].y == 128)
    #expect(TeamGraph.apply(.add("scan"), to: chain(), selected: nil).selected == "scan")
}

// MARK: Ids

@Test func idsAreUniqueAndNeverTheOrchestrators() {
    #expect(TeamGraph.uniqueID(from: "build", taking: ["build"]) == "build-2")
    #expect(TeamGraph.uniqueID(from: "build-2", taking: ["build-2"]) == "build-3")
    #expect(TeamGraph.uniqueID(from: "Orchestrator", taking: []) == "orchestrator-2")
    #expect(AddChoice.all().count == 13)
}
