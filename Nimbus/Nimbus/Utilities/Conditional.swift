import SwiftUI

/// Applies `modifier` only while `enabled`. Used to detach a view's toolbar
/// contribution without unmounting the view itself.
struct Conditional<M: ViewModifier>: ViewModifier {
    let enabled: Bool
    let modifier: M

    func body(content: Content) -> some View {
        if enabled {
            content.modifier(modifier)
        } else {
            content
        }
    }
}
