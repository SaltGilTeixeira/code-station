import SwiftUI

// A rolling day of summed session activity. Each bar opens the sessions behind it, and
// resting on one shows which projects filled it.
struct DayRibbonSection: View {
    let ribbon: DayRibbon
    // Whether every session in the window has been read off disk yet. Without it the
    // chart claims an empty day for the moment between opening Home and the first scan
    // landing, which is the one moment the claim is most likely to be wrong.
    let scanned: Bool
    let onOpen: (UUID) -> Void

    @Environment(TooltipPresenter.self) private var tooltips

    // One owner for every bar, so moving between bars hands the card along instead of
    // closing one and waiting to open the next.
    @State private var cardOwner = UUID()
    @State private var shownBar: Int?
    @State private var hoveredBar: Int?
    @State private var pendingShow: Task<Void, Never>?
    @State private var pendingHide: Task<Void, Never>?
    @State private var trackAnchor = FrameAnchor()
    @State private var sectionAnchor = FrameAnchor()

    private static let bandHeight: CGFloat = 54
    private static let barSpacing: CGFloat = 3
    private static let cardWidth: CGFloat = 290
    // Crossing the gap between two bars ends one hover just before the next begins, so
    // the card waits this long before going, in case the pointer is only passing over.
    private static let hideGrace = Duration.milliseconds(140)

    private var peeking: Bool { tooltips.isShowing(owner: cardOwner) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title.fixedSize()
                    Spacer()
                    headline.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    title
                    headline
                }
            }
            chart
        }
        .background(FrameAnchorView(anchor: sectionAnchor))
        .onDisappear {
            pendingShow?.cancel()
            pendingHide?.cancel()
            tooltips.hide(owner: cardOwner, immediately: true)
        }
    }

    private var title: some View {
        Text("Your day, at a glance")
            .font(.serif(20))
            .accessibilityAddTraits(.isHeader)
    }

    private var headline: some View {
        (Text(scanned ? DayRibbon.duration(ribbon.spent) : "Counting session time…")
            .font(.mono(11.5, .semibold))
            .foregroundStyle(Color.primary)
            + Text(verbatim: scanned ? " of session time in the last 24 hours" : "")
            .font(.mono(11))
            .foregroundStyle(.tertiary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 0) {
            track
            if scanned && ribbon.isEmpty {
                emptyNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 11)
    }

    // MARK: - Band

    private var track: some View {
        GeometryReader { geometry in
            let count = max(1, min(64, Int(geometry.size.width / 7)))
            let activity = ribbon.activity(bucketCount: count)
            let peak = max(activity.map(\.spent).max() ?? 0, 1)
            let barWidth = (geometry.size.width - Self.barSpacing * Double(count - 1)) / Double(count)
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(Array(activity.enumerated()), id: \.offset) { index, bucket in
                    let fraction = scanned ? bucket.spent / peak : 0
                    let height = max(4, Self.bandHeight * fraction)
                    let live = scanned && bucket.spent > 0
                    let face = RibbonBar(bucket: bucket,
                                         height: height,
                                         opacity: live ? 0.55 + fraction * 0.3 : 0.22,
                                         dimmed: peeking && shownBar != index,
                                         stacked: peeking && shownBar == index)
                    if live {
                        let place = BarPlace(index: index, bucket: bucket,
                                             x: Double(index) * (barWidth + Self.barSpacing),
                                             width: barWidth)
                        face
                            .onFocusChange { focused in focus(place, focused) }
                            .appMenu {
                                [.searchable(bucket.sessions.map { block in
                                    MenuItem(label: block.title, projectTint: block.subject.tint,
                                             subtitle: block.subject.name,
                                             handler: { onOpen(block.sessionID) })
                                }, prompt: "Find a session", noResults: "No sessions match your search.")]
                            }
                            .onPointerHover { inside in hover(place, inside) }
                            .accessibilityLabel(activityLabel(bucket))
                            .accessibilityHint("Shows sessions active during this time")
                    } else {
                        face.accessibilityHidden(true)
                    }
                }
            }
            .background(FrameAnchorView(anchor: trackAnchor))
        }
        .frame(height: Self.bandHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scanned
            ? "Session activity over the last 24 hours. Taller bars mean more session time."
            : "Counting session activity")
    }

    private func activityLabel(_ bucket: DayRibbon.Activity) -> String {
        let start = bucket.interval.start.formatted(date: .omitted, time: .shortened)
        let end = bucket.interval.end.formatted(date: .omitted, time: .shortened)
        let projects = bucket.projects
            .map { "\($0.subject.name) \(DayRibbon.duration($0.spent))" }
            .joined(separator: ", ")
        return "\(start) to \(end), \(DayRibbon.duration(bucket.spent)): \(projects)"
    }

    private var emptyNote: some View {
        Text("No sessions ran in the last 24 hours")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.top, 13)
    }

    // MARK: - Card

    private struct BarPlace {
        let index: Int
        let bucket: DayRibbon.Activity
        let x: CGFloat
        let width: CGFloat
    }

    private func hover(_ place: BarPlace, _ inside: Bool) {
        pendingShow?.cancel()
        if inside {
            hoveredBar = place.index
            pendingHide?.cancel()
            if peeking {
                showCard(place)
                return
            }
            pendingShow = Task {
                try? await Task.sleep(for: TooltipPresenter.hoverDelay)
                guard !Task.isCancelled else { return }
                showCard(place)
            }
        } else if hoveredBar == place.index {
            hoveredBar = nil
            hideCard()
        }
    }

    // A keyboard user has no pointer to rest, so focus shows the card straight away.
    private func focus(_ place: BarPlace, _ focused: Bool) {
        if focused {
            pendingShow?.cancel()
            pendingHide?.cancel()
            showCard(place)
        } else if hoveredBar == nil && shownBar == place.index {
            hideCard()
        }
    }

    private func hideCard() {
        pendingHide?.cancel()
        pendingHide = Task {
            try? await Task.sleep(for: Self.hideGrace)
            guard !Task.isCancelled else { return }
            tooltips.hide(owner: cardOwner, immediately: true)
        }
    }

    private func showCard(_ place: BarPlace) {
        guard let track = trackAnchor.frame(), let section = sectionAnchor.frame() else { return }
        let bar = CGRect(x: track.minX + place.x, y: track.minY,
                         width: place.width, height: track.height)
        shownBar = place.index
        tooltips.show(Tooltip(title: "",
                              hanging: Tooltip.Hanging(
                                  width: Self.cardWidth,
                                  edges: section.minX...max(section.maxX, section.minX + Self.cardWidth),
                                  content: AnyView(RibbonCard(bucket: place.bucket)))),
                      from: bar, owner: cardOwner)
    }
}

// MARK: - Bar

private struct RibbonBar: View {
    let bucket: DayRibbon.Activity
    let height: CGFloat
    let opacity: Double
    let dimmed: Bool
    // While its card is up the bar shows its own project mix, biggest at the bottom.
    let stacked: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .fill(Theme.accent.opacity(opacity))
                .opacity(stacked ? 0 : 1)
            VStack(spacing: 0) {
                ForEach(bucket.projects.reversed()) { share in
                    Rectangle()
                        .fill(share.subject.tint.colour)
                        .frame(height: height * share.spent / max(bucket.spent, 1))
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            .opacity(stacked ? 1 : 0)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(dimmed ? 0.3 : 1)
        .motion(Motion.reveal, value: dimmed)
        .motion(Motion.reveal, value: stacked)
        .contentShape(Rectangle())
    }

    // The bar sits inside the menu button, so it learns of the button's focus from the
    // environment the button sets.
    func onFocusChange(_ handler: @escaping (Bool) -> Void) -> some View {
        FocusReader(handler: handler) { self }
    }
}

private struct FocusReader<Content: View>: View {
    let handler: (Bool) -> Void
    @ViewBuilder let content: Content

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content.onChange(of: isFocused) { _, focused in handler(focused) }
    }
}

// What a time slot held: when it was, how long, and the projects that filled it.
private struct RibbonCard: View {
    let bucket: DayRibbon.Activity

    private static let maxRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(clock(bucket.interval.start)) - \(clock(bucket.interval.end))")
                        .font(.serif(15))
                    Text(verbatim: "\(day) · \(counted(bucket.projects.count, "project"))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(DayRibbon.duration(bucket.spent))
                    .font(.mono(13, .semibold))
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 10)

            mix
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(bucket.projects.prefix(Self.maxRows)) { share in
                    HStack(spacing: 9) {
                        ProjectTileView(name: share.subject.name, tint: share.subject.tint, side: 22)
                        Text(share.subject.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(DayRibbon.duration(share.spent))
                            .font(.mono(10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                let rest = bucket.projects.count - Self.maxRows
                if rest > 0 {
                    Text(verbatim: "and \(rest) more")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 39)
                        .padding(.trailing, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("Click to open one of these sessions")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 9)
        }
    }

    private var mix: some View {
        GeometryReader { geometry in
            let gaps = Double(max(0, bucket.projects.count - 1))
            let width = max(0, geometry.size.width - gaps)
            HStack(spacing: 1) {
                ForEach(bucket.projects) { share in
                    Rectangle()
                        .fill(share.subject.tint.colour)
                        .frame(width: width * share.spent / max(bucket.spent, 1))
                }
            }
        }
        .frame(height: 6)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var day: String {
        Calendar.current.isDateInToday(bucket.interval.start) ? "Today" : "Yesterday"
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
