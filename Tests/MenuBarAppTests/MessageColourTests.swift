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

    // Near-black Planets grounds and pale Stripes ones used to give a grey bubble. Every
    // icon in every style has to show its project's colour, in both appearances.
    @Test func everySidebarIconGivesAColourfulBubble() throws {
        let tints = sampleTints() + everyArtworkTint().map(\.tint)
        for appearance in try appearances() {
            for (index, tint) in tints.enumerated() {
                let fill = try swatch(UserMessageStyle.tinted(tint).fill, in: appearance)
                let chroma = OKLCH(red: fill.red, green: fill.green, blue: fill.blue).chroma
                #expect(chroma >= 0.02, "tint \(index) on \(appearance.name.rawValue)")
            }
        }
    }

    // The bubble is only worth having if it reads as the icon in the sidebar, including
    // the styles drawn in several colours with no one background.
    @Test func theBubbleSharesItsHueWithTheSidebarIcon() throws {
        for (style, tint) in everyArtworkTint() {
            let icon = try #require(OKLCH(NSColor(tint)))
            guard icon.chroma >= 0.02 else { continue }
            for appearance in try appearances() {
                let fill = try swatch(UserMessageStyle.tinted(tint).fill, in: appearance)
                let bubble = OKLCH(red: fill.red, green: fill.green, blue: fill.blue)
                let gap = abs(bubble.hue - icon.hue)
                #expect(min(gap, 360 - gap) < 12, "\(style.label) on \(appearance.name.rawValue)")
            }
        }
    }

    @Test func multiColourArtworkGivesAHueFromItsOwnDrawing() throws {
        for style in [DiceBearAvatarStyle.shapes, .landscape, .weave] {
            for index in 1...SidebarAvatar.artworkCount {
                let avatar = SidebarAvatar(subject: .project, id: UUID(), artworkIndex: index)
                let tint = avatar.identityTint(iconSet: .diceBear, style: style,
                                              name: "orbit-api",
                                              monogramTint: Theme.projectTint(for: "orbit-api"))
                let colour = try #require(OKLCH(NSColor(tint.colour)))
                #expect(colour.chroma >= 0.04, "\(style.label) \(index)")
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

    private func everyArtworkTint() -> [(style: DiceBearAvatarStyle, tint: Color)] {
        DiceBearAvatarStyle.allCases.flatMap { style in
            (1...SidebarAvatar.artworkCount).map { index in
                let avatar = SidebarAvatar(subject: .project, id: UUID(), artworkIndex: index)
                let tint = avatar.identityTint(iconSet: .diceBear, style: style,
                                              name: "orbit-api",
                                              monogramTint: Theme.projectTint(for: "orbit-api"))
                return (style, tint.colour)
            }
        }
    }

    // The project wheel, the workspace olive, and the extremes a sidebar artwork's
    // background could hand over.
    private func sampleTints() -> [Color] {
        projectWheel() + [Theme.workspaceTint.colour, Theme.brand, .white, .black,
                          Color(red: 1, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1)]
    }
}
