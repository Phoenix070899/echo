import SwiftUI

/// One on/off bit of view state, for views that would otherwise need `@State`.
public final class Flag: ObservableObject {
    @Published public var on = false

    public init() {}

}
