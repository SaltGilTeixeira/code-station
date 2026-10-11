import AppKit
import SwiftUI
import Testing
@testable import MenuBarApp

@MainActor
struct TurnHandoffTests {
    private let ended = Date(timeIntervalSinceReferenceDate: 321)

    @Test func warningsKeepActualFailuresInTheLatestTurnEvenAfterAnIsolatedRerun() throws {
        let failure = ToolUse(id: "full", name: "Bash", input: "swift test",
                              result: "1 test failed", exitCode: 1)
        let denied = ToolUse(id: "denied", name: "Bash", input: "npm test",
                             result: "Permission denied", isError: true)
        let handoff = try #require(TurnHandoff(messages: [
            ChatMessage(role: .user, text: "earlier"),
            ChatMessage(role: .assistant, tools: [failure]),
            ChatMessage(role: .user, text: "current"),
            ChatMessage(role: .assistant, tools: [
                failure, denied,
                ToolUse(id: "rerun", name: "Bash", input: "swift test --filter LayoutTests",
                        result: "Passed", exitCode: 0),
                ToolUse(id: "pending", name: "Bash", input: "swift test", isError: true),
                ToolUse(id: "read", name: "Read", input: "missing.swift", result: "Missing", isError: true)
            ])
        ], projectPath: "/repo"))
        #expect(handoff.failedCommands.map(\.id) == ["full", "denied"])
        #expect(handoff.failedCommands.first?.result == "1 test failed")
        #expect(!handoff.receipt.hasChanges)
    }

    @Test func earlierFailuresDoNotLeakIntoANewTurn() throws {
        let handoff = try #require(TurnHandoff(messages: [
            ChatMessage(role: .user, text: "earlier"),
            ChatMessage(role: .assistant, tools: [
                ToolUse(id: "failure", name: "Bash", input: "swift test", result: "Failed", isError: true)
            ]),
            ChatMessage(role: .user, text: "current"),
            ChatMessage(role: .assistant, text: "No changes needed.")
        ], projectPath: "/repo"))
        #expect(handoff.failedCommands.isEmpty)
        #expect(!handoff.receipt.hasChanges)
        #expect(TurnHandoff(messages: [], projectPath: "/repo") == nil)
    }

    @Test func revisitingARecentEndingNeverReplaysItsArrival() {
        let ending = TurnEnding(started: ended.addingTimeInterval(-321), ended: ended, outcome: .finished)
        var arrival = TurnHandoffArrival()
        let opened = arrival.observe(ending, visible: false, now: ended)
        let revisited = arrival.observe(ending, visible: true, now: ended.addingTimeInterval(0.2))
        #expect(!opened)
        #expect(!revisited)
        let next = TurnEnding(started: ended, ended: ended.addingTimeInterval(20), outcome: .stopped)
        let finished = arrival.observe(next, visible: true, now: next.ended)
        let redrawn = arrival.observe(next, visible: true, now: next.ended)
        #expect(finished)
        #expect(!redrawn)
    }

    @Test func anOffscreenOrHistoricalFinishDoesNotArriveWhenScrolledIntoView() {
        let ending = TurnEnding(started: ended.addingTimeInterval(-321), ended: ended, outcome: .finished)
        var offscreen = TurnHandoffArrival()
        let hidden = offscreen.observe(ending, visible: false, now: ended)
        let scrolled = offscreen.observe(ending, visible: true, now: ended)
        #expect(!hidden)
        #expect(!scrolled)
        var historical = TurnHandoffArrival()
        let reopened = historical.observe(ending, visible: true, now: ended.addingTimeInterval(30))
        #expect(!reopened)
        #expect(!ending.isFresh(now: ended.addingTimeInterval(-1)))
    }

    @Test func theArrivalHasOneFiniteSequenceWithoutMovingTheLayout() {
        let start = TurnSealArrival(progress: 0)
        #expect(start.opacity == 0)
        #expect(start.offset == 6)
        #expect(start.markScale == 0.8)
        #expect(start.check == 0)
        #expect(TurnSealArrival(progress: 0.13 / 0.38).check == 0)
        let end = TurnSealArrival(progress: 1)
        #expect(abs(end.opacity - 1) < 0.001)
        #expect(abs(end.offset) < 0.001)
        #expect(abs(end.markScale - 1) < 0.001)
        #expect(abs(end.check - 1) < 0.001)
        #expect(TurnSealArrival.duration == 0.38)
    }
}

@MainActor
struct TurnHandoffLayoutTests {
    @Test func completeAndStoppedHandoffsWrapInsideANarrowTranscript() {
        for outcome: TurnEnding.Outcome in [.finished, .stopped, .failed] {
            for reviewed in [false, true] {
                let wide = measure(width: 600, outcome: outcome, reviewed: reviewed)
                #expect(abs(wide.height - 44) < 1)
                #expect(wide.width <= 600)
                let narrow = measure(width: 300, outcome: outcome, reviewed: reviewed)
                #expect(narrow.width <= 300)
                #expect(narrow.height > 44)
                #expect(narrow.height <= 122)
            }
        }
    }

    @Test func warningSitsBelowTheRowAndNoChangesStaysCompact() {
        let warning = measure(width: 600, warning: true)
        #expect(abs(warning.height - 67) < 1)
        let noChanges = measure(width: 300, changes: false)
        #expect(abs(noChanges.height - 44) < 1)
        #expect(noChanges.width <= 300)
    }

    private func measure(width: CGFloat, outcome: TurnEnding.Outcome = .finished,
                         reviewed: Bool = false, changes: Bool = true, warning: Bool = false) -> CGSize {
        let measured = Measurement()
        let ending = TurnEnding(started: Date(timeIntervalSinceReferenceDate: 0),
                                ended: Date(timeIntervalSinceReferenceDate: 321), outcome: outcome)
        let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
            TurnSeal(ending: ending,
                     receipt: changes ? TurnReceipt(added: 44, removed: 10, files: 4) : TurnReceipt(),
                     reviewed: reviewed,
                     failedCommands: warning ? [ToolUse(id: "test", name: "Bash", input: "swift test",
                                                       result: "Failed", exitCode: 1)] : [],
                     review: {})
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { measured.size = proxy.size }
                })
            Spacer(minLength: 0)
        }.environment(DialogPresenter()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        view.frame = CGRect(x: 0, y: 0, width: width, height: 240)
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
        }
        return measured.size
    }

    private final class Measurement { var size = CGSize.zero }
}
