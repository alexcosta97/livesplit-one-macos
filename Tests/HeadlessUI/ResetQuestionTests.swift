import AppKit
import Synchronization
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct ResetQuestionTests {
    @Test func theAlertAsksAboutTheBestTimes() {
        let alert = ResetQuestion.alert()
        #expect(alert.messageText == "Do you want to update your best times?")
        #expect(alert.informativeText == "This attempt has beaten some of your best times.")
    }

    @Test func theButtonsAreYesNoAndDontResetInThatOrder() {
        #expect(ResetQuestion.alert().buttons.map(\.title) == ["Yes", "No", "Don't Reset"])
    }

    @Test func theButtonsGiveTheirAnswers() {
        #expect(ResetQuestion.answer(for: .alertFirstButtonReturn) == .yes)
        #expect(ResetQuestion.answer(for: .alertSecondButtonReturn) == .no)
        #expect(ResetQuestion.answer(for: .alertThirdButtonReturn) == .dontReset)
    }

    @Test(arguments: [NSApplication.ModalResponse.abort, .stop, .cancel, .continue])
    func anyOtherResponseDoesNotReset(response: NSApplication.ModalResponse) {
        #expect(ResetQuestion.answer(for: response) == .dontReset)
    }

    /// While the alert is open, other main-actor work keeps running, so the timer's window is
    /// told of changes and keeps drawing. `waitOnMain` is what the command queue asks the
    /// question with.
    @Test(.timeLimit(.minutes(1))) func otherMainActorWorkRunsWhileTheAlertIsOpen() async {
        let ran = Mutex<[String]>([])
        let answered = Mutex(false)
        let answer = await withCheckedContinuation {
            (done: CheckedContinuation<ResetAnswer, Never>) in
            DispatchQueue.global().async {
                // Closes the alert, as an answer would, after the probes had time to run.
                DispatchQueue.main.async {
                    let closing = Timer(timeInterval: 0.5, repeats: false) { _ in
                        MainActor.assumeIsolated { NSApp.abortModal() }
                    }
                    RunLoop.main.add(closing, forMode: .common)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ran.withLock { if !answered.withLock({ $0 }) { $0.append("queue") } }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    ran.withLock { if !answered.withLock({ $0 }) { $0.append("task") } }
                }
                let answer = CommandRunner.waitOnMain { ResetQuestion.ask() }
                answered.withLock { $0 = true }
                done.resume(returning: answer)
            }
        }
        #expect(answer == .dontReset)
        // Both ran before the question was answered, not after.
        #expect(
            ran.withLock { $0 } == ["queue", "task"] || ran.withLock { $0 } == ["task", "queue"])
    }
}
