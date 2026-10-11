import SwiftUI
import Testing
@testable import MenuBarApp

@MainActor
struct HeaderMotionTests {
    // The chip is seen leaving the button and landing in the composer, so it has to start
    // and end out of sight and be solid for the whole of the trip between.
    @Test func aPromptFlightIsOnlySeenBetweenTheButtonAndTheComposer() {
        #expect(PromptFlightChip.opacity(at: 0) == 0)
        #expect(PromptFlightChip.opacity(at: 1) == 0)
        for progress in stride(from: 0.18, through: 0.9, by: 0.06) {
            #expect(PromptFlightChip.opacity(at: progress) == 1)
        }
    }

    // It grows out of the button, and shrinks as it goes into the composer, rather than
    // arriving at full size.
    @Test func aPromptFlightGrowsOutOfTheButtonAndShrinksIntoTheComposer() {
        let start = PromptFlightChip.scale(at: 0)
        let cruise = PromptFlightChip.scale(at: 0.55)
        let end = PromptFlightChip.scale(at: 1)
        #expect(start < 1 && end < 1)
        #expect(cruise > start && cruise > end)
        // A singular scale is how AppKit layout ends up with a NaN frame.
        for progress in stride(from: 0.0, through: 1.0, by: 0.01) {
            #expect(PromptFlightChip.scale(at: progress) > 0.3)
        }
    }

    @Test func aFlightMovesIntoTheLayerThatDrawsIt() {
        let flight = PromptFlight(name: "Debug", icon: "ant",
                                  from: CGPoint(x: 900, y: 80), to: CGPoint(x: 500, y: 700))
        let local = flight.relative(to: CGPoint(x: 200, y: 50))
        #expect(local.id == flight.id)
        #expect(local.from == CGPoint(x: 700, y: 30))
        #expect(local.to == CGPoint(x: 300, y: 650))
    }
}
