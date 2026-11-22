import SwiftUI

/// One motion vocabulary for the whole app, chosen by what the motion does:
///
/// - Nothing animates on keyboard actions or anything seen hundreds of times;
///   those change instantly.
/// - Feedback (press, hover in, value readouts) is under 150 ms, no bounce.
/// - Opens, swaps and selection moves are 250 ms with a strong ease-out.
/// - Closes are quicker than opens and never bounce.
/// - Only something a finger let go of carries a little bounce.
/// - Reduce Motion keeps fades and drops movement, scale and blur.
enum Motion {
    /// Press feedback, hover in, readout changes.
    static let quick = Animation.smooth(duration: 0.15)
    /// Opens, swaps, selection moves.
    static let fast = Animation.smooth(duration: 0.25)
    /// Whole-surface changes, such as connect to connected.
    static let medium = Animation.smooth(duration: 0.35)
    /// A released drag settling, with the momentum it had.
    static let settle = Animation.spring(duration: 0.35, bounce: 0.15)
    /// Lifting something under the pointer: a little life.
    static let lift = Animation.spring(duration: 0.3, bounce: 0.25)
    /// Hover out: softer than hover in.
    static let hoverOut = Animation.smooth(duration: 0.22)
    /// Per-item offset in a cascade; keep the total under ~300 ms.
    static let stagger: Double = 0.035
}

// MARK: - Settle-in transition

/// Enter: fade in from 6 pt below with a 2 pt blur. Exit: a quicker plain
/// fade, so a dismissal never lingers or travels.
struct SettleEffect: ViewModifier {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: reduceMotion ? 0 : (1 - progress) * 6)
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 2)
    }
}

extension AnyTransition {
    static var settle: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SettleEffect(progress: 0), identity: SettleEffect(progress: 1)),
            removal: .opacity.animation(Motion.quick)
        )
    }
}

// MARK: - Cascade on first appearance

/// Fades a view in from just below on first appearance, `index` steps after
/// the first item, so a page assembles rather than pops. Coming back to a
/// page that is already shown does not replay it.
private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .blur(radius: shown || reduceMotion ? 0 : 2)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.fast.delay(Double(min(index, 8)) * Motion.stagger)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Cascade entrance; see `Entrance`.
    func entrance(_ index: Int) -> some View {
        modifier(Entrance(index: index))
    }
}

// MARK: - Page arrival

/// macOS swaps NavigationStack pages in one frame. Each page instead
/// arrives: it fades in while drifting 14 pt from the side it comes from
/// (pushed pages from the trailing edge, the main page from the leading
/// edge on the way back), out of a 3 pt blur. Slow enough to read as
/// calm, short enough not to wait on: 0.38 s, smooth, no bounce. With
/// Reduce Motion it only fades.
private struct PageArrival: ViewModifier {
    let edge: HorizontalEdge
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let distance: CGFloat = edge == .leading ? -14 : 14
        content
            .opacity(0.001 + 0.999 * progress)
            .offset(x: reduceMotion ? 0 : (1 - progress) * distance)
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 3)
            .onAppear {
                guard progress < 1 else { return }
                withAnimation(.smooth(duration: 0.38)) { progress = 1 }
            }
            .onDisappear {
                // Ready to arrive again when navigated back to.
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { progress = 0 }
            }
    }
}

extension View {
    func pageArrival(from edge: HorizontalEdge) -> some View {
        modifier(PageArrival(edge: edge))
    }

    /// The main page coming back: the same arrival, from the leading edge,
    /// each time `returns` counts up.
    func pageReturn(_ returns: Int) -> some View {
        modifier(PageReturn(returns: returns))
    }
}

private struct PageReturn: ViewModifier {
    let returns: Int
    @State private var progress: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(0.001 + 0.999 * progress)
            .offset(x: reduceMotion ? 0 : (1 - progress) * -14)
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 3)
            .onChange(of: returns) {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { progress = 0 }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.smooth(duration: 0.38)) { progress = 1 }
                }
            }
    }
}
