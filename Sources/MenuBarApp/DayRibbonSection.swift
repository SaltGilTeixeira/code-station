import SwiftUI

// A rolling day of summed session activity, with project totals and session access.
struct DayRibbonSection: View {
    let ribbon: DayRibbon
    // Whether every session in the window has been read off disk yet. Without it the
    // chart claims an empty day for the moment between opening Home and the first scan
    // landing, which is the one moment the claim is most likely to be wrong.
    let scanned: Bool
    let onOpen: (UUID) -> Void

    // Nil shows every project; a selected chip narrows the bars to that project.
    @State private var focused: String?

    private static let bandHeight: CGFloat = 54

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
            Text("Last 24 hours · Summed session time, including parallel work")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .onChange(of: ribbon.legend.map(\.id)) { _, subjects in
            if let focused, !subjects.contains(focused) { self.focused = nil }
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
            + Text(verbatim: scanned ? " of session time · \(counted(ribbon.legend.count, "project"))" : "")
            .font(.mono(11))
            .foregroundStyle(.tertiary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 0) {
            band
            if scanned && !ribbon.isEmpty {
                legend
            } else if scanned {
                emptyNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 11)
    }

    // MARK: - Band

    private var band: some View {
        VStack(alignment: .leading, spacing: 6) {
            track
            RibbonAxis(axis: ribbon.axis)
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let count = max(1, min(64, Int(geometry.size.width / 7)))
            let activity = ribbon.activity(bucketCount: count, subject: focused)
            let peak = max(activity.map(\.spent).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(activity) { bucket in
                    let fraction = scanned ? bucket.spent / peak : 0
                    let bar = UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(Theme.accent.opacity(scanned && bucket.spent > 0 ? 0.55 + fraction * 0.3 : 0.22))
                        .frame(height: max(4, Self.bandHeight * fraction))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                    if scanned && bucket.spent > 0 {
                        bar
                            .appMenu {
                                [.searchable(bucket.sessions.map { block in
                                    MenuItem(label: block.title, projectTint: block.subject.tint,
                                             subtitle: block.subject.name,
                                             handler: { onOpen(block.sessionID) })
                                }, prompt: "Find a session", noResults: "No sessions match your search.")]
                            }
                            .appTooltip(activityLabel(bucket))
                            .accessibilityLabel(activityLabel(bucket))
                            .accessibilityHint("Shows sessions active during this time")
                    } else {
                        bar.accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(height: Self.bandHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scanned
            ? "Session activity over the last 24 hours. Taller bars mean more session time."
            : "Counting session activity")
    }

    private func activityLabel(_ bucket: DayRibbon.Activity) -> String {
        let start = bucket.interval.start.formatted(date: .abbreviated, time: .shortened)
        let end = bucket.interval.end.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end), \(DayRibbon.duration(bucket.spent)) of session time, "
            + counted(bucket.sessions.count, "session")
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 13) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            FlowRow(spacing: 6) {
                ForEach(ribbon.legend) { total in
                    RibbonChip(total: total,
                               dimmed: dimmed(total.subject.name),
                               focus: { focus(total.subject.name) })
                }
            }
        }
        .padding(.top, 13)
    }

    private var emptyNote: some View {
        Text("No sessions ran in the last 24 hours")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.top, 13)
    }

    // MARK: - Focus

    private func dimmed(_ name: String) -> Bool {
        guard let focused else { return false }
        return focused != name
    }

    private func focus(_ name: String) {
        focused = focused == name ? nil : name
    }
}

// MARK: - Legend chip

private struct RibbonChip: View {
    let total: DayRibbon.Total
    let dimmed: Bool
    let focus: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: focus) {
            HStack(spacing: 7) {
                ProjectDot(tint: total.subject.tint, size: 8)
                Text(total.subject.name)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Text(DayRibbon.duration(total.spent))
                    .font(.mono(10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .surface(hovering ? Theme.field : .clear, cornerRadius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.35 : 1)
        .hoverLift(hovering)
        .onHover { hovering = $0 }
        .motion(Motion.hover, value: hovering)
        .motion(Motion.reveal, value: dimmed)
        .accessibilityLabel("\(total.subject.name), \(DayRibbon.duration(total.spent))")
        .accessibilityValue(dimmed ? "Not selected" : "Shown")
        .accessibilityHint("Toggles the project filter for the activity bars")
    }
}

// MARK: - Axis

private struct RibbonAxis: View {
    let axis: DateInterval

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let divisions = width >= 650 ? 6 : 3
            ZStack(alignment: .topLeading) {
                Text(axis.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(1..<divisions, id: \.self) { index in
                    let position = width * Double(index) / Double(divisions)
                    let date = axis.start.addingTimeInterval(axis.duration * Double(index) / Double(divisions))
                    if position > 145 && position < width - 55 {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .frame(width: 72)
                            .offset(x: position - 36)
                    }
                }
                Text("Now")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(height: 15)
        .accessibilityHidden(true)
    }
}
