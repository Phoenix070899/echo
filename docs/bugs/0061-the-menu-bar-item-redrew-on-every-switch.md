# The menu bar item redrew on every display at each switch, so switching was slow

Found: 2026-11-02
Where: app/Sources/HubApp/HubApp.swift (the Scene), app/Sources/HubApp/MenuBarView.swift (MenuBarItem)
Fixed in: the change that adds this file

Switching between Orchestrators in different checkouts took about 45 ms of main-thread time each, while a comparison with Orca's switching was under way.
Cause: the menu bar item was a SwiftUI `MenuBarExtra`; every change to `AppModel` updates the app's Scene graph, which set the item's image again, and macOS then redrew its copy in the menu bar of every display and Space (8 copies on this Mac).
That was over half of each switch, measured with `sample` on a test copy: 30 switches took 1,250 to 1,600 busy main-thread samples before, and 610 to 850 after.
Taking the Scene's observation of the model away, or giving the label only the Needs You count, did not help: any update of the app's graph reconfigured the item.
Fix: the item is an `NSStatusItem` made by the app delegate, outside the Scene; its title changes only when the Needs You count does, and a click shows `MenuBarView` in a panel below it (ui-ux/0057).
Lesson: keep anything AppKit draws for the whole system, like the menu bar item, out of SwiftUI's Scene; when a switch is slow, look for `NSStatusItem` and `MenuBarExtraController` in a `sample` of the main thread.
