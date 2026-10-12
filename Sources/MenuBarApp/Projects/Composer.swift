import AppKit
import QuartzCore
import SwiftUI

// The prompt box under a transcript: what has been dropped or pasted onto it, the field
// itself, and the button that sends, queues or stops. The Chat and Design panes both
// draw it, and differ only in the words in the field, what sits at its end, and what
// they put on the rows above it.
//
// The half-written prompt is the runner's, not this view's: switching sessions builds
// the pane again from nothing, and anything held here would go with it.
struct Composer<Above: View, Accessory: View>: View {
    @Environment(ProjectStore.self) private var store
    @Environment(SessionRunner.self) private var runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sessionID: UUID
    // Which CLI the prompt is bound for: only Claude's reads a thinking keyword out of it.
    let agent: AgentKind
    // Whether the session can run at all: its folder is there and its CLI is installed.
    let blocked: Bool
    @Binding var isFocused: Bool
    let placeholder: String
    // The side margin, which the narrow Design pane keeps smaller.
    var inset: CGFloat = 20
    var minimumLines: Int = 1
    let onOversizedPaste: (String) -> Void
    var onRecallUp: (() -> Bool)? = nil
    var onRecallDown: (() -> Bool)? = nil
    var onSend: (() -> Void)? = nil
    // Passed to the field so the keys the suggestion above answers are only taken while
    // the cursor is in the box.
    var onSuggestionKey: ((SuggestionKey) -> Bool)? = nil
    @ViewBuilder let above: Above
    @ViewBuilder let accessory: Accessory

    @State private var dropTargeted = false
    @State private var commands: [AgentCommand] = []
    @State private var commandSelection = 0
    // The command being typed when the menu was waved away, so it stays away until the
    // word changes rather than coming back on the next keystroke.
    @State private var dismissedQuery: String?

    private var attachments: [Attachment] { runner.draft(sessionID).attachments }

    // The slash command being typed, if the whole of the prompt is one.
    private var query: String? { SlashQuery.typed(in: runner.draft(sessionID).text) }

    private var matches: [AgentCommand] {
        guard let query, query != dismissedQuery else { return [] }
        return SlashQuery.matches(query, in: commands)
    }

    private var draft: Binding<String> {
        Binding(get: { runner.draft(sessionID).text },
                set: { text in runner.editDraft(sessionID) { $0.text = text } })
    }

    var body: some View {
        let state = runner.state(sessionID)
        let busy = state.isBusy
        let canSend = !blocked && !runner.draft(sessionID).isEmpty
        let roots = store.session(sessionID).map(store.workingDirectories(for:)) ?? []

        let matches = matches

        VStack(alignment: .leading, spacing: 8) {
            above
            attachmentStrip

            if !matches.isEmpty, isFocused, !blocked {
                SlashCommandMenu(agent: agent,
                                 commands: matches,
                                 selected: min(commandSelection, matches.count - 1),
                                 choose: take,
                                 highlight: { commandSelection = $0 })
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Typing during a turn is allowed: what is written goes to the back of the
                // queue instead of waiting for the agent to be free. A turn parked on a
                // background task is the one case where it does not queue at all - the
                // pipe is open, so it goes straight to the agent.
                ComposerField(text: draft,
                              isFocused: $isFocused,
                              placeholder: placeholder,
                              isEnabled: !blocked,
                              onSubmit: send,
                              onOversizedPaste: onOversizedPaste,
                              onRecallUp: onRecallUp,
                              onRecallDown: onRecallDown,
                              highlightsKeyword: agent == .claudeCode,
                              commandNames: Set(commands.map { $0.name.lowercased() }),
                              onSuggestionKey: onSuggestionKey,
                              onCommandKey: commandKey,
                              onDropFiles: blocked ? nil : { attach(Attachments.fromDrop($0)) },
                              onFileDragTargeted: { dropTargeted = $0 },
                              minimumLines: minimumLines) {
                    accessory
                }

                if busy, canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.accentFill))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverLift(amount: Motion.smallLift)
                    .accessibilityLabel("Queue prompt")
                    .appTooltip("Queue this for when the turn ends")
                    .transition(.fadeIn)
                }

                // Send and Stop share one place, so a turn starting reads as the button
                // turning into the other, and the field never changes width over it.
                primaryButton(state: state, canSend: canSend)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: canSend)
            .animation(reduceMotion ? nil : Motion.control, value: busy)
            .animation(reduceMotion ? nil : Motion.control, value: state == .stopping)
        }
        .padding(.horizontal, inset)
        // The top matches the stack spacing, so a row above the field sits evenly
        // between the edge of the bar and the field.
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Theme.accent, lineWidth: dropTargeted ? 2 : 0)
            .padding(6))
        // Saved drafts need the command names too. Refresh as the menu opens or closes,
        // since command files can change between prompts.
        .task(id: [agent.rawValue, String(query == nil)] + roots) {
            let agent = agent
            let loaded = await Task.detached {
                AgentCommands.all(for: agent, workingDirectories: roots)
            }.value
            guard !Task.isCancelled else { return }
            commands = loaded
        }
        .onChange(of: query) { _, typed in
            commandSelection = 0
            // Waving the menu away is about the word that was on screen, so the next one
            // typed gets its own answer.
            if typed != dismissedQuery { dismissedQuery = nil }
        }
        .pasteAttachments(enabled: isFocused && !blocked) { attach($0) }
        .dropDestination(for: URL.self) { urls, _ in
            guard !blocked else { return false }
            attach(Attachments.fromDrop(urls))
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // One button that sends, stops, or waits for a stop to land. It stays put while its
    // glyph turns into the next one: the button carries views AppKit lays out itself,
    // and those cannot be spun or shrunk. With nothing to send it keeps its place, so the
    // field does not change width as soon as there is something.
    //
    // Idle it is the green send arrow. While a turn works it is red with a square and a
    // faint ring turning around it, and amber while the agent is asking a question, so
    // the way to stop is never in doubt.
    private func primaryButton(state: SessionState, canSend: Bool) -> some View {
        let stopping = state == .stopping
        let busy = state.isBusy
        let asking = runner.question(sessionID) != nil
        let fill: Color = stopping ? Theme.field
            : busy ? (asking ? Theme.attention : Theme.deletion)
            : Theme.accentFill.opacity(canSend ? 1 : 0.45)
        return Button {
            if busy { runner.stop(sessionID) } else { send() }
        } label: {
            ZStack {
                Circle().fill(fill)
                if stopping {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .transition(.buttonSwap)
                } else if busy {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .transition(.buttonSwap)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.buttonSwap)
                }
            }
            .frame(width: 32, height: 32)
            .overlay {
                if busy && !stopping {
                    TurnRing(colour: asking ? Theme.attention : Theme.deletion)
                        .transition(.opacity)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(stopping || (!busy && !canSend))
        .hoverLift(amount: Motion.smallLift)
        .motion(Motion.control, value: busy)
        .motion(Motion.control, value: asking)
        .motion(Motion.hover, value: canSend)
        .accessibilityLabel(stopping ? "Stopping this turn" : busy ? "Stop this turn" : "Send prompt")
        .appTooltip(stopping ? "Stopping this turn"
                    : busy ? "Stop this turn (esc)"
                    : canSend ? "Send (shift-return for a new line)" : "")
    }

    // What is waiting to go out with the next prompt. Long file names are common, so the
    // strip scrolls rather than squeezing the chips.
    @ViewBuilder private var attachmentStrip: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(attachments) { attachment in
                        AttachmentChip(url: attachment.url) {
                            runner.editDraft(sessionID) { $0.attachments.removeAll { $0.id == attachment.id } }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // The keys the menu answers, taken only while it is on screen. Return picks the
    // highlighted command rather than sending, so a half-typed name can never be sent as
    // a prompt by the key that finishes it; the next return sends what it left behind.
    private func commandKey(_ key: CommandKey) -> Bool {
        let matches = matches
        guard !blocked, !matches.isEmpty else { return false }
        let selected = min(commandSelection, matches.count - 1)
        switch key {
        case .up:
            commandSelection = (selected - 1 + matches.count) % matches.count
        case .down:
            commandSelection = (selected + 1) % matches.count
        case .complete:
            take(matches[selected])
        case .cancel:
            dismissedQuery = query
        }
        return true
    }

    // The name goes in whole, with a space after it, so anything the command takes can be
    // typed straight on the end. The space also closes the menu, since the word is settled.
    private func take(_ command: AgentCommand) {
        runner.editDraft(sessionID) { $0.text = command.typed + " " }
        commandSelection = 0
        isFocused = true
    }

    private func attach(_ found: [Attachment]) {
        runner.attach(found, to: sessionID)
        isFocused = true
    }

    private func send() {
        let draft = runner.draft(sessionID)
        guard !blocked, !draft.isEmpty else { return }
        onSend?()
        runner.send(draft.text.trimmed,
                    attachments: draft.attachments,
                    customInstructions: draft.customInstructions,
                    sessionID: sessionID,
                    store: store)
        runner.clearDraft(sessionID)
    }
}

// A faint arc turning around the stop button once every 1.4 seconds, so a working turn
// reads as alive even with the transcript scrolled away. With motion turned down it holds
// still and the colour and the square still say the turn is running.
private struct TurnRing: View {
    let colour: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TurnRingLayer(colour: colour, moving: !reduceMotion)
            .padding(-4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TurnRingLayer: NSViewRepresentable {
    let colour: Color
    let moving: Bool

    func makeNSView(context: Context) -> TurnRingView { TurnRingView() }

    func updateNSView(_ view: TurnRingView, context: Context) {
        view.update(colour: colour.resolve(in: context.environment).cgColor, moving: moving)
    }
}

// The arc is a slice of a conic gradient seen through a ring-shaped mask. The gradient
// fades in towards the arc's leading end, which is the end the turn moves towards.
final class TurnRingView: LoopLayerView {
    static let lap: CFTimeInterval = 1.4
    static let arcLength: NSNumber = 0.3

    private let turner = CALayer()
    private let gradient = CAGradientLayer()
    private let ring = CAShapeLayer()
    private var colour: CGColor?
    private(set) var moving = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, Self.arcLength, Self.arcLength, 1]
        ring.fillColor = nil
        ring.strokeColor = .black
        ring.lineWidth = 2
        gradient.mask = ring
        turner.addSublayer(gradient)
        layer?.addSublayer(turner)
    }

    var loops: [String] { turner.animationKeys() ?? [] }

    func update(colour: CGColor, moving: Bool) {
        if colour != self.colour {
            self.colour = colour
            let clear = colour.copy(alpha: 0) ?? colour
            let lit = colour.copy(alpha: colour.alpha * 0.55) ?? colour
            LayerLoop.still { gradient.colors = [clear, lit, clear, clear] }
        }
        guard moving != self.moving else { return }
        self.moving = moving
        restartLoops()
    }

    override func layoutLayers() {
        turner.bounds = bounds
        turner.position = CGPoint(x: bounds.midX, y: bounds.midY)
        // The line is centred on the circle, so half of it lies outside the view. The
        // gradient reaches that far too, or the mask would cut the line in half.
        let overhang = ring.lineWidth / 2
        gradient.frame = bounds.insetBy(dx: -overhang, dy: -overhang)
        ring.frame = gradient.bounds
        ring.path = CGPath(ellipseIn: gradient.bounds.insetBy(dx: overhang, dy: overhang),
                           transform: nil)
    }

    override func restartLoops() {
        turner.removeAnimation(forKey: "turn")
        guard moving else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = CGFloat.pi * 2
        turn.duration = Self.lap
        turner.add(LayerLoop.repeating(turn, period: Self.lap), forKey: "turn")
    }
}

extension SessionRunner {
    // Files joining the unsent prompt. The same file twice in one prompt says nothing
    // new, so one already waiting is skipped.
    func attach(_ found: [Attachment], to sessionID: UUID) {
        editDraft(sessionID) { draft in
            for item in found where !draft.attachments.contains(where: { $0.url == item.url }) {
                draft.attachments.append(item)
            }
        }
    }
}
