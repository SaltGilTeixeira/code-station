import Foundation
import Testing
@testable import MenuBarApp

struct HomeWorkMapTests {
    private func live(project: UUID = UUID(), workspace: UUID? = nil,
                      name: String = "Project", tone: SessionTone = .running,
                      permission: PermissionRequest? = nil, finished: Bool = false,
                      destination: SessionDestination = .conversation) -> HomeLive {
        var session = ChatSession(projectID: project, agent: .codex)
        session.workspaceID = workspace
        return HomeLive(session: session, liveID: session.id, containerName: name,
                        tint: Theme.projectTint(for: name),
                        avatar: SidebarAvatar(subject: workspace == nil ? .project : .workspace,
                                              id: workspace ?? project),
                        tone: tone, activity: "Working", location: "project folder",
                        destination: destination, permission: permission, finished: finished)
    }

    private var permission: PermissionRequest {
        PermissionRequest(id: "request", toolName: "Bash", title: "Run checks",
                          subject: "swift test", detail: "", input: Data(),
                          suggestions: nil, alwaysTitle: nil, questions: [])
    }

    @Test func groupsByIdentityAndKeepsWorkspaceSessionsTogether() {
        let project = UUID()
        let workspace = UUID()
        let standalone = live(project: project)
        let attached = live(project: project, workspace: workspace)
        let otherLead = live(workspace: workspace)
        let sameName = live()
        let idle = live(tone: .idle)
        let map = HomeWorkMap(sessions: [standalone, attached, otherLead, sameName, idle])

        #expect(map.groups.count == 3)
        #expect(map.groups.first { $0.id == workspace }?.sessions.count == 2)
        #expect(map.active.count == 4)
        #expect(map.sessions.count == 5)
    }

    @Test func countsWorkSeparatelyFromBackgroundWaitsAndAttention() {
        let map = HomeWorkMap(sessions: [live(), live(tone: .waiting),
                                        live(tone: .needsYou), live(tone: .idle)])
        #expect(map.runningCount == 1)
        #expect(map.waiting.count == 1)
        #expect(map.active.count == 3)
    }

    @Test func routesReviewToChangesOnlyWhenThereAreChanges() {
        let review = live(tone: .needsYou, finished: true)
        #expect(review.primaryAction(hasChanges: true).destination == .changes)
        #expect(review.primaryAction(hasChanges: false).destination == .conversation)
        let stale = live(tone: .needsYou)
        #expect(stale.primaryAction(hasChanges: true).title == "Open session")
        #expect(stale.status == "Needs your attention")
    }

    @Test func permissionsAndDesignsKeepTheirConversationDestination() {
        let request = live(tone: .needsYou, permission: permission)
        #expect(request.primaryAction(hasChanges: true).destination == .conversation)
        #expect(request.primaryAction(hasChanges: true).title == "View request")
        let design = live(tone: .needsYou, permission: permission, destination: .design)
        #expect(design.primaryAction(hasChanges: true).destination == .design)
        let designReview = live(tone: .needsYou, finished: true, destination: .design)
        #expect(designReview.primaryAction(hasChanges: true).destination == .design)
    }

    @Test func sortsSessionsByWhoNeedsYouThenWhatIsRunning() {
        let project = UUID()
        let waiting = live(project: project, tone: .waiting)
        let running = live(project: project, tone: .running)
        let needs = live(project: project, tone: .needsYou)
        let map = HomeWorkMap(sessions: [waiting, running, needs])
        #expect(map.groups[0].sessions.map(\.id) == [needs.id, running.id, waiting.id])
        #expect(map.backgroundWaitCount == 1)
    }

    @Test func offersQuickAnswersOnlyForShortRequests() {
        let allow = live(tone: .needsYou, permission: permission)
        #expect(allow.quickAnswers.map(\.title) == ["Allow", "Deny"])
        #expect(allow.quickAnswers.map(\.answer) == [.allowOnce, .deny])

        var plan = permission
        plan.subjectIsMarkdown = true
        #expect(live(tone: .needsYou, permission: plan).quickAnswers.isEmpty)

        let question = AgentQuestion(id: 0, header: "", text: "Keep the hub?", multiSelect: false,
                                     options: [.init(id: 0, label: "Keep it", description: ""),
                                               .init(id: 1, label: "Replace it", description: "")])
        let asked = live(tone: .needsYou, permission: request(questions: [question]))
        #expect(asked.quickAnswers.map(\.title) == ["Keep it", "Replace it"])
        #expect(asked.quickAnswers.first?.answer == .answers(["Keep the hub?": "Keep it"]))

        let several = AgentQuestion(id: 0, header: "", text: "Which?", multiSelect: true,
                                    options: question.options)
        #expect(live(tone: .needsYou, permission: request(questions: [several])).quickAnswers.isEmpty)
        #expect(live(tone: .needsYou, permission: request(questions: [question, question]))
            .quickAnswers.isEmpty)
        #expect(live(tone: .needsYou, finished: true).quickAnswers.isEmpty)
    }

    @Test func orbitLaysOutABusyDayWithoutOverlaps() {
        var sessions: [HomeLive] = []
        let counts = [3, 2, 2, 1, 2, 1, 1]
        for (index, count) in counts.enumerated() {
            let project = UUID()
            for slot in 0..<count {
                sessions.append(live(project: project, name: "Project \(index)",
                                     tone: slot == 0 && index.isMultiple(of: 2) ? .needsYou : .running))
            }
        }
        #expect(sessions.count == 12)
        for width in [OrbitLayout.minWidth, 1000, 1400] {
            expectNoOverlaps(OrbitLayout(map: HomeWorkMap(sessions: sessions), width: width))
        }
    }

    private func expectNoOverlaps(_ layout: OrbitLayout) {
        let width = layout.size.width

        #expect(layout.nodes.count == 7)
        #expect(layout.pills.count == 12)
        let hub = CGRect(x: layout.hub.x - OrbitLayout.hubSide / 2, y: layout.hub.y - OrbitLayout.hubSide / 2,
                         width: OrbitLayout.hubSide, height: OrbitLayout.hubSide)
        let tiles = layout.nodes.map {
            CGRect(x: $0.center.x - 30, y: $0.center.y - 30, width: 60, height: 76)
        }
        let shapes = layout.pills.map(\.frame) + tiles + [hub]
        for (index, shape) in shapes.enumerated() {
            #expect(shape.minX >= 0 && shape.maxX <= width && shape.minY >= 0
                    && shape.maxY <= layout.size.height)
            for other in shapes[(index + 1)...] {
                #expect(!shape.intersects(other))
            }
        }
    }

    @Test func orbitGrowsTallerInsteadOfSqueezingAColumn() {
        var sessions: [HomeLive] = []
        for index in 0..<8 {
            let project = UUID()
            sessions += (0..<3).map { _ in live(project: project, name: "P\(index)", tone: .needsYou) }
        }
        let layout = OrbitLayout(map: HomeWorkMap(sessions: sessions), width: 1000)
        #expect(layout.size.height > OrbitLayout.minHeight)
        let frames = layout.pills.map(\.frame)
        for (index, frame) in frames.enumerated() {
            #expect(frame.height == OrbitLayout.tallPillHeight)
            for other in frames[(index + 1)...] { #expect(!frame.intersects(other)) }
        }
    }

    @Test func orbitFoldsSessionsPastThreeIntoAChip() {
        let project = UUID()
        let sessions = (0..<5).map { _ in live(project: project, name: "Busy") }
        let layout = OrbitLayout(map: HomeWorkMap(sessions: sessions), width: 1000)
        #expect(layout.pills.count == OrbitLayout.shownPerProject)
        #expect(layout.more.map(\.count) == [2])
        #expect(layout.more[0].frame.minY > layout.pills.map(\.frame.maxY).max() ?? 0)
    }

    @Test func orbitWiresFollowTheStateOfWhatTheyLeadTo() {
        let project = UUID()
        let needs = live(project: project, tone: .needsYou)
        let running = live(project: project)
        let waiting = live(tone: .waiting)
        let layout = OrbitLayout(map: HomeWorkMap(sessions: [needs, running, waiting]), width: 1000)
        let kinds = Dictionary(uniqueKeysWithValues: layout.wires.map { ($0.id, $0.kind) })
        #expect(kinds["hub:\(project)"] == .attention)
        #expect(kinds["session:\(needs.id)"] == .attention)
        #expect(kinds["session:\(running.id)"] == .running)
        #expect(kinds["session:\(waiting.id)"] == .quiet)
        #expect(layout.pills.first { $0.id == needs.id }?.frame.height == OrbitLayout.tallPillHeight)
    }

    @Test func emptyOrbitKeepsOnlyTheHub() {
        let layout = OrbitLayout(map: HomeWorkMap(sessions: [live(tone: .idle)]), width: 1000)
        #expect(layout.nodes.isEmpty && layout.pills.isEmpty && layout.wires.isEmpty)
        #expect(layout.size.height == OrbitLayout.emptyHeight)
    }

    private func request(questions: [AgentQuestion]) -> PermissionRequest {
        PermissionRequest(id: "question", toolName: "AskUserQuestion", title: "Question",
                          subject: "", detail: "", input: Data(), suggestions: nil,
                          alwaysTitle: nil, questions: questions)
    }
}
