import SwiftUI

// How the session header moves. Every tab change and every panel shows where it came
// from: the underline stretches to the new tab before it lets go of the old one, the page
// lifts in under it, and a panel grows out of the button that opened it, so the eye
// already knows where to click to put it away. Under Reduce Motion all of it is a fade.
enum HeaderMotion {
    // The underline's two legs: reaching over to the new tab, then letting go of the old
    // one. Together they run just under half a second, slow in, fast across, soft out.
    static let stretch = Animation.timingCurve(0.45, 0, 0.7, 0.6, duration: 0.21)
    static let release = Animation.timingCurve(0.2, 0.5, 0.2, 1, duration: 0.25)
    static let page = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    // A popover overshoots by a hair, so it reads as thrown from the button.
    static let grow = Animation.timingCurve(0.2, 0.9, 0.3, 1.12, duration: 0.34)
    static let shrink = Animation.timingCurve(0.4, 0, 0.6, 1, duration: 0.2)
    // Panels that come in from a window edge travel further, so they take longer.
    static let rise = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42)
    static let slide = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)
    static let sink = Animation.timingCurve(0.4, 0, 0.8, 0.6, duration: 0.24)
    static let flight = Animation.timingCurve(0.45, 0.05, 0.3, 1, duration: 0.82)

    static let pageLift: CGFloat = 8
    // The share of its size a popover starts from. Small enough to read as growing, and
    // never zero, since a singular scale is a NaN waiting to happen in AppKit layout.
    static let seed: CGFloat = 0.55
}

extension AnyTransition {
    // A new page lifts into place under the tab that chose it. The page it replaces goes
    // at once, so two heavy panes are never drawn over each other.
    static func headerPage(reduceMotion: Bool) -> AnyTransition {
        let insertion: AnyTransition = reduceMotion
            ? .opacity.animation(Motion.reveal)
            : .opacity.combined(with: .offset(y: HeaderMotion.pageLift)).animation(HeaderMotion.page)
        return .asymmetric(insertion: insertion, removal: .identity)
    }

    // A panel that grows out of the point it was opened from and shrinks back into it.
    // `origin` is in window coordinates; without one the panel only fades.
    static func grow(from origin: CGPoint?, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion, let origin else {
            return .opacity.animation(reduceMotion ? Motion.reveal : HeaderMotion.grow)
        }
        let modifier = AnyTransition.modifier(active: GrowFromPoint(progress: 0, origin: origin),
                                              identity: GrowFromPoint(progress: 1, origin: origin))
        return .asymmetric(insertion: modifier.animation(HeaderMotion.grow),
                           removal: modifier.animation(HeaderMotion.shrink))
    }

    // A drawer that comes in from one edge of the window and goes back out of it.
    static func drawer(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(Motion.reveal) }
        let arriving = edge == .bottom ? HeaderMotion.rise : HeaderMotion.slide
        return .asymmetric(insertion: .move(edge: edge).animation(arriving),
                           removal: .move(edge: edge).animation(HeaderMotion.sink))
    }
}

// The panel itself is never scaled. Panels hold buttons with tooltips, and those are
// AppKit views that cannot be laid out under a scale. A mask grows from the origin
// instead and uncovers the panel where it already stands.
nonisolated private struct GrowFromPoint: ViewModifier, Animatable {
    var progress: CGFloat
    let origin: CGPoint

    // Room for the panel's shadow, which the mask would otherwise cut off at rest.
    private static let bleed: CGFloat = 40

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            // The panel is solid well before it has finished growing, so it is never a
            // faint ghost of itself.
            .opacity(min(1, max(0, progress * 2)))
            .mask {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global).insetBy(dx: -Self.bleed, dy: -Self.bleed)
                    Rectangle()
                        .padding(-Self.bleed)
                        .scaleEffect(HeaderMotion.seed + (1 - HeaderMotion.seed) * progress,
                                     anchor: UnitPoint(x: (origin.x - frame.minX) / max(frame.width, 1),
                                                       y: (origin.y - frame.minY) / max(frame.height, 1)))
                }
            }
    }
}

extension View {
    // Keeps track of where a button's centre is in the window, for a panel or a flight
    // that has to start from it.
    func onCentreChange(_ action: @escaping (CGPoint) -> Void) -> some View {
        onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .global)
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { action($0) }
    }
}

// MARK: - Acting out

// A glyph plays its part once when what it stands for is chosen: the brush makes a
// stroke, the counts turn over, the rest give a small hop. It moves only the drawing of
// the symbol, never the button around it.
struct ActOut: ViewModifier {
    let icon: String
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if icon.hasPrefix("paintbrush") || icon.hasPrefix("magnifyingglass") {
            content.symbolEffect(.wiggle, options: .nonRepeating, value: trigger)
        } else if icon == "plusminus" {
            content.symbolEffect(.rotate, options: .nonRepeating, value: trigger)
        } else {
            content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
        }
    }
}

extension View {
    func actOut(_ icon: String, trigger: Int) -> some View {
        modifier(ActOut(icon: icon, trigger: trigger))
    }
}

// MARK: - Notes

// A short line that drops from a button whose action happens outside the window, such as
// opening Finder. Nothing in the window moves, so without it the click leaves no trace.
struct HeaderNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.terminalText)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Prompt flight

// A saved prompt sent from the rail, shown leaving its button and landing in the
// composer, so the message that turns up in the chat is seen arriving from the click.
struct PromptFlight: Identifiable, Equatable {
    var id = UUID()
    let name: String
    let icon: String
    // Both in window coordinates until the layer drawing the flight moves them into its own.
    let from: CGPoint
    let to: CGPoint

    func relative(to origin: CGPoint) -> PromptFlight {
        PromptFlight(id: id, name: name, icon: icon,
                     from: CGPoint(x: from.x - origin.x, y: from.y - origin.y),
                     to: CGPoint(x: to.x - origin.x, y: to.y - origin.y))
    }
}

struct PromptFlightChip: View {
    let flight: PromptFlight
    let landed: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Tweened(progress: progress) { progress in
            chip
                .scaleEffect(Self.scale(at: progress))
                .opacity(Self.opacity(at: progress))
                .position(point(at: progress))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(HeaderMotion.flight) {
                progress = 1
            } completion: {
                landed()
            }
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            Image(systemName: flight.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(flight.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(height: 28)
        .background(Theme.accentFill, in: Capsule())
        .shadow(color: Theme.accentFill.opacity(0.5), radius: 10, y: 6)
        .fixedSize()
    }

    // Drops out of the button first, then glides across into the composer, the way
    // something let go of falls before it travels.
    private func point(at progress: CGFloat) -> CGPoint {
        let control = CGPoint(x: flight.from.x, y: flight.from.y + (flight.to.y - flight.from.y) * 0.7)
        let t = min(1, max(0, progress))
        let u = 1 - t
        return CGPoint(x: u * u * flight.from.x + 2 * u * t * control.x + t * t * flight.to.x,
                       y: u * u * flight.from.y + 2 * u * t * control.y + t * t * flight.to.y)
    }

    static func scale(at progress: CGFloat) -> CGFloat {
        switch progress {
        case ..<0.18: 0.4 + 0.6 * progress / 0.18
        case ..<0.55: 1 + 0.05 * (progress - 0.18) / 0.37
        case ..<0.92: 1.05 - 0.2 * (progress - 0.55) / 0.37
        default: 0.85 - 0.25 * min(1, (progress - 0.92) / 0.08)
        }
    }

    static func opacity(at progress: CGFloat) -> CGFloat {
        switch progress {
        case ..<0.18: progress / 0.18
        case ..<0.92: 1
        default: min(1, max(0, (1 - progress) / 0.08))
        }
    }
}
