import CoreGraphics
import Testing
@testable import HubCore

private let window = CGSize(width: 1280, height: 800)

@Test func aPopoverHangsUnderItsControlOnItsLeadingEdge() {
    let place = PopoverPlacement.place(anchor: CGRect(x: 20, y: 60, width: 300, height: 32), width: 392, in: window, gap: 16)
    #expect(place == PopoverPlacement(x: 20, y: 108, height: 800 - 108 - 6 - 8, below: true))
}

@Test func aTrailingPopoverEndsUnderItsControlsTrailingEdge() {
    let place = PopoverPlacement.place(anchor: CGRect(x: 1000, y: 8, width: 28, height: 28), width: 480, in: window, trailing: true)
    #expect(place.x == 1028 - 480)
    #expect(place.below)
}

@Test func aPopoverStaysInsideTheWindowWithItsOffsetBlock() {
    let right = PopoverPlacement.place(anchor: CGRect(x: 1200, y: 100, width: 60, height: 30), width: 392, in: window)
    #expect(right.x == 1280 - 392 - 6 - 8)
    let left = PopoverPlacement.place(anchor: CGRect(x: 4, y: 8, width: 28, height: 28), width: 480, in: window, trailing: true)
    #expect(left.x == 8)
}

@Test func aPopoverNearTheBottomOpensOverItsControl() {
    let place = PopoverPlacement.place(anchor: CGRect(x: 300, y: 700, width: 120, height: 34), width: 320, in: window)
    #expect(!place.below)
    #expect(place.y == 8)
    #expect(place.height == 700 - 8 - 8)
}

@Test func aPopoverOpensUnderWhenThereIsRoomEnoughEvenIfMoreIsAbove() {
    let place = PopoverPlacement.place(anchor: CGRect(x: 300, y: 400, width: 120, height: 34), width: 320, in: window)
    #expect(place.below)
}
