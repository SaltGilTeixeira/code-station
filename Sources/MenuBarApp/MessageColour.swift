import AppKit
import SwiftUI

// The colour behind what a person sends in a session. The bubble's shape is fixed; only
// its colours are a choice.
enum MessageColour: String, CaseIterable, Identifiable {
    case projectIcon
    case stone
    case paper
    case lemon
    case leaf
    case ink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .projectIcon: "Project icon"
        case .stone: "Stone"
        case .paper: "Paper"
        case .lemon: "Lemon"
        case .leaf: "Leaf"
        case .ink: "Ink"
        }
    }

    // A session that belongs to no project or workspace has no icon to borrow from, so
    // Project icon falls back to Stone, the quietest of the fixed colours.
    @MainActor
    func style(projectTint: Theme.ProjectTint?) -> UserMessageStyle {
        switch self {
        case .projectIcon: projectTint.map { UserMessageStyle.tinted($0.colour) } ?? .stone
        case .stone: UserMessageStyle.stone
        case .paper: UserMessageStyle.paper
        case .lemon: UserMessageStyle.lemon
        case .leaf: UserMessageStyle.leaf
        case .ink: UserMessageStyle.ink
        }
    }
}

struct UserMessageStyle: Equatable {
    let fill: Color
    let ring: Color
    // Ink is dark on a light page and light on a dark one, so what sits inside it is drawn
    // in the other appearance. That flips the AppKit text views too, not just SwiftUI text.
    var inverts = false

    static let stone = UserMessageStyle(
        fill: Theme.adaptive(light: srgb(0.918, 0.902, 0.859), dark: srgb(0.153, 0.149, 0.137)),
        ring: Theme.adaptive(light: srgb(0.459, 0.420, 0.341, alpha: 0.14),
                             dark: srgb(1, 1, 1, alpha: 0.07)))
    static let paper = UserMessageStyle(
        fill: Theme.card,
        ring: Theme.adaptive(light: srgb(0.459, 0.420, 0.341, alpha: 0.22),
                             dark: srgb(1, 1, 1, alpha: 0.11)))
    // The brand yellow taken down to a wash.
    static let lemon = UserMessageStyle(
        fill: Theme.adaptive(light: srgb(0.953, 0.953, 0.831), dark: srgb(0.165, 0.169, 0.098)),
        ring: Theme.adaptive(light: srgb(0.667, 0.675, 0.157, alpha: 0.32),
                             dark: srgb(0.867, 0.878, 0.282, alpha: 0.16)))
    static let leaf = UserMessageStyle(fill: Theme.userMessage, ring: Theme.userMessageRing)
    static let ink = UserMessageStyle(
        fill: Theme.adaptive(light: srgb(0.169, 0.173, 0.149), dark: srgb(0.894, 0.882, 0.835)),
        ring: .clear,
        inverts: true)

    // A project colour laid over the canvas at low strength, the way a sidebar tile sits
    // behind its glyph. Dark mode needs more of the colour to stand off the canvas.
    // Built once per colour: the transcript compares styles to decide what to redraw, and
    // a fresh dynamic colour never equals the last one.
    @MainActor
    static func tinted(_ colour: Color) -> UserMessageStyle {
        if let style = tintedCache[colour] { return style }
        let base = NSColor(colour).usingColorSpace(.sRGB) ?? .gray
        let style = UserMessageStyle(
            fill: Theme.adaptive(
                light: Theme.canvasLightNSColor.blended(withFraction: 0.13, of: base) ?? base,
                dark: Theme.canvasDarkNSColor.blended(withFraction: 0.26, of: base) ?? base),
            ring: Theme.adaptive(light: base.withAlphaComponent(0.28),
                                 dark: base.withAlphaComponent(0.34)))
        tintedCache[colour] = style
        return style
    }

    @MainActor private static var tintedCache: [Color: UserMessageStyle] = [:]

    private static func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat,
                             alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension AppSettings {
    // The same colour the session's project or workspace wears in the sidebar, so a
    // bubble and the icon it belongs to always agree.
    @MainActor
    func userMessageStyle(for session: ChatSession, in store: ProjectStore) -> UserMessageStyle {
        guard messageColour == .projectIcon else { return messageColour.style(projectTint: nil) }
        let tint: Theme.ProjectTint? =
            if let workspace = session.workspaceID.flatMap(store.workspace) {
                workspace.sidebarAvatar.identityTint(
                    iconSet: sidebarIconSet, style: diceBearAvatarStyle,
                    name: workspace.name, monogramTint: Theme.workspaceTint)
            } else if let project = store.project(session.projectID) {
                project.sidebarAvatar.identityTint(
                    iconSet: sidebarIconSet, style: diceBearAvatarStyle,
                    name: project.name, monogramTint: Theme.projectTint(for: project.name))
            } else {
                nil
            }
        return messageColour.style(projectTint: tint)
    }
}
