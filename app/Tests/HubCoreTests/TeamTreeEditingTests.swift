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

// MARK: Keys

@Test func plainKeysSelectRenameRemoveAddAndDuplicate() {
    #expect(TreeKeys.command(for: .up, modifiers: []) == .select(-1))
    #expect(TreeKeys.command(for: .down, modifiers: []) == .select(1))
    #expect(TreeKeys.command(for: .enter, modifiers: []) == .rename)
    #expect(TreeKeys.command(for: .delete, modifiers: []) == .remove)
    #expect(TreeKeys.command(for: .character("a"), modifiers: []) == .add("execute"))
    #expect(TreeKeys.command(for: .character("d"), modifiers: []) == .duplicate)
    #expect(TreeKeys.command(for: .left, modifiers: []) == .leave)
}

@Test func optionArrowsMoveIndentAndOutdent() {
    #expect(TreeKeys.command(for: .up, modifiers: .option) == .move(-1))
    #expect(TreeKeys.command(for: .down, modifiers: .option) == .move(1))
    #expect(TreeKeys.command(for: .right, modifiers: .option) == .indent)
    #expect(TreeKeys.command(for: .left, modifiers: .option) == .outdent)
}

@Test func commandKeysAreNeverTheTrees() {
    // ⌘N and ⌘D are Echo's New Orchestrator and split (ui-ux/0008).
    #expect(TreeKeys.command(for: .character("n"), modifiers: .command) == nil)
    #expect(TreeKeys.command(for: .character("d"), modifiers: .command) == nil)
    #expect(TreeKeys.command(for: .character("d"), modifiers: [.command, .shift]) == nil)
    #expect(TreeKeys.command(for: .up, modifiers: .command) == nil)
    #expect(TreeKeys.command(for: .down, modifiers: [.option, .command]) == nil)
}

@Test func otherModifiersAndKeysAreLeftAlone() {
    #expect(TreeKeys.command(for: .character("a"), modifiers: .shift) == nil)
    #expect(TreeKeys.command(for: .character("a"), modifiers: .control) == nil)
    #expect(TreeKeys.command(for: .character("a"), modifiers: .option) == nil)
    #expect(TreeKeys.command(for: .character("x"), modifiers: []) == nil)
    #expect(TreeKeys.command(for: .right, modifiers: []) == nil)
    #expect(TreeKeys.command(for: .up, modifiers: .shift) == nil)
}

@Test func onlySelectionAndFocusWorkInATeamThatCannotBeEdited() {
    #expect(!TreeCommand.select(1).edits)
    #expect(!TreeCommand.leave.edits)
    for command in [TreeCommand.move(1), .indent, .outdent, .rename, .remove, .add("scan"), .duplicate] {
        #expect(command.edits)
    }
}

// MARK: The settings page's keys

@Test func theSettingsPageLeavesUpAndDownToAFocusedTree() {
    #expect(!SettingsKeys.pageTakesUpDown(treeFocused: true, asking: false, hasModifiers: false))
    #expect(SettingsKeys.pageTakesUpDown(treeFocused: false, asking: false, hasModifiers: false))
    #expect(!SettingsKeys.pageTakesUpDown(treeFocused: false, asking: true, hasModifiers: false))
    #expect(!SettingsKeys.pageTakesUpDown(treeFocused: false, asking: false, hasModifiers: true))
}

@Test func theSettingsPageHandsTheKeyboardToTheTreeOnlyWhenItShowsAndHasNotGotIt() {
    #expect(SettingsKeys.pageEntersTree(treeShown: true, treeFocused: false, asking: false, hasModifiers: false))
    #expect(!SettingsKeys.pageEntersTree(treeShown: false, treeFocused: false, asking: false, hasModifiers: false))
    #expect(!SettingsKeys.pageEntersTree(treeShown: true, treeFocused: true, asking: false, hasModifiers: false))
    #expect(!SettingsKeys.pageEntersTree(treeShown: true, treeFocused: false, asking: true, hasModifiers: false))
    #expect(!SettingsKeys.pageEntersTree(treeShown: true, treeFocused: false, asking: false, hasModifiers: true))
}

// MARK: Selecting

@Test func downFromTheOrchestratorSelectsTheFirstMemberAndUpComesBack() {
    #expect(TeamTreeEditing.select(1, from: nil, in: sample) == "scan")
    #expect(TeamTreeEditing.select(-1, from: "scan", in: sample) == nil)
}

@Test func selectionFollowsTheRowsInTreeOrderAndStopsAtBothEnds() {
    #expect(TeamTreeEditing.select(1, from: "build", in: sample) == "check")
    #expect(TeamTreeEditing.select(1, from: "notes", in: sample) == "run")
    #expect(TeamTreeEditing.select(1, from: "run", in: sample) == "run")
    #expect(TeamTreeEditing.select(-1, from: nil, in: sample) == nil)
    #expect(TeamTreeEditing.select(1, from: nil, in: []) == nil)
}

@Test func selectingChangesNothingInTheTree() {
    let edit = TeamTreeEditing.apply(.select(1), to: sample, selected: "scan")
    #expect(edit.members == sample)
    #expect(edit.selected == "build")
    #expect(edit.notice == nil)
}

// MARK: Adding

@Test func addUnderAMemberMakesItsLastChildAndSelectsIt() {
    let edit = TeamTreeEditing.apply(.add("scan"), to: sample, selected: "build")
    #expect(shape(edit.members) == ["scan", "build", "build/check", "build/notes", "build/scan-2", "run"])
    #expect(edit.selected == "scan-2")
    #expect(edit.notice == nil)
}

@Test func addUnderTheOrchestratorMakesALevelOneMember() {
    let edit = TeamTreeEditing.apply(.add("research"), to: sample, selected: nil)
    #expect(shape(edit.members).last == "research")
    #expect(edit.selected == "research")
}

@Test func theAKeyAddsAnExecuteMember() {
    let command = TreeKeys.command(for: .character("a"), modifiers: [])
    let edit = TeamTreeEditing.apply(command ?? .leave, to: [], selected: nil)
    #expect(edit.members.map(\.action) == ["execute"])
    #expect(edit.members.first?.profile == "naruto")
}

@Test func addIsRefusedWithAReasonAtTheDeepestLevel() {
    let deep = [member("a", "execute"), member("b", "execute", under: "a"), member("c", "execute", under: "b")]
    let edit = TeamTreeEditing.apply(.add("scan"), to: deep, selected: "c")
    #expect(edit.members == deep)
    #expect(edit.notice?.contains("level 3") == true)
}

@Test func aVerifyMemberIsOnlyAddedUnderAnExecuteMember() {
    let under = TeamTreeEditing.apply(.add("verify"), to: sample, selected: "build")
    #expect(under.notice == nil)
    #expect(under.selected == "verify")
    let elsewhere = TeamTreeEditing.apply(.add("verify"), to: sample, selected: "scan")
    #expect(elsewhere.notice == "A verify Member needs an execute Member above it.")
    #expect(elsewhere.members == sample)
    let root = TeamTreeEditing.apply(.add("verify"), to: sample, selected: nil)
    #expect(root.notice != nil)
}

@Test func aTeamAtTheLimitTakesNoMoreMembers() {
    let full = (0..<TeamForm.maxMembers).map { member("m\($0)") }
    let edit = TeamTreeEditing.apply(.add("scan"), to: full, selected: nil)
    #expect(edit.members == full)
    #expect(edit.notice == "A Team holds at most 24 Members.")
}

@Test func aCustomMemberIsNotAddedByKeyBecauseItNeedsAProfile() {
    let edit = TeamTreeEditing.apply(.add(Action.custom), to: sample, selected: nil)
    #expect(edit.members == sample)
    #expect(edit.notice?.contains("Profile") == true)
}

// MARK: Duplicating

@Test func duplicateCopiesTheSubtreeAndSelectsTheCopy() {
    let edit = TeamTreeEditing.apply(.duplicate, to: sample, selected: "build")
    #expect(shape(edit.members) == ["scan", "build", "build/check", "build/notes", "build-2", "build-2/check-2", "build-2/notes-2", "run"])
    #expect(edit.selected == "build-2")
}

@Test func duplicateIsRefusedWhenTheCopiesWouldPassTheLimit() {
    let full = (0..<(TeamForm.maxMembers - 1)).map { member("m\($0)") } + [member("last")]
    #expect(TeamTreeEditing.apply(.duplicate, to: full, selected: "last").notice != nil)
    let nearly = Array(full.dropLast())
    #expect(TeamTreeEditing.apply(.duplicate, to: nearly, selected: "m0").notice == nil)
}

@Test func theOrchestratorCannotBeCopiedOrRemovedOrMoved() {
    for command in [TreeCommand.duplicate, .remove, .move(1), .indent, .outdent] {
        let edit = TeamTreeEditing.apply(command, to: sample, selected: nil)
        #expect(edit.members == sample)
        #expect(edit.selected == nil)
        #expect(edit.notice != nil)
    }
}

// MARK: Removing

@Test func removingAMemberWithoutChildrenAsksNothingAndSelectsTheNextSibling() {
    let edit = TeamTreeEditing.apply(.remove, to: sample, selected: "scan")
    #expect(shape(edit.members) == ["build", "build/check", "build/notes", "run"])
    #expect(edit.selected == "build")
    #expect(edit.asksToRemove == nil)
}

@Test func removingTheLastSiblingSelectsThePreviousOne() {
    let edit = TeamTreeEditing.apply(.remove, to: sample, selected: "run")
    #expect(edit.selected == "build")
}

@Test func removingTheOnlyChildSelectsItsParentAndTheOnlyMemberTheOrchestrator() {
    let one = [member("build", "execute"), member("check", "verify", under: "build")]
    #expect(TeamTreeEditing.apply(.remove, to: one, selected: "check").selected == "build")
    #expect(TeamTreeEditing.apply(.remove, to: [member("a")], selected: "a").selected == nil)
}

@Test func removingAMemberWithChildrenAsksFirstAndChangesNothing() {
    let edit = TeamTreeEditing.apply(.remove, to: sample, selected: "build")
    #expect(edit.asksToRemove == 3)
    #expect(edit.members == sample)
    #expect(edit.selected == "build")
}

@Test func aConfirmedRemovalTakesTheWholeSubtree() {
    let edit = TeamTreeEditing.apply(.remove, to: sample, selected: "build", confirmed: true)
    #expect(shape(edit.members) == ["scan", "run"])
    #expect(edit.selected == "run")
    #expect(edit.asksToRemove == nil)
}

// MARK: Moving

@Test func optionDownMovesAMemberPastItsNextSiblingAndKeepsItSelected() {
    let edit = TeamTreeEditing.apply(.move(1), to: sample, selected: "scan")
    #expect(shape(edit.members) == ["build", "build/check", "build/notes", "scan", "run"])
    #expect(edit.selected == "scan")
}

@Test func movingPastTheEndOfTheSiblingsIsRefusedWithAReason() {
    let first = TeamTreeEditing.apply(.move(-1), to: sample, selected: "scan")
    #expect(first.notice == "scan is already first among its siblings.")
    #expect(first.members == sample)
    let last = TeamTreeEditing.apply(.move(1), to: sample, selected: "run")
    #expect(last.notice == "run is already last among its siblings.")
}

@Test func indentPutsAMemberUnderTheSiblingAbove() {
    let edit = TeamTreeEditing.apply(.indent, to: sample, selected: "run")
    #expect(shape(edit.members) == ["scan", "build", "build/check", "build/notes", "build/run"])
    #expect(edit.selected == "run")
}

@Test func indentWithNoSiblingAboveIsRefused() {
    let edit = TeamTreeEditing.apply(.indent, to: sample, selected: "scan")
    #expect(edit.members == sample)
    #expect(edit.notice?.contains("scan") == true)
}

@Test func indentIsRefusedWithTheTreesOwnReasonWhenItWouldGoTooDeep() {
    let deep = [member("a"), member("b"), member("c", under: "b"), member("d", under: "c")]
    let edit = TeamTreeEditing.apply(.indent, to: deep, selected: "b")
    #expect(edit.members == deep)
    #expect(edit.notice?.contains("at most 3") == true)
}

@Test func outdentPutsAMemberRightAfterItsParent() {
    let edit = TeamTreeEditing.apply(.outdent, to: sample, selected: "notes")
    #expect(shape(edit.members) == ["scan", "build", "build/check", "notes", "run"])
    #expect(edit.selected == "notes")
}

@Test func outdentAtLevelOneIsRefused() {
    let edit = TeamTreeEditing.apply(.outdent, to: sample, selected: "build")
    #expect(edit.notice == "build is already at level 1.")
    #expect(edit.members == sample)
}

@Test func outdentOfAVerifyMemberIsRefusedBecauseItNeedsItsExecuteParent() {
    let edit = TeamTreeEditing.apply(.outdent, to: sample, selected: "check")
    #expect(edit.members == sample)
    #expect(edit.notice?.contains("verify") == true)
}

@Test func renameAndLeaveAreTheViewsToCarryOut() {
    for command in [TreeCommand.rename, .leave] {
        let edit = TeamTreeEditing.apply(command, to: sample, selected: "build")
        #expect(edit == TreeEdit(members: sample, selected: "build"))
    }
}

@Test func everyOperationLeavesATreeThatPassesTheTeamsRules() {
    let commands: [TreeCommand] = [.add("scan"), .duplicate, .remove, .move(1), .move(-1), .indent, .outdent]
    for command in commands {
        for id in sample.map(\.id) {
            let edit = TeamTreeEditing.apply(command, to: sample, selected: id, confirmed: true)
            #expect(TeamTree.isValid(edit.members))
        }
    }
}

// MARK: Looks

@Test func everyActionHasItsOwnSymbolAndCustomHasOne() {
    let symbols = (Action.shippedIDs + [Action.custom]).map(ActionLook.symbol(for:))
    #expect(Set(symbols).count == symbols.count)
    #expect(symbols.allSatisfy { !$0.isEmpty })
}

@Test func aRowIsTitledByItsActionAndCustomIsCustom() {
    #expect(ActionLook.title(for: "execute") == "Write code")
    #expect(ActionLook.title(for: "custom") == "Custom")
}

@Test func theGreyLineNamesTheProfileAndTheModelWhenThereIsOne() {
    #expect(ActionLook.meta(profile: "naruto", model: "opus") == "naruto, opus")
    #expect(ActionLook.meta(profile: "naruto", model: "") == "naruto")
}

@Test func aCustomMemberWithAProfileIsRefusedOnlyWhereTheTreeHasNoRoom() {
    #expect(TeamTreeEditing.addRefusal(Action.custom, under: nil, in: sample, hasProfile: true) == nil)
    let deep = [member("a", "execute"), member("b", "execute", under: "a"), member("c", "execute", under: "b")]
    #expect(TeamTreeEditing.addRefusal(Action.custom, under: deep[2], in: deep, hasProfile: true) != nil)
}
