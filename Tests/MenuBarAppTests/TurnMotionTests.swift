import Foundation
import SwiftUI
import Testing
@testable import MenuBarApp

// The start and end of a turn are told by motion, but what the motion lands on has to
// say the same thing without it: the node's resting look, the card's word and the seal's
// words. These hold those, and the timing the motion is built from.
@MainActor
struct TurnMotionTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Thread

    @Test func aRunningTurnOutranksEverythingTheLastOneLeft() {
        #expect(ThreadPhase(busy: true, failed: true, finished: true) == .running)
        #expect(ThreadPhase(busy: false, failed: true, finished: true) == .failed)
        #expect(ThreadPhase(busy: false, failed: false, finished: true) == .finished)
        #expect(ThreadPhase(busy: false, failed: false, finished: false) == .idle)
    }

    @Test func eachPhaseRestsOnItsOwnMark() {
        let idle = ThreadLook.resting(.idle)
        #expect(idle == ThreadLook())

        let running = ThreadLook.resting(.running)
        #expect(running.ring == 1)
        #expect(running.tick == 0 && running.bang == 0)

        // Done is a full dot with a tick, and the orbit is gone.
        let finished = ThreadLook.resting(.finished)
        #expect(finished.tick == 1)
        #expect(finished.ring == 0)
        #expect(finished.alarm == 0)

        // Failure is never told by colour alone: the dot also carries its own mark.
        let failed = ThreadLook.resting(.failed)
        #expect(failed.alarm == 1)
        #expect(failed.bang == 1)
        #expect(failed.tick == 0)
    }

    @Test func theOrbitIsSlowerThanTheFastestLoopAllowed() {
        #expect(TurnMotion.orbitPeriod >= 1.2)
        #expect(TurnMotion.arcPeriod >= 1.2)
    }

    @Test func theOrbitComesBackToWhereItStartedEachPeriod() {
        let moment = Self.start.addingTimeInterval(0.3)
        let later = moment.addingTimeInterval(TurnMotion.orbitPeriod * 3)
        let drift = (TurnMotion.orbit(at: later) - TurnMotion.orbit(at: moment)).degrees
        #expect(abs(drift.remainder(dividingBy: 360)) < 0.01)
        #expect(TurnMotion.orbit(at: Self.start).degrees.isNear(0))
        let half = Self.start.addingTimeInterval(TurnMotion.orbitPeriod / 2)
        #expect(TurnMotion.orbit(at: half).degrees.isNear(180))
    }

    @Test func theArcNeitherVanishesNorClosesWhileRunning() {
        for step in 0...100 {
            let date = Self.start.addingTimeInterval(TurnMotion.arcPeriod * Double(step) / 50)
            let length = TurnMotion.arcLength(at: date)
            #expect(length >= 0.22 - 0.000_1 && length <= 0.48 + 0.000_1)
        }
    }

    @Test func theBeadWaitsAtTheTopThenLandsInTheNode() {
        #expect(TurnMotion.fall(0) == 0)
        #expect(TurnMotion.fall(0.1) == 0)
        #expect(Double(TurnMotion.fall(1)).isNear(1))
        var previous: CGFloat = 0
        for step in 0...100 {
            let fall = TurnMotion.fall(CGFloat(step) / 100)
            #expect(fall >= previous, "the bead rose at step \(step)")
            previous = fall
        }
    }

    @Test func theShakeSettlesWhereItBegan() {
        #expect(TurnMotion.shake(0) == 0)
        #expect(TurnMotion.shake(1) == 0)
        for step in 0...100 {
            #expect(abs(TurnMotion.shake(CGFloat(step) / 100)) <= 4)
        }
    }

    // A replayed effect counts up by one each run, so a whole number is always rest.
    @Test func aCountedRunRestsBetweenRuns() {
        #expect(TurnMotion.stage(0) == 0)
        #expect(TurnMotion.stage(3) == 0)
        #expect(Double(TurnMotion.stage(2.25)).isNear(0.25))
    }

    // MARK: - Hand-off

    @Test func aTurnsLengthReadsAsAClock() {
        #expect(TurnReceipt.clock(0) == "0:00")
        #expect(TurnReceipt.clock(7.9) == "0:07")
        #expect(TurnReceipt.clock(760) == "12:40")
        #expect(TurnReceipt.clock(3725) == "1:02:05")
    }

    @Test func theSealSaysHowTheTurnEnded() {
        let finished = ending(seconds: 7, .finished)
        let changes = TurnReceipt(added: 48, removed: 6, files: 3)
        #expect(changes.summary(finished) == "Finished in 0:07 · +48 \u{2212}6 · 3 files")
        #expect(TurnReceipt().summary(finished) == "Finished in 0:07")
        #expect(TurnReceipt(added: 2, removed: 0, files: 1).summary(finished)
            == "Finished in 0:07 · +2 \u{2212}0 · 1 file")
        #expect(TurnReceipt().summary(ending(seconds: 65, .failed)) == "Stopped after 1:05")
        #expect(TurnReceipt().summary(ending(seconds: 3, .stopped)) == "Stopped after 0:03")
    }

    @Test func theSealIsSpokenInWords() {
        let spoken = TurnReceipt(added: 48, removed: 6, files: 3)
            .spokenSummary(ending(seconds: 7, .finished))
        #expect(spoken.contains("48 lines added, 6 removed, in 3 files"))
        #expect(!spoken.contains("\u{2212}"))
    }

    @Test func onlyAnEndingJustNowStampsItself() {
        let ended = ending(seconds: 7, .finished)
        #expect(ended.isFresh(now: ended.ended.addingTimeInterval(0.5)))
        #expect(!ended.isFresh(now: ended.ended.addingTimeInterval(30)))
    }

    @Test func theReceiptCountsOnlyTheLastTurn() throws {
        let earlier = assistant([edit("e1", path: "/repo/old.swift", old: "a", new: "b")])
        let messages = [
            ChatMessage(role: .user, text: "first"),
            earlier,
            ChatMessage(role: .user, text: "second"),
            assistant([
                edit("e2", path: "/repo/a.swift", old: "x", new: "y\nz"),
                edit("e3", path: "/repo/a.swift", old: "p", new: "q"),
                write("w1", path: "/repo/b.swift", content: "1\n2\n3"),
                ToolUse(id: "r1", name: "Read", input: #"{"file_path":"/repo/c.swift"}"#,
                        result: "…"),
            ]),
        ]
        let receipt = try #require(TurnReceipt(lastTurnIn: messages, projectPath: "/repo"))
        // Two edits to one file count it once; a file that was only read is not counted.
        #expect(receipt.files == 2)
        #expect(receipt.added == 2 + 1 + 3)
        #expect(receipt.removed == 1 + 1)
    }

    @Test func aTranscriptWithNoPromptHasNoReceipt() {
        #expect(TurnReceipt(lastTurnIn: [], projectPath: "/repo") == nil)
        #expect(TurnReceipt(lastTurnIn: [ChatMessage(role: .system, text: "note")],
                            projectPath: "/repo") == nil)
    }

    // MARK: - Helpers

    private func ending(seconds: TimeInterval, _ outcome: TurnEnding.Outcome) -> TurnEnding {
        TurnEnding(started: Self.start, ended: Self.start.addingTimeInterval(seconds),
                   outcome: outcome)
    }

    private func assistant(_ tools: [ToolUse]) -> ChatMessage {
        var message = ChatMessage(role: .assistant, text: "Done.")
        message.tools = tools
        return message
    }

    private func edit(_ id: String, path: String, old: String, new: String) -> ToolUse {
        ToolUse(id: id, name: "Edit", input: json(["file_path": path, "old_string": old,
                                                   "new_string": new]),
                result: "ok")
    }

    private func write(_ id: String, path: String, content: String) -> ToolUse {
        ToolUse(id: id, name: "Write", input: json(["file_path": path, "content": content]),
                result: "ok")
    }

    private func json(_ fields: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

private extension Double {
    func isNear(_ other: Double) -> Bool { abs(self - other) < 0.000_1 }
}
