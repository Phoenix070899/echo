# The Teams section's columns pushed the Settings list off a 1280 pt window

Found: 2026-11-14
Where: app/Sources/HubApp/TeamTreeView.swift, TeamsSection.swift, SettingsPage.swift
Fixed in: the change that adds this file

In the redesigned Teams section at a 1280 pt window, "SETTINGS" and the section names were cut at the left, the inspector at the right, and the tree's names shrank to "M" and "(".
Cause: the tree's rows had fixed columns (a 106 pt indent, 150 pt Profile, 74 pt effort) whose sum, with the list beside a ledger-wide section list and the 300 pt inspector, was wider than the window, and SwiftUI let the row's minimum width push its neighbours out.
Fix: the tree takes exactly the width it is offered (a GeometryReader) and narrows its margins, steps and columns under 600 pt; the Team head's counts keep their size and a long name scales down; the section list is 260 pt at most.
Lesson: a column of fixed-width parts must lay out in the width it is offered, not set a minimum; shoot every wide section at the harness's 1280 pt window before calling it done.
