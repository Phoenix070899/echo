import AppKit
import SwiftUI

// Foundry's question (ui-ux/0140): what Echo asks before it does something that cannot be taken
// back, in place of the system's alert and confirmation dialog. A card centred over the dimmed
// window (ui-ux/0006), the sheet grey in a 2 pt ink frame, a bold question over a quiet line, an
// optional field, and Foundry's buttons. Return runs the primary answer, Esc or a click on the
// backdrop cancels.

/// One answer to a question: its button.
public struct FoundryAnswer: Equatable {
    public enum Role { case primary, destructive, plain }

    public let title: String
    public let role: Role

    public init(_ title: String, role: Role = .plain) {
        self.title = title
        self.role = role
    }
}

/// What a question asks, and the field it carries, if any.
public struct FoundryQuestion {
    public let title: String
    public let message: String
    /// The answers, left to right before Cancel; the last one is run by Return.
    public let answers: [FoundryAnswer]
    /// A field's placeholder; nil for a question without one.
    public let field: String?
    /// The button that cancels; nil for a notice that has only its answer.
    public let cancel: String?

    public init(_ title: String, message: String = "", answers: [FoundryAnswer], field: String? = nil,
                cancel: String? = "Cancel") {
        self.title = title
        self.message = message
        self.answers = answers
        self.field = field
        self.cancel = cancel
    }
}

/// The question the window shows, one at a time. The window's `foundryAskHost` draws it.
@MainActor
public final class FoundryAsk: ObservableObject {
    public static let shared = FoundryAsk()

    @Published public private(set) var question: FoundryQuestion?
    @Published public var text = ""
    private var answered: ((String?, String) -> Void)?
    /// What held the keyboard before the question, given it back after, as an alert does.
    private weak var before: NSResponder?

    public init() {}

    /// Shows `question`; `answered` gets the picked answer's title and the field's text, or nil
    /// when the human cancels. A question asked while one is up cancels the first.
    public func ask(_ question: FoundryQuestion, answered: @escaping (_ answer: String?, _ text: String) -> Void) {
        if self.question != nil { answer(nil) }
        let window = NSApp?.keyWindow ?? NSApp?.mainWindow ?? NSApp?.orderedWindows.first { $0.isVisible && $0.canBecomeKey }
        before = window?.firstResponder
        text = ""
        self.answered = answered
        self.question = question
    }

    /// Tells the human something that went wrong; one OK closes it.
    public func tell(_ title: String, message: String = "") {
        ask(FoundryQuestion(title, message: message, answers: [FoundryAnswer("OK", role: .primary)], cancel: nil)) { _, _ in }
    }

    /// Asks with one answer and runs `then` only when the human picks it.
    public func confirm(_ title: String, message: String = "", answer: FoundryAnswer, then: @escaping () -> Void) {
        ask(FoundryQuestion(title, message: message, answers: [answer])) { picked, _ in
            if picked == answer.title { then() }
        }
    }

    /// Closes the question with `title` picked, or nil for Cancel.
    public func answer(_ title: String?) {
        let answered = answered
        let text = text
        self.answered = nil
        question = nil
        if let view = before as? NSView, let window = view.window {
            // Once the card has gone, so its own focus does not take the keyboard back.
            DispatchQueue.main.async { window.makeFirstResponder(view) }
        }
        before = nil
        answered?(title, text)
    }
}

extension View {
    /// Draws the question `FoundryAsk.shared` asks over this view.
    @MainActor public func foundryAskHost() -> some View {
        overlay { FoundryAskCard(ask: .shared) }
    }
}

private struct FoundryAskCard: View {
    @ObservedObject var ask: FoundryAsk
    @FocusState private var focus: Focus?

    private enum Focus { case card, field }

    var body: some View {
        if let question = ask.question {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { ask.answer(nil) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(question.title)
                        .font(Ledger.font(18, .bold))
                        .foregroundStyle(Ledger.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    if !question.message.isEmpty {
                        Text(question.message)
                            .font(Ledger.font(13))
                            .foregroundStyle(Ledger.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                    }
                    if let placeholder = question.field {
                        TextField(placeholder, text: $ask.text)
                            .squareField(.inspector)
                            .focused($focus, equals: .field)
                            .onSubmit { pickLast(question) }
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        if let cancel = question.cancel {
                            Button(cancel) { ask.answer(nil) }
                                .buttonStyle(.settings)
                                .keyboardShortcut(.cancelAction)
                        }
                        ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                            let last = index == question.answers.count - 1
                            Button(answer.title) { ask.answer(answer.title) }
                                .buttonStyle(SettingsButtonStyle(primary: last, destructive: answer.role == .destructive))
                                .modifier(DefaultAction(on: last))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .frame(width: 420)
                .background(Ledger.paper)
                // A frame, not a shadow, sets it apart from the dimmed window (ui-ux/0013).
                .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
            // Focus leaves what is under the card, so Esc and Return reach the card.
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .card)
            .onAppear { DispatchQueue.main.async { focus = question.field == nil ? .card : .field } }
            .onExitCommand { ask.answer(nil) }
        }
    }

    private func pickLast(_ question: FoundryQuestion) {
        if let last = question.answers.last { ask.answer(last.title) }
    }
}

/// Return runs the last answer.
private struct DefaultAction: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
