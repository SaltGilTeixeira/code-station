import SwiftUI

// Where every shape on the orbit map sits. Worked out from the map and the width alone, so
// it can be checked without drawing anything.
//
// Projects take a left and a right column so their sessions always have room to reach
// outward, away from the hub. The map is only as tall as its busiest column, and a column
// grows the map rather than squeezing its rows, so sessions are never laid over each other.
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
        let group: HomeWorkMap.Group
        let count: Int
        let frame: CGRect
        var id: UUID { group.id }
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

    static let hubSide: CGFloat = 136
    static let tileSide: CGFloat = 40
    static let pillHeight: CGFloat = 32
    static let tallPillHeight: CGFloat = 44
    static let pillGap: CGFloat = 7
    static let shownPerProject = 2
    static let maxProjects = 5
    static let maxSessions = 10
    // A narrower map leaves the session pills too short to read a title in.
    static let minWidth: CGFloat = 860
    // A tile sits this far above the middle of its row, so the name under it stays inside
    // the row.
    static let tileLift: CGFloat = 8
    // Room for the hub, so a map with one project in each column still holds it.
    static let minHeight: CGFloat = hubSide + 2 * margin + 20

    // How much height a project takes when it has a single session: the tile, its halo and
    // the name under it.
    private static let nodeExtent: CGFloat = 74
    private static let margin: CGFloat = 14
    private static let rowGap: CGFloat = 18
    private static let pillReach: CGFloat = 46
    // The name under a tile stops short of the pills beside it.
    static let nameWidth: CGFloat = 2 * pillReach - 8

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

        let columnHeights = columns.map { column, _ in
            column.map(extent).reduce(0, +) + Self.rowGap * CGFloat(max(column.count - 1, 0))
        }
        let height = max(Self.minHeight, (columnHeights.max() ?? 0) + 2 * Self.margin)
        size = CGSize(width: width, height: height)
        let centerX = width / 2
        let centerY = height / 2
        hub = CGPoint(x: centerX, y: centerY)

        let reach = min(250, max(176, width * 0.2))
        pillWidth = min(250, centerX - reach - Self.pillReach - 30)
        let tileEdge = Self.tileSide / 2 + 7

        for (index, (column, left)) in columns.enumerated() {
            var top = centerY - columnHeights[index] / 2
            for group in column {
                let rowHeight = extent(group)
                let y = top + rowHeight / 2
                // Rows further from the middle bend in towards the hub, which is what turns
                // two columns into an orbit.
                let bend = min(abs(y - centerY), 160) * 0.32
                let x = left ? centerX - reach + bend : centerX + reach - bend
                let tile = CGPoint(x: x, y: y - Self.tileLift)
                nodes.append(Node(group: group, center: tile, left: left))

                wires.append(Wire(id: "hub:\(group.id)",
                                  start: CGPoint(x: centerX + (left ? -1 : 1) * Self.hubSide / 2,
                                                 y: centerY),
                                  end: CGPoint(x: x + (left ? 1 : -1) * tileEdge, y: tile.y),
                                  kind: Self.kind(of: group.sessions), trunk: true))

                let (shown, hidden, stackHeight) = stack(group)
                let pillX = left ? x - Self.pillReach - pillWidth : x + Self.pillReach
                var pillY = y - stackHeight / 2
                for live in shown {
                    let frame = CGRect(x: pillX, y: pillY, width: pillWidth, height: Self.height(of: live))
                    pills.append(Pill(live: live, frame: frame))
                    wires.append(Wire(id: "session:\(live.id)",
                                      start: CGPoint(x: x + (left ? -1 : 1) * tileEdge, y: tile.y),
                                      end: CGPoint(x: left ? frame.maxX : frame.minX, y: frame.midY),
                                      kind: Self.kind(of: [live]), trunk: false))
                    pillY = frame.maxY + Self.pillGap
                }
                if hidden > 0 {
                    more.append(More(group: group, count: hidden,
                                     frame: CGRect(x: pillX, y: pillY, width: pillWidth,
                                                   height: Self.pillHeight)))
                }
                top += rowHeight + Self.rowGap
            }
        }
    }

    // A session that needs you is the one tall shape on the map, so it is found first.
    static func height(of live: HomeLive) -> CGFloat {
        live.needsAttention ? tallPillHeight : pillHeight
    }

    // A wire takes the state of the busiest thing it leads to.
    static func kind(of sessions: [HomeLive]) -> Wire.Kind {
        sessions.contains(where: \.needsAttention) ? .attention
            : sessions.contains(where: { $0.tone == .running }) ? .running : .quiet
    }
}

// Where everything sits on the rail, the map for a short list: the hub on the left, each
// project's tile beside it, and a row for every session that runs to the edge of the card,
// so a handful of sessions use the width instead of leaving it empty.
struct RailLayout {
    static let hubSide: CGFloat = 112
    static let rowHeight: CGFloat = 50
    static let tallRowHeight: CGFloat = 56
    static let maxProjects = 2
    static let maxSessions = 4
    // Below this a row is too short to hold its title next to its buttons.
    static let minWidth: CGFloat = 600
    static let nameWidth: CGFloat = 120

    private static let rowGap: CGFloat = 8
    private static let groupGap: CGFloat = 16
    private static let tileExtent: CGFloat = 80

    let size: CGSize
    let hub: CGPoint
    private(set) var nodes: [OrbitLayout.Node] = []
    private(set) var rows: [OrbitLayout.Pill] = []
    private(set) var wires: [OrbitLayout.Wire] = []

    var motionKey: [CGRect] {
        nodes.map { CGRect(origin: $0.center, size: .zero) } + rows.map(\.frame)
    }

    init(map: HomeWorkMap, width: CGFloat) {
        let blocks = map.groups.map { group in
            let heights = group.sessions.map(Self.height(of:))
            let stack = heights.reduce(0, +) + Self.rowGap * CGFloat(heights.count - 1)
            return (group: group, heights: heights, stack: stack, extent: max(Self.tileExtent, stack))
        }
        let content = blocks.map(\.extent).reduce(0, +) + Self.groupGap * CGFloat(max(blocks.count - 1, 0))
        let height = max(Self.hubSide + 12, content)
        size = CGSize(width: width, height: height)
        let centerY = height / 2
        hub = CGPoint(x: Self.hubSide / 2 + 4, y: centerY)

        let tileX = Self.hubSide + 108
        let tileEdge = OrbitLayout.tileSide / 2 + 7
        let rowX = tileX + OrbitLayout.tileSide / 2 + 50
        var top = centerY - content / 2
        for block in blocks {
            // A tile taller than its rows is lifted, so the name under it stays in the block.
            let y = top + block.extent / 2 - (block.extent > block.stack ? OrbitLayout.tileLift : 0)
            nodes.append(OrbitLayout.Node(group: block.group, center: CGPoint(x: tileX, y: y), left: false))
            wires.append(OrbitLayout.Wire(id: "hub:\(block.group.id)",
                                          start: CGPoint(x: hub.x + Self.hubSide / 2, y: centerY),
                                          end: CGPoint(x: tileX - tileEdge, y: y),
                                          kind: OrbitLayout.kind(of: block.group.sessions), trunk: true))
            var rowY = y - block.stack / 2
            for (live, rowHeight) in zip(block.group.sessions, block.heights) {
                let frame = CGRect(x: rowX, y: rowY, width: width - rowX, height: rowHeight)
                rows.append(OrbitLayout.Pill(live: live, frame: frame))
                wires.append(OrbitLayout.Wire(id: "session:\(live.id)",
                                              start: CGPoint(x: tileX + tileEdge, y: y),
                                              end: CGPoint(x: frame.minX, y: frame.midY),
                                              kind: OrbitLayout.kind(of: [live]), trunk: false))
                rowY = frame.maxY + Self.rowGap
            }
            top += block.extent + Self.groupGap
        }
    }

    static func height(of live: HomeLive) -> CGFloat {
        live.needsAttention ? tallRowHeight : rowHeight
    }
}

// The rail drawn: the hub, a tile for each project, and a row for each session with its
// buttons on it, so a request is answered right there.
struct RailMap: View {
    let map: HomeWorkMap
    let width: CGFloat
    let hasChanges: (HomeLive) -> Bool
    let open: (HomeLive, SessionDestination) -> Void
    let answer: (HomeLive, PermissionAnswer) -> Void

    var body: some View {
        let layout = RailLayout(map: map, width: width)
        ZStack(alignment: .topLeading) {
            OrbitWires(wires: layout.wires)

            OrbitHub(map: map, side: RailLayout.hubSide, ringWidth: 6, numberSize: 30)
                .position(layout.hub)

            ForEach(layout.nodes) { node in
                OrbitProjectTile(group: node.group)
                    .position(node.center)
                OrbitTileName(name: node.group.identity.containerName, width: RailLayout.nameWidth)
                    .position(x: node.center.x, y: node.center.y + OrbitTileName.offset)
            }

            ForEach(layout.rows) { row in
                let live = row.live
                HomeMapActionRow(live: live, hasChanges: hasChanges(live),
                                 open: { open(live, $0) }, answer: { answer(live, $0) })
                    .frame(width: row.frame.width, height: row.frame.height)
                    .position(x: row.frame.midX, y: row.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .motion(HomeWorkMapView.reflow, value: layout.motionKey)
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
    let reveal: (HomeWorkMap.Group) -> Void

    @State private var selected: UUID?
    @State private var cardHeight: CGFloat = 190

    var body: some View {
        let layout = OrbitLayout(map: map, width: width)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }

            // Two faint orbits, sized from the map so they keep its shape at any height.
            Group {
                Ellipse()
                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 380, height: min(220, layout.size.height - 28))
                Ellipse()
                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: min(760, width - 40), height: layout.size.height - 8)
            }
            .position(layout.hub)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            OrbitWires(wires: layout.wires)

            OrbitHub(map: map)
                .position(layout.hub)

            ForEach(layout.nodes) { node in
                OrbitProjectTile(group: node.group)
                    .position(node.center)
                OrbitTileName(name: node.group.identity.containerName, width: OrbitLayout.nameWidth)
                    .position(x: node.center.x, y: node.center.y + OrbitTileName.offset)
            }

            ForEach(layout.pills) { pill in
                OrbitSessionPill(live: pill.live, selected: selected == pill.id) {
                    selected = selected == pill.id ? nil : pill.id
                }
                .frame(width: pill.frame.width, height: pill.frame.height)
                .position(x: pill.frame.midX, y: pill.frame.midY)
            }

            ForEach(layout.more) { more in
                OrbitMoreChip(more: more) { reveal(more.group) }
                    .frame(width: more.frame.width, height: more.frame.height)
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

    // Under the session when it fits, above it when it would run off the bottom. The map
    // can be shorter than the card, so the card may hang over the card's own padding and
    // heading, but never past them.
    private func card(for pill: OrbitLayout.Pill, in layout: OrbitLayout) -> some View {
        let half = OrbitSessionCard.width / 2
        let x = min(max(pill.frame.midX, half + 10), layout.size.width - half - 10)
        let lowest = layout.size.height + 14
        let highest: CGFloat = -30
        let below = pill.frame.maxY + 10 + cardHeight <= lowest
        let top = below ? pill.frame.maxY + 10 : pill.frame.minY - 10 - cardHeight
        let y = max(min(top, lowest - cardHeight), highest) + cardHeight / 2
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
            .position(x: x, y: y)
            .zIndex(2)
            .transition(.opacity)
    }
}

private struct OrbitTileName: View {
    let name: String
    let width: CGFloat

    // From the middle of a tile to the middle of the name under it.
    static let offset: CGFloat = OrbitLayout.tileSide / 2 + 18

    var body: some View {
        Text(name)
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
            .frame(width: width)
    }
}

// The sessions a project has past the ones the orbit shows. Clicking it opens the project
// in the sidebar, where every session is listed.
private struct OrbitMoreChip: View {
    let more: OrbitLayout.More
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let name = more.group.identity.containerName
        Button(action: action) {
            Text("+\(more.count) more in \(name)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .cardSurface(cornerRadius: OrbitLayout.pillHeight / 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityHint("Shows \(name) in the sidebar")
    }
}


// The lines from the hub to each project and on to its sessions. A line flows while what
// it leads to is running, and stands still otherwise, so motion on the map always means
// work is happening. The flow is played by Core Animation, so a map full of running work
// costs nothing between frames.
private struct OrbitWires: View {
    let wires: [OrbitLayout.Wire]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let flowing = reduceMotion ? [] : wires.filter { $0.kind == .running }
        ZStack {
            ForEach(wires.filter { reduceMotion || $0.kind != .running }) { wire in
                MapConnector(start: wire.start, end: wire.end)
                    .stroke(Self.colour(wire.kind), style: Self.style(wire))
            }
            if !flowing.isEmpty {
                FlowingWires(wires: flowing, colour: Self.colour(.running))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func colour(_ kind: OrbitLayout.Wire.Kind) -> Color {
        switch kind {
        case .attention: Theme.attention.opacity(0.7)
        case .running: Theme.accent.opacity(0.4)
        case .quiet: Theme.accent.opacity(0.22)
        }
    }

    static func width(_ wire: OrbitLayout.Wire) -> CGFloat { wire.trunk ? 1.6 : 1.2 }

    static func style(_ wire: OrbitLayout.Wire) -> StrokeStyle {
        let width = width(wire)
        return switch wire.kind {
        case .attention: StrokeStyle(lineWidth: width)
        case .running: StrokeStyle(lineWidth: width, lineCap: .round, dash: FlowingWiresView.dash)
        case .quiet: StrokeStyle(lineWidth: width, dash: [2, 4])
        }
    }
}

private struct FlowingWires: NSViewRepresentable {
    let wires: [OrbitLayout.Wire]
    let colour: Color

    func makeNSView(context: Context) -> FlowingWiresView { FlowingWiresView() }

    func updateNSView(_ view: FlowingWiresView, context: Context) {
        let paths = Dictionary(grouping: wires, by: OrbitWires.width).mapValues { group in
            let path = CGMutablePath()
            for wire in group {
                path.addPath(MapConnector(start: wire.start, end: wire.end).path(in: .zero).cgPath)
            }
            return path as CGPath
        }
        view.update(paths: paths, colour: colour.resolve(in: context.environment).cgColor)
    }
}

final class FlowingWiresView: LoopLayerView {
    static let dash: [CGFloat] = [2, 6]
    private static let flowPeriod: TimeInterval = 0.48

    // One layer for each line width, since a layer strokes every line it holds the same.
    private var lines: [CGFloat: CAShapeLayer] = [:]

    func update(paths: [CGFloat: CGPath], colour: CGColor) {
        LayerLoop.still {
            for (width, line) in lines where paths[width] == nil {
                line.removeFromSuperlayer()
                lines[width] = nil
            }
            for (width, path) in paths {
                let line = lines[width] ?? addLine(width: width)
                line.path = path
                line.strokeColor = colour
            }
        }
    }

    override func layoutLayers() {
        lines.values.forEach { $0.frame = bounds }
    }

    override func restartLoops() {
        lines.values.forEach(flow)
    }

    private func addLine(width: CGFloat) -> CAShapeLayer {
        let line = CAShapeLayer()
        line.fillColor = nil
        line.lineWidth = width
        line.lineCap = .round
        line.lineDashPattern = Self.dash.map { NSNumber(value: Double($0)) }
        line.frame = bounds
        line.contentsScale = window?.backingScaleFactor ?? 2
        layer?.addSublayer(line)
        lines[width] = line
        flow(line)
        return line
    }

    // The dashes travel one whole pattern each period, out from the hub.
    private func flow(_ line: CAShapeLayer) {
        let flow = CABasicAnimation(keyPath: "lineDashPhase")
        flow.fromValue = 0
        flow.toValue = -Self.dash.reduce(0, +)
        flow.duration = Self.flowPeriod
        line.add(LayerLoop.repeating(flow, period: Self.flowPeriod), forKey: "flow")
    }
}

// The middle of the map. The ring has one arc for every session, in the colour of its
// state, so the overall picture reads before any label does. Smaller hubs drop the
// caption and then the chip, keeping the count.
struct OrbitHub: View {
    let map: HomeWorkMap
    var side: CGFloat = OrbitLayout.hubSide
    var ringWidth: CGFloat = 7
    var numberSize: CGFloat = 38

    // The space left between two arcs, measured along the ring.
    private static let arcGap: CGFloat = 7

    private var radius: CGFloat { side / 2 - ringWidth / 2 - 2 }

    var body: some View {
        let arcs = arcs
        let core = side - 2 * ringWidth - 14
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: ringWidth)
                .frame(width: radius * 2, height: radius * 2)
            ForEach(arcs.indices, id: \.self) { index in
                HubArc(start: arcs[index].start, end: arcs[index].end)
                    .stroke(arcs[index].colour,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
            }
            VStack(spacing: 2) {
                Text("\(map.runningCount)")
                    .font(.serif(numberSize, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                if side >= 120 {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                if side >= 100 {
                    chip.padding(.top, 3)
                }
            }
            .frame(width: core, height: core)
            .background(Circle().fill(Theme.card))
            .overlay(Circle().stroke(Theme.border))
            .shadow(color: .black.opacity(0.09), radius: 9, y: 8)
        }
        .frame(width: side, height: side)
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
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        } else {
            Text(chipText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.attentionText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.attention.opacity(0.16)))
        }
    }

    private var arcs: [(start: CGFloat, end: CGFloat, colour: Color)] {
        let sessions = map.active.sorted { rank($0.tone) < rank($1.tone) }
        guard !sessions.isEmpty else { return [] }
        let share = 1 / CGFloat(sessions.count)
        let gap = sessions.count > 1 ? Self.arcGap / (2 * .pi * radius) : 0
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
        let shape = RoundedRectangle(cornerRadius: needs ? 13 : 16)
        Button(action: action) {
            HStack(spacing: 8) {
                MapLight(tone: live.tone)
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
        .overlay { PingRing(trigger: pings, cornerRadius: needs ? 13 : 16) }
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

    private var border: Color {
        if selected { return Theme.accent }
        if live.needsAttention { return Theme.attention.opacity(0.55) }
        return hovering ? Theme.accent.opacity(0.45) : Theme.border
    }
}

// The light beside a session on the map. Waiting is drawn as a ring: the session is
// alive, but nothing is being worked on.
struct MapLight: View {
    let tone: SessionTone

    var body: some View {
        if tone == .waiting {
            Circle()
                .strokeBorder(Theme.dotOn, lineWidth: 1.6)
                .frame(width: 7, height: 7)
        } else {
            StateLight(tone: tone, size: 7)
        }
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
