import Foundation

// The one-off entrance the day ribbon plays the first time Home opens on a full day.
// The total rolls up over the dimmed chart and flies into the headline. Under it the
// bars rise from the centre in their project colours, hold a beat, then drain from the
// top into the accent green, which is how the chart looks at rest.
//
// Every value is a pure function of the time since the start, so one clock can drive
// the whole thing and a skip is only a jump to the end.
struct RibbonEntrance {
    // The bar a day has to clear to earn the entrance. A thinner day is drawn the way it
    // always is, with a plain fade.
    static let minimumSlots = 8
    static let minimumSpent: TimeInterval = 3_600
    static let slots = 64

    // The headline's own size and the size the total rolls at, so the flight can shrink
    // one into the other.
    static let headlineSize: CGFloat = 11.5
    static let rollSize: CGFloat = 46

    // The total as it reads in the headline, and its digits in order.
    let total: String
    let digits: [Int]

    private static let roll: TimeInterval = 0.75
    private static let digitStagger: TimeInterval = 0.07
    private static let flightDelay: TimeInterval = 0.14
    private static let flight: TimeInterval = 0.52
    private static let rise: TimeInterval = 0.52
    private static let riseStagger: TimeInterval = 0.008
    private static let hold: TimeInterval = 0.25
    private static let drain: TimeInterval = 0.3
    private static let drainStagger: TimeInterval = 0.007

    init(total: String) {
        self.total = total
        digits = total.compactMap(\.wholeNumberValue)
    }

    static func isDeserved(by ribbon: DayRibbon) -> Bool {
        guard ribbon.spent >= minimumSpent else { return false }
        let filled = ribbon.activity(bucketCount: slots).filter { $0.spent > 0 }.count
        return filled >= minimumSlots
    }

    // Only the first Home visit of a calendar day gets to choose, so reopening Home later
    // that day finds the chart at rest. Answers true once a day, and marks the day taken.
    static func claimToday(now: Date = Date(),
                           calendar: Calendar = .current,
                           in store: UserDefaults = .standard) -> Bool {
        if let last = Preferences.dayRibbonEntranceDay(in: store),
           calendar.isDate(last, inSameDayAs: now) {
            return false
        }
        Preferences.setDayRibbonEntranceDay(now, in: store)
        return true
    }

    // MARK: - Timing

    var flightStart: TimeInterval {
        Self.roll + Double(max(0, digits.count - 1)) * Self.digitStagger + Self.flightDelay
    }

    private var riseStart: TimeInterval { flightStart }

    private var drainStart: TimeInterval {
        riseStart + Double(Self.slots / 2) * Self.riseStagger + Self.rise + Self.hold
    }

    var duration: TimeInterval {
        drainStart + Double(Self.slots) * Self.drainStagger + Self.drain
    }

    // How far a digit's strip has turned, in digits. Each column spins one turn more than
    // the one after it, and they land left to right.
    func turn(ofDigit column: Int, at time: TimeInterval) -> Double {
        let spins = Double(digits.count - column)
        let end = Self.roll + Double(column) * Self.digitStagger
        return (spins * 10 + Double(digits[column])) * Self.easeOutQuart(time / end)
    }

    // How far the total has travelled from over the chart into the headline.
    func flight(at time: TimeInterval) -> Double {
        Self.easeInOutCubic((time - flightStart) / Self.flight)
    }

    // The large total fades in as it starts to roll, and hands over to the headline's own
    // text just before it lands.
    func rollOpacity(at time: TimeInterval) -> Double {
        min(Self.clamp(time / 0.16), 1 - Self.clamp((flight(at: time) - 0.7) / 0.3))
    }

    func numberOpacity(at time: TimeInterval) -> Double {
        Self.clamp((flight(at: time) - 0.65) / 0.35)
    }

    func restOpacity(at time: TimeInterval) -> Double {
        Self.clamp((time - flightStart - Self.flight + 0.12) / 0.26)
    }

    // The chart sits at 45% while the total rolls over it, and comes back as it flies.
    func chartOpacity(at time: TimeInterval) -> Double {
        1 - 0.55 * (1 - Self.clamp((time - flightStart) / 0.3)) * Self.clamp(time / 0.2)
    }

    // How far a bar has risen. The spring overshoots a little past one before it settles.
    func rise(ofBar index: Int, of count: Int, at time: TimeInterval) -> Double {
        let fromCentre = abs(Double(index) - Double(count - 1) / 2)
        // Spread over the full set of slots, so a narrow chart takes the same time.
        let scale = Double(Self.slots) / Double(max(count, 1))
        return Self.spring((time - riseStart - fromCentre * scale * Self.riseStagger) / Self.rise)
    }

    // How much of a bar's project colour has drained away from the top.
    func drain(ofBar index: Int, of count: Int, at time: TimeInterval) -> Double {
        let scale = Double(Self.slots) / Double(max(count, 1))
        return Self.easeInOutCubic(
            (time - drainStart - Double(index) * scale * Self.drainStagger) / Self.drain)
    }

    // MARK: - Curves

    private static func clamp(_ value: Double) -> Double { max(0, min(1, value)) }

    private static func spring(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return 1 - exp(-6.5 * x) * cos(10.5 * x)
    }

    private static func easeOutQuart(_ x: Double) -> Double {
        1 - pow(1 - clamp(x), 4)
    }

    private static func easeInOutCubic(_ x: Double) -> Double {
        let x = clamp(x)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}
