import Foundry
import Testing

@MainActor
@Test func anAnswerReachesTheAskerWithTheFieldsText() {
    let ask = FoundryAsk()
    var heard: (String?, String)?
    ask.ask(FoundryQuestion("New custom Worker", answers: [FoundryAnswer("Create", role: .primary)], field: "name")) {
        heard = ($0, $1)
    }
    #expect(ask.question?.title == "New custom Worker")
    ask.text = "code-reviewer"
    ask.answer("Create")
    #expect(heard?.0 == "Create")
    #expect(heard?.1 == "code-reviewer")
    #expect(ask.question == nil)
}

@MainActor
@Test func confirmRunsOnlyOnItsAnswer() {
    let ask = FoundryAsk()
    var ran = 0
    ask.confirm("Delete it?", answer: FoundryAnswer("Delete", role: .destructive)) { ran += 1 }
    ask.answer(nil)
    #expect(ran == 0)
    ask.confirm("Delete it?", answer: FoundryAnswer("Delete", role: .destructive)) { ran += 1 }
    ask.answer("Delete")
    #expect(ran == 1)
}

@MainActor
@Test func aSecondQuestionCancelsTheFirst() {
    let ask = FoundryAsk()
    var first: String?? = .none
    ask.ask(FoundryQuestion("First?", answers: [FoundryAnswer("Yes")])) { answer, _ in first = .some(answer) }
    ask.ask(FoundryQuestion("Second?", answers: [FoundryAnswer("Yes")])) { _, _ in }
    #expect(first == .some(nil))
    #expect(ask.question?.title == "Second?")
}

@MainActor
@Test func aNewQuestionStartsWithAnEmptyField() {
    let ask = FoundryAsk()
    ask.ask(FoundryQuestion("One", answers: [FoundryAnswer("OK")], field: "name")) { _, _ in }
    ask.text = "left over"
    ask.answer(nil)
    ask.ask(FoundryQuestion("Two", answers: [FoundryAnswer("OK")], field: "name")) { _, _ in }
    #expect(ask.text.isEmpty)
}
