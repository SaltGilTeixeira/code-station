import AppKit
import SwiftUI
import Testing
@testable import MenuBarApp

// The colour behind a person's own messages, picked in Settings.
@MainActor
struct MessageColourTests {
    @Test func projectIconIsTheDefaultAndThePickIsKept() throws {
        let suite = "MessageColourTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences.messageColour(in: defaults) == .projectIcon)
        Preferences.setMessageColour(.ink, in: defaults)
        #expect(Preferences.messageColour(in: defaults) == .ink)
        defaults.set("not-a-colour", forKey: "messageColour")
        #expect(Preferences.messageColour(in: defaults) == .projectIcon)
    }

    // Leaf is the colour the bubble always had, kept for anyone who liked it.
    @Test func leafIsTheOriginalBubble() {
        #expect(MessageColour.leaf.style(projectTint: nil)
            == UserMessageStyle(fill: Theme.userMessage, ring: Theme.userMessageRing))
    }

    @Test func aSessionOutsideAnyProjectFallsBackToStone() {
        #expect(MessageColour.projectIcon.style(projectTint: nil) == .stone)
    }

    // The transcript only redraws a message whose inputs changed, so the same project
    // colour has to give back an equal style every time it is asked for.
    @Test func theSameProjectColourGivesAnEqualStyle() {
        let tint = Theme.projectTint(for: "orbit-api")
        #expect(MessageColour.projectIcon.style(projectTint: tint)
            == MessageColour.projectIcon.style(projectTint: tint))
    }

    @Test func bodyTextReadsOnEveryColourInBothAppearances() throws {
        let tinted = sampleTints().map { UserMessageStyle.tinted($0) }
        let fixed: [UserMessageStyle] = [.stone, .paper, .lemon, .leaf, .ink]
        for appearance in try appearances() {
            for (index, style) in (fixed + tinted).enumerated() {
                let fill = try swatch(style.fill, in: appearance)
                let textAppearance = style.inverts ? try inverted(appearance) : appearance
                let text = try swatch(Color(nsColor: .labelColor), in: textAppearance).over(fill)
                #expect(text.contrast(against: fill) >= 4.5,
                        "style \(index) on \(appearance.name.rawValue)")
            }
        }
    }

    // With Project icon on, two sessions from different projects have to be told apart by
    // the bubble alone.
    @Test func everyProjectColourGivesItsOwnBubble() throws {
        let wheel = projectWheel()
        #expect(wheel.count == 12)
        for appearance in try appearances() {
            let fills = try wheel.map { try swatch(UserMessageStyle.tinted($0).fill, in: appearance) }
            for (i, a) in fills.enumerated() {
                for b in fills[(i + 1)...] {
                    let gap = max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))
                    #expect(gap > 0.01, "\(appearance.name.rawValue)")
                }
            }
        }
    }

    private func inverted(_ appearance: NSAppearance) throws -> NSAppearance {
        try #require(NSAppearance(named: Theme.isDark(appearance) ? .aqua : .darkAqua))
    }

    private func projectWheel() -> [Color] {
        var seen: [Color] = []
        for index in 0..<500 {
            let colour = Theme.projectTint(for: "project-\(index)").colour
            if !seen.contains(colour) { seen.append(colour) }
        }
        return seen
    }

    // The project wheel, the workspace olive, and the extremes a sidebar artwork's
    // background could hand over.
    private func sampleTints() -> [Color] {
        projectWheel() + [Theme.workspaceTint.colour, Theme.brand, .white, .black,
                          Color(red: 1, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1)]
    }
}
