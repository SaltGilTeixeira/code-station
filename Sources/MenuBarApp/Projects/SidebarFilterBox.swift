import SwiftUI

// The sidebar's filter box: what has been typed, and the three pieces of state that hang
// off it. They move together, so they are held together. Clearing the text has to decide
// whether the rail jumps back to the current row, and opening a row while filtering has
// to remember which one so that row's sessions stay whole.
//
// `SidebarFilter` is the matching rule this hands out. This is the control around it.
struct SidebarFilterBox {
    // Bound straight to the text field, so it is the one part a person writes directly.
    var text = ""

    // Whether the narrow tree field was opened deliberately. The field also stays up on
    // its own while there is text in it, which is what `showsField` folds together.
    private(set) var isFieldOpen = false

    // The one container opened while filtering. Its sessions are shown whole rather than
    // narrowed, so a row the filter matched can be explored without clearing the box.
    private(set) var revealedContainerID: UUID?

    // Set when a disclosure cleared the filter rather than a person. That clear must not
    // also jump the rail back to the current row: the click already said where to look.
    private(set) var clearedForDisclosure = false

    var filter: SidebarFilter { SidebarFilter(text) }
    var query: String { filter.query }
    var isActive: Bool { filter.isActive }
    var showsField: Bool { isFieldOpen || !text.isEmpty }

    // Whatever was typed makes the reveal stale: it was granted to a row the old query
    // matched, and the new one may not match it at all.
    mutating func typed() {
        revealedContainerID = nil
    }

    // Cleared by a person, or by navigation that needs the whole rail back.
    mutating func clear() {
        text = ""
    }

    // Cleared by opening or closing a row while filtering. The rail must not then chase
    // the current row, so this leaves a note for the clear that follows.
    mutating func clearForDisclosure() {
        clearedForDisclosure = true
        text = ""
    }

    // Answers once whether the clear that just happened came from a disclosure, and
    // forgets it. A note left standing would swallow the next clear a person made.
    mutating func wasClearedForDisclosure() -> Bool {
        defer { clearedForDisclosure = false }
        return clearedForDisclosure
    }

    // Only meaningful while filtering: with the whole rail showing there is nothing for a
    // reveal to widen.
    mutating func reveal(_ containerID: UUID) {
        guard isActive else { return }
        revealedContainerID = containerID
    }

    func revealsEverything(in containerID: UUID) -> Bool {
        revealedContainerID == containerID
    }

    mutating func openField() {
        isFieldOpen = true
    }

    // The close button empties a box that has something in it, and closes one that is
    // already empty, so the same button never needs a second press to get out of the way.
    mutating func closeOrClear() {
        if text.isEmpty {
            isFieldOpen = false
        } else {
            text = ""
        }
    }

    // Escape, or leaving an empty field, puts the whole box away in one go.
    mutating func close() {
        text = ""
        isFieldOpen = false
    }
}
