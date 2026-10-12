import Foundation
import Observation

@MainActor
@Observable
final class ProjectNavigation {
    var selection: SidebarSelection?
    var selectedProjectID: UUID?
    var history = NavigationHistory()
    var sessionOpenRequest: SessionOpenRequest?
    var projectToReveal: UUID?
    var sessionToReveal: UUID?
    var sidebarHighlight: UUID?
    var pointedSidebarItem: UUID?
    @ObservationIgnored var lastSessionTabs: [UUID: SessionDestination] = [:]
    @ObservationIgnored var isWalkingHistory = false

    var currentPlace: NavigationPlace? {
        switch selection {
        case .home: .home
        case .session(let id): .session(id)
        case .workspace(let id): .workspace(id)
        case nil: selectedProjectID.map(NavigationPlace.project)
        }
    }

    func arrived() {
        persistSelection()
        recordVisit()
    }

    func recordVisit() {
        guard !isWalkingHistory, let currentPlace else { return }
        history.visit(currentPlace)
    }

    // Navigation is a preference and never needs to rewrite the project index.
    func persistSelection() {
        Preferences.selectedSessionID = if case .session(let id) = selection { id } else { nil }
        Preferences.selectedWorkspaceID = if case .workspace(let id) = selection { id } else { nil }
        Preferences.selectedProjectID = selectedProjectID
    }
}
