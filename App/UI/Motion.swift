import SwiftUI

// Beweging in de app: alleen op een concrete waarde, kort en zacht, en nooit als Verlaag beweging aan staat.
// Een animatie hoort bij de waarde die verandert, niet bij een hele pagina (par. 4.6 van docs/design/plan.md).

/// Animeert veranderingen van `value`, tenzij de gebruiker Verlaag beweging heeft aangezet: dan verandert alles meteen.
struct AnimatedByValue<Value: Equatable>: ViewModifier {
    let value: Value
    let quick: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : (quick ? Theme.quickMotion : Theme.motion), value: value)
    }
}

extension View {
    /// Animeert alleen veranderingen van `value`, met `Theme.motion` (of `Theme.quickMotion` bij `quick`), en niet bij
    /// Verlaag beweging. Vervangt `.animation(Theme.motion, value:)`.
    func animated<V: Equatable>(by value: V, quick: Bool = false) -> some View {
        modifier(AnimatedByValue(value: value, quick: quick))
    }
}
