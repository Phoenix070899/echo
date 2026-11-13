import Foundation
import Testing
@testable import HubCore

@Test func aToolResultFillsItsCallAndRunsOfCallsGroup() {
    var log = ChatLog()
    log.apply(["session": "s1", "end": 10, "items": [
        ["kind": "user", "id": "u1", "text": "fix it"],
        ["kind": "tool", "id": "t1", "tool": "Bash", "summary": "cargo test"],
        ["kind": "tool", "id": "t2", "tool": "Read", "summary": "src/a.rs"],
    ]])
    #expect(log.request["after"] as? Int == 10)
    let changed = log.apply(["session": "s1", "end": 20, "items": [
        ["kind": "result", "id": "t1", "text": "ok", "error": false],
        ["kind": "result", "id": "gone", "text": "from before the window"],
        ["kind": "reply", "id": "a1", "text": "Fixed."],
    ]])
    #expect(changed)
    #expect(log.items.map(\.id) == ["u1", "t1", "t2", "a1"])
    #expect(log.items[1].output == "ok")
    #expect(log.rows.count == 3)
    if case .tools(let run) = log.rows[1] { #expect(run.count == 2) } else { Issue.record("tools not grouped") }
    let again = log.apply(["session": "s1", "end": 20, "items": []])
    #expect(!again)
}

@Test func aNewSessionStartsTheChatOver() {
    var log = ChatLog()
    log.apply(["session": "s1", "end": 10, "items": [["kind": "user", "id": "u1", "text": "hi"]]])
    log.apply(["session": "s2", "end": 5, "items": [["kind": "user", "id": "u2", "text": "again"]]])
    #expect(log.items.map(\.id) == ["u2"])
    #expect(log.request["session"] as? String == "s2")
}

@Test func aReplyNeedsTheHumanOnlyWhenItsNeedsYouListsSomething() {
    let reply = { (text: String) in ChatItem(id: "a", kind: .reply, text: text) }
    #expect(reply("Done.\n\nNeeds you\n- Approve the merge of feat/x\n\nNext: wait.").needsHuman)
    #expect(!reply("Needs you\n- Nothing.\nDone\n- ok").needsHuman)
    #expect(!reply("The test passed.").needsHuman)
}

@Test func theWorkingRowShowsTheStepElseTheSpinnerOnlyWhileWorking() {
    var log = ChatLog()
    log.apply(["session": "s1", "end": 0, "items": [], "state": ["live": true, "look": "working",
                                                                 "spinner": "Nesting… (3s · ↓ 89 tokens)"]])
    #expect(log.state.working == "Nesting…")
    let stepped = log.apply(["session": "s1", "end": 0, "items": [],
                             "state": ["live": true, "look": "working", "spinner": "Nesting… (4s)", "step": "Bash(cargo test)"]])
    #expect(stepped)
    #expect(log.state.working == "Bash(cargo test)")
    log.apply(["session": "s1", "end": 0, "items": [], "state": ["live": true, "look": "idle"]])
    #expect(log.state.working == nil)
}

@Test func anOlderPageGoesFirstAndFillsCallsWhoseResultsCameEarlier() {
    var log = ChatLog()
    log.apply(["session": "s2", "end": 50, "start": 30, "more": true, "items": [
        ["kind": "result", "id": "t1", "text": "ok"],
        ["kind": "reply", "id": "a2", "text": "Done."],
    ]])
    #expect(log.olderRequest?["before"] as? Int == 30)
    #expect(log.olderRequest?["page_session"] as? String == "s2")
    log.applyOlder(["start": 0, "page_session": "s1", "more": false, "items": [
        ["kind": "user", "id": "u1", "text": "build"],
        ["kind": "tool", "id": "t1", "tool": "Bash", "summary": "make"],
        ["kind": "divider", "id": "renewed s2", "text": "Session renewed, context cleared"],
    ]])
    #expect(log.items.map(\.id) == ["u1", "t1", "renewed s2", "a2"])
    #expect(log.items[1].output == "ok")
    #expect(log.olderRequest == nil)
}

@Test func aSlashCompletesCommandNamesUntilASpace() {
    let commands = [SlashCommand(name: "model", description: "", menu: true),
                    SlashCommand(name: "compact", description: "", menu: false),
                    SlashCommand(name: "mattpocock-skills:tdd", description: "", menu: false)]
    #expect(SlashCommand.matches("/", in: commands).count == 3)
    #expect(SlashCommand.matches("/co", in: commands).map(\.name) == ["compact", "mattpocock-skills:tdd"])
    #expect(SlashCommand.matches("/td", in: commands).map(\.name) == ["mattpocock-skills:tdd"])
    #expect(SlashCommand.matches("/model opus", in: commands).isEmpty)
    #expect(SlashCommand.matches("hello", in: commands).isEmpty)
}

@Test func columnsGiveWayBeforeThePanelBetweenThemIsPushedOut() {
    // A wide window keeps every width the human dragged to.
    #expect(ColumnLayout.fit(total: 2056, fixed: 48, ledger: 392, files: 280) == .init(ledger: 392, files: 280))
    // At the 900 pt minimum Files gives way first, then the ledger, to their floors.
    #expect(ColumnLayout.fit(total: 900, fixed: 48, ledger: 392, files: 280) == .init(ledger: 300, files: 220))
    // A little short: only Files shrinks.
    #expect(ColumnLayout.fit(total: 1100, fixed: 48, ledger: 392, files: 400) == .init(ledger: 392, files: 300))
    // No Files column: the ledger alone gives way.
    #expect(ColumnLayout.fit(total: 900, fixed: 36, ledger: 640, files: nil) == .init(ledger: 504, files: nil))
}

@Test func aKiroItemCarriesItsLevelAndDeniedFlagAndOthersCarryNone() {
    var log = ChatLog()
    log.apply(["session": "k1", "end": 9, "supported": true, "items": [
        ["kind": "event", "id": "e1", "text": "Interrupted", "level": "interrupt"],
        ["kind": "event", "id": "e2", "text": "Error: the turn failed.", "level": "error", "extra": 1],
        ["kind": "event", "id": "e3", "text": "w12 sent its Final Report"],
        ["kind": "tool", "id": "t1", "tool": "Bash", "summary": "rm x", "denied": true],
        ["kind": "result", "id": "t1", "text": "Denied", "error": true],
        ["kind": "tool", "id": "t2", "tool": "Read", "summary": "a.rs"],
    ]])
    #expect(log.supported)
    #expect(log.items.map(\.level) == ["interrupt", "error", nil, nil, nil])
    #expect(log.items[3].denied && log.items[3].failed && log.items[3].output == "Denied")
    #expect(!log.items[4].denied)
}
