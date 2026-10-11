import SwiftUI

// Where every shape on the orbit map sits. Worked out from the map and the width alone, so
// it can be checked without drawing anything.
//
// Projects take a left and a right column so their sessions always have room to reach
// outward, away from the hub. A column grows the map taller rather than squeezing its
// rows, so a busy day pushes the card down instead of laying sessions over each other.
struct OrbitLayout {
    struct Node: Identifiable {
        let group: HomeWorkMap.Group
        let center: CGPoint
        let left: Bool
        var id: UUID { group.id }
    }

    struct Pill: Identifiable {
        let live: HomeLive
        let frame: CGRect
        var id: UUID { live.id }
    }

    struct More: Identifiable {
        let id: UUID
        let count: Int
        let name: String
        let frame: CGRect
    }

    struct Wire: Identifiable {
        enum Kind { case running, attention, quiet }
        let id: String
        let start: CGPoint
        let end: CGPoint
        let kind: Kind
        // From the hub to a project, drawn a little heavier than a project to a session.
        let trunk: Bool
    }

    static let minHeight: CGFloat = 540
    static let emptyHeight: CGFloat = 420
    static let hubSide: CGFloat = 176
    static let tileSide: CGFloat = 48
    static let pillHeight: CGFloat = 34
    static let tallPillHeight: CGFloat = 48
    static let pillGap: CGFloat = 8
    static let shownPerProject = 3
    // A narrower map leaves the session pills too short to read a title in.
    static let minWidth: CGFloat = 860

    // How much height a project takes when it has a single session: the tile, its halo and
    // the name under it.
    private static let nodeExtent: CGFloat = 92
    private static let margin: CGFloat = 40
    private static let rowGap: CGFloat = 22
    // Past this a column with only two projects would push them to the corners.
    private static let widestRowGap: CGFloat = 96
    private static let pillReach: CGFloat = 52

    let size: CGSize
    let hub: CGPoint
    let pillWidth: CGFloat
    private(set) var nodes: [Node] = []
    private(set) var pills: [Pill] = []
    private(set) var more: [More] = []
    private(set) var wires: [Wire] = []

    // Everything that moves when the map changes, so the move can be animated as one.
    var motionKey: [CGRect] {
        nodes.map { CGRect(origin: $0.center, size: .zero) } + pills.map(\.frame) + more.map(\.frame)
    }

    init(map: HomeWorkMap, width: CGFloat) {
        let groups = map.groups
        let leftCount = (groups.count + 1) / 2
        let columns = [(Array(groups.prefix(leftCount)), true),
                       (Array(groups.dropFirst(leftCount)), false)]

        func stack(_ group: HomeWorkMap.Group) -> (shown: [HomeLive], hidden: Int, height: CGFloat) {
            let shown = Array(group.sessions.prefix(Self.shownPerProject))
            let hidden = group.sessions.count - shown.count
            let heights = shown.map(Self.height(of:)) + (hidden > 0 ? [Self.pillHeight] : [])
            return (shown, hidden, heights.reduce(0, +) + Self.pillGap * CGFloat(heights.count - 1))
        }
        func extent(_ group: HomeWorkMap.Group) -> CGFloat { max(Self.nodeExtent, stack(group).height) }

        let available = Self.minHeight - 2 * Self.margin
        let spacing = columns.map { column, _ -> (gap: CGFloat, height: CGFloat) in
            let total = column.map(extent).reduce(0, +)
            guard column.count > 1 else { return (0, total) }
            let gap = min(max(Self.rowGap, (available - total) / CGFloat(column.count - 1)),
                          Self.widestRowGap)
            return (gap, total + gap * CGFloat(column.count - 1))
        }

        let height = groups.isEmpty
            ? Self.emptyHeight
            : max(Self.minHeight, (spacing.map(\.height).max() ?? 0) + 2 * Self.margin)
        size = CGSize(width: width, height: height)
        let centerX = width / 2
        let centerY = groups.isEmpty ? 170 : height / 2
        hub = CGPoint(x: centerX, y: centerY)

        let reach = min(300, max(190, width * 0.22))
        pillWidth = min(260, centerX - reach - 62)

        for (index, (column, left)) in columns.enumerated() {
            var top = centerY - spacing[index].height / 2
            for group in column {
                let rowHeight = extent(group)
                let y = top + rowHeight / 2
                // Rows further from the middle bend in towards the hub, which is what turns
                // two columns into an orbit.
                let bend = min(abs(y - centerY), 200) * 0.32
                let x = left ? centerX - reach + bend : centerX + reach - bend
                nodes.append(Node(group: group, center: CGPoint(x: x, y: y), left: left))

                let busiest: Wire.Kind = group.sessions.contains(where: \.needsAttention) ? .attention
                    : group.sessions.contains(where: { $0.tone == .running }) ? .running : .quiet
                wires.append(Wire(id: "hub:\(group.id)",
                                  start: CGPoint(x: centerX + (left ? -1 : 1) * Self.hubSide / 2,
                                                 y: centerY),
                                  end: CGPoint(x: x + (left ? 1 : -1) * (Self.tileSide / 2 + 7), y: y),
                                  kind: busiest, trunk: true))

                let (shown, hidden, stackHeight) = stack(group)
                let pillX = left ? x - Self.pillReach - pillWidth : x + Self.pillReach
                var pillY = y - stackHeight / 2
                for live in shown {
                    let frame = CGRect(x: pillX, y: pillY, width: pillWidth, height: Self.height(of: live))
                    pills.append(Pill(live: live, frame: frame))
                    wires.append(Wire(id: "session:\(live.id)",
                                      start: CGPoint(x: x + (left ? -1 : 1) * (Self.tileSide / 2 + 7), y: y),
                                      end: CGPoint(x: left ? frame.maxX : frame.minX, y: frame.midY),
                                      kind: live.needsAttention ? .attention
                                          : live.tone == .running ? .running : .quiet,
                                      trunk: false))
                    pillY = frame.maxY + Self.pillGap
                }
                if hidden > 0 {
                    more.append(More(id: group.id, count: hidden, name: group.identity.containerName,
                                     frame: CGRect(x: pillX, y: pillY, width: pillWidth,
                                                   height: Self.pillHeight)))
                }
                top += rowHeight + spacing[index].gap
            }
        }
    }

    // A session that needs you is the one tall shape on the map, so it is found first.
    static func height(of live: HomeLive) -> CGFloat {
        live.needsAttention ? tallPillHeight : pillHeight
    }
}

// The work map drawn around a hub whose ring has one arc for every session. Projects sit
// on either side with their sessions beside them, and a session that needs you grows
// larger and turns amber. Clicking a session opens its card, where a request can be
// answered without leaving Home.
struct OrbitMap: View {
    let map: HomeWorkMap
    let width: CGFloat
    let hasChanges: (HomeLive) -> Bool
    let open: (HomeLive, SessionDestination) -> Void
    let answer: (HomeLive, PermissionAnswer) -> Void

    @State private var selected: UUID?
    @State private var cardHeight: CGFloat = 190

    var body: some View {
        let layout = OrbitLayout(map: map, width: width)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }

            // Two faint orbits, so the map keeps its shape even when nothing is on it.
            let room = 2 * min(layout.hub.y, layout.size.height - layout.hub.y)
            Group {
                Ellipse()
                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 420, height: min(300, room - 40))
                Ellipse()
                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: min(760, width - 40), height: min(470, room - 10))
            }
            .position(layout.hub)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            OrbitWires(wires: layout.wires)

            OrbitHub(map: map)
                .position(layout.hub)

            if map.active.isEmpty {
                VStack(spacing: 8) {
                    Text("Room for your next idea").font(.serif(20, .semibold))
                    Text("Nothing is running. Start something new, or pick up where you left off.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 420)
                .position(x: layout.hub.x, y: layout.hub.y + OrbitLayout.hubSide / 2 + 56)
            }

            ForEach(layout.nodes) { node in
                OrbitProjectTile(group: node.group)
                    .position(node.center)
                Text(node.group.identity.containerName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 130)
                    .position(x: node.center.x, y: node.center.y + OrbitLayout.tileSide / 2 + 19)
            }

            ForEach(layout.pills) { pill in
                OrbitSessionPill(live: pill.live, selected: selected == pill.id) {
                    selected = selected == pill.id ? nil : pill.id
                }
                .frame(width: pill.frame.width, height: pill.frame.height)
                .position(x: pill.frame.midX, y: pill.frame.midY)
            }

            ForEach(layout.more) { more in
                Text("+\(more.count) more in \(more.name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .frame(width: more.frame.width, height: more.frame.height, alignment: .leading)
                    .cardSurface(cornerRadius: more.frame.height / 2)
                    .position(x: more.frame.midX, y: more.frame.midY)
            }

            if let selected, let pill = layout.pills.first(where: { $0.id == selected }) {
                card(for: pill, in: layout)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .motion(HomeWorkMapView.reflow, value: layout.motionKey)
        .onExitCommand { selected = nil }
    }

    // Under the session when it fits, above it when it would run off the bottom of the map.
    private func card(for pill: OrbitLayout.Pill, in layout: OrbitLayout) -> some View {
        let half = OrbitSessionCard.width / 2
        let x = min(max(pill.frame.midX, half + 10), layout.size.width - half - 10)
        let below = pill.frame.maxY + 10 + cardHeight <= layout.size.height - 6
        let y = below ? pill.frame.maxY + 10 + cardHeight / 2 : pill.frame.minY - 10 - cardHeight / 2
        let live = pill.live
        return OrbitSessionCard(
            live: live,
            hasChanges: hasChanges(live),
            open: { destination in
                selected = nil
                open(live, destination)
            },
            answer: { given in
                selected = nil
                answer(live, given)
            })
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .position(x: x, y: min(max(y, cardHeight / 2 + 6), layout.size.height - cardHeight / 2 - 6))
            .zIndex(2)
            .transition(.opacity)
    }
}

// The lines from the hub to each project and on to its sessions. A line flows while what
// it leads to is running, and stands still otherwise, so motion on the map always means
// work is happening.
private struct OrbitWires: View {
    let wires: [OrbitLayout.Wire]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dash: CGFloat = 8
    private static let flowPeriod: TimeInterval = 0.48

    var body: some View {
        let flowing = !reduceMotion && wires.contains { $0.kind == .running }
        TimelineView(.animation(paused: !flowing)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.flowPeriod) / Self.flowPeriod
            let phase = flowing ? -Self.dash * turn : 0
            ZStack {
                ForEach(wires) { wire in
                    MapConnector(start: wire.start, end: wire.end)
                        .stroke(colour(wire), style: style(wire, phase: phase))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func colour(_ wire: OrbitLayout.Wire) -> Color {
        switch wire.kind {
        case .attention: Theme.attention.opacity(0.7)
        case .running: Theme.accent.opacity(0.4)
        case .quiet: Theme.accent.opacity(0.22)
        }
    }

    private func style(_ wire: OrbitLayout.Wire, phase: CGFloat) -> StrokeStyle {
        let width: CGFloat = wire.trunk ? 1.6 : 1.2
        return switch wire.kind {
        case .attention: StrokeStyle(lineWidth: width)
        case .running: StrokeStyle(lineWidth: width, lineCap: .round, dash: [2, 6], dashPhase: phase)
        case .quiet: StrokeStyle(lineWidth: width, dash: [2, 4])
        }
    }
}

// The middle of the map. The ring has one arc for every session, in the colour of its
// state, so the overall picture reads before any label does.
private struct OrbitHub: View {
    let map: HomeWorkMap

    private static let radius: CGFloat = 80
    private static let ringWidth: CGFloat = 8
    // The space left between two arcs, measured along the ring.
    private static let arcGap: CGFloat = 14

    var body: some View {
        let arcs = arcs
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: Self.ringWidth)
                .frame(width: Self.radius * 2, height: Self.radius * 2)
            ForEach(arcs.indices, id: \.self) { index in
                HubArc(start: arcs[index].start, end: arcs[index].end)
                    .stroke(arcs[index].colour,
                            style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .frame(width: Self.radius * 2, height: Self.radius * 2)
            }
            VStack(spacing: 2) {
                Text("\(map.runningCount)")
                    .font(.serif(46, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                chip.padding(.top, 6)
            }
            .frame(width: 132, height: 132)
            .background(Circle().fill(Theme.card))
            .overlay(Circle().stroke(Theme.border))
            .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
        }
        .frame(width: OrbitLayout.hubSide, height: OrbitLayout.hubSide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counted(map.runningCount, "session")) working, \(chipText)")
    }

    private var caption: String {
        if map.active.isEmpty { return "nothing running" }
        return map.runningCount == 1 ? "session working" : "sessions working"
    }

    private var chipText: String {
        let needs = map.waiting.count
        if needs > 0 { return "\(needs) need\(needs == 1 ? "s" : "") you" }
        let waits = map.backgroundWaitCount
        return waits > 0 ? "\(waits) waiting on a task" : "all clear"
    }

    @ViewBuilder private var chip: some View {
        if map.waiting.isEmpty {
            Text(chipText)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        } else {
            Text(chipText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.attentionText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.attention.opacity(0.16)))
        }
    }

    private var arcs: [(start: CGFloat, end: CGFloat, colour: Color)] {
        let sessions = map.active.sorted { rank($0.tone) < rank($1.tone) }
        guard !sessions.isEmpty else { return [] }
        let share = 1 / CGFloat(sessions.count)
        let gap = sessions.count > 1 ? Self.arcGap / (2 * .pi * Self.radius) : 0
        return sessions.enumerated().map { index, live in
            let start = CGFloat(index) * share
            let colour = switch live.tone {
            case .needsYou: Theme.attention
            case .waiting: Theme.dotOn.opacity(0.4)
            case .running, .idle: Theme.dotOn
            }
            return (start, start + max(share - gap, 0.002), colour)
        }
    }

    private func rank(_ tone: SessionTone) -> Int {
        switch tone {
        case .needsYou: 0
        case .running: 1
        case .waiting: 2
        case .idle: 3
        }
    }
}

// One arc of the hub's ring, given as fractions of a turn starting at the top.
private struct HubArc: Shape {
    var start: CGFloat
    var end: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: .degrees(Double(start) * 360 - 90),
                    endAngle: .degrees(Double(end) * 360 - 90),
                    clockwise: false)
        return path
    }
}

private struct OrbitProjectTile: View {
    let group: HomeWorkMap.Group

    var body: some View {
        let identity = group.identity
        SidebarIdentityTile(avatar: identity.avatar, name: identity.containerName, tint: identity.tint,
                            stacked: identity.session.workspaceID != nil, side: OrbitLayout.tileSide)
            .background {
                RoundedRectangle(cornerRadius: 19)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(Theme.hairline))
                    .padding(-6)
            }
            .accessibilityHidden(true)
    }
}

private struct OrbitSessionPill: View {
    let live: HomeLive
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var pings = 0

    var body: some View {
        let needs = live.needsAttention
        let shape = RoundedRectangle(cornerRadius: needs ? 14 : 17)
        Button(action: action) {
            HStack(spacing: 8) {
                light
                if needs {
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        Text(live.status)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.attentionText)
                    }
                } else {
                    title
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape.fill(Theme.card)
                if needs { shape.fill(Theme.attention.opacity(0.09)) }
            }
            .overlay(shape.stroke(border, lineWidth: selected ? 2 : 1))
            .shadow(color: (needs ? Theme.attention : .black).opacity(needs ? 0.22 : 0.1), radius: 8, y: 5)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay { PingRing(trigger: pings, cornerRadius: needs ? 14 : 17) }
        .onChange(of: needs) { _, now in
            if now && !reduceMotion { pings += 1 }
        }
        .accessibilityLabel("\(live.session.title), \(live.status), \(live.containerName)")
        .accessibilityHint("Shows this session's card")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: some View {
        Text(live.session.title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
    }

    // Waiting is drawn as a ring: the session is alive, but nothing is being worked on.
    @ViewBuilder private var light: some View {
        if live.tone == .waiting {
            Circle()
                .strokeBorder(Theme.dotOn, lineWidth: 1.6)
                .frame(width: 7, height: 7)
        } else {
            StateLight(tone: live.tone, size: 7)
        }
    }

    private var border: Color {
        if selected { return Theme.accent }
        if live.needsAttention { return Theme.attention.opacity(0.55) }
        return hovering ? Theme.accent.opacity(0.45) : Theme.border
    }
}

// A single ring that swells and fades when a session starts asking for something. It
// plays once per request rather than looping, so it marks the moment without nagging.
private struct PingRing: View {
    let trigger: Int
    let cornerRadius: CGFloat

    private struct Frame {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + 6)
            .stroke(Theme.attention, lineWidth: 2)
            .padding(-6)
            .keyframeAnimator(initialValue: Frame(), trigger: trigger) { ring, frame in
                ring.scaleEffect(frame.scale).opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.96)
                    CubicKeyframe(1.18, duration: 1.1)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0.9)
                    LinearKeyframe(0, duration: 1.1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// What opens beside a session on the orbit map: what it is doing or asking, and the
// buttons to answer it from here.
private struct OrbitSessionCard: View {
    let live: HomeLive
    let hasChanges: Bool
    let open: (SessionDestination) -> Void
    let answer: (PermissionAnswer) -> Void

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ProjectDot(tint: live.tint, size: 7)
                Text(live.containerName.uppercased())
                    .font(.mono(10.5))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(live.session.agent.title)
                    .font(.mono(10.5))
                    .foregroundStyle(.tertiary)
            }
            Text(live.session.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            request
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.sunken))
                .padding(.top, 10)
            actions.padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width, alignment: .leading)
        .floatingCard(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(live.session.title)
    }

    private var statusLine: String {
        guard let permission = live.permission else { return live.status }
        return "\(live.status) for \(RelativeTime.duration(since: permission.askedAt))"
    }

    @ViewBuilder private var request: some View {
        if let permission = live.permission {
            if let question = permission.questions.first {
                Text(question.text).lineLimit(4)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(permission.title).foregroundStyle(.secondary)
                    Text(permission.subjectIsMarkdown
                         ? permission.subject.components(separatedBy: .newlines).first ?? ""
                         : permission.subject)
                        .font(.mono(11.5))
                        .lineLimit(3)
                }
            }
        } else if live.finished {
            let summary = live.session.summary
            HStack(spacing: 6) {
                Text("Finished.")
                if summary.added > 0 || summary.removed > 0 {
                    DiffPair(added: summary.added, removed: summary.removed, size: 11, spacing: 4)
                }
            }
        } else {
            Text(live.activity).lineLimit(2)
        }
    }

    @ViewBuilder private var actions: some View {
        let quick = live.quickAnswers
        let primary = live.primaryAction(hasChanges: hasChanges)
        HStack(spacing: 6) {
            if !quick.isEmpty {
                ForEach(quick.indices, id: \.self) { index in
                    ActionButton(title: quick[index].title, tone: index == 0 ? .green : .outlined,
                                 height: 26, size: 12) { answer(quick[index].answer) }
                }
                Spacer(minLength: 4)
                InlineLink(title: "Open session") { open(live.destination) }
            } else if live.needsAttention {
                ActionButton(title: primary.title, tone: .green, height: 26, size: 12) {
                    open(primary.destination)
                }
                Spacer(minLength: 4)
                if primary.destination != live.destination {
                    InlineLink(title: "Open session") { open(live.destination) }
                }
            } else {
                ActionButton(title: primary.title, tone: .outlined, height: 26, size: 12) {
                    open(primary.destination)
                }
                Spacer(minLength: 4)
                Text(RelativeTime.short(live.session.lastActivity))
                    .font(.mono(10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
