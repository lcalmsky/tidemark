import Testing
import TidemarkCore

private func usage(
    _ name: String,
    ok: Bool = true,
    session: Double? = 10,
    weekly: Double? = 10
) -> AccountUsage {
    AccountUsage(name: name, ok: ok, sessionPercent: session, weeklyAllPercent: weekly)
}

@Suite("autoSwitchDecision")
struct AutoSwitchTests {
    @Test func belowThresholdDoesNothing() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 94.9, weekly: 10),
            usage("b", session: 5, weekly: 5),
        ])
        #expect(decision == nil)
    }

    @Test func sessionAtThresholdSwitches() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 95, weekly: 10),
            usage("b", session: 5, weekly: 5),
        ])
        #expect(decision == AutoSwitchDecision(target: "b", label: "세션", percent: 95))
    }

    @Test func weeklyAtThresholdSwitchesWithWeeklyLabel() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 10, weekly: 95),
            usage("b", session: 5, weekly: 5),
        ])
        #expect(decision == AutoSwitchDecision(target: "b", label: "주간", percent: 95))
    }

    @Test func currentWithErrorDoesNothing() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", ok: false, session: 99, weekly: 99),
            usage("b", session: 5, weekly: 5),
        ])
        #expect(decision == nil)
    }

    @Test func missingCurrentDoesNothing() {
        let decision = autoSwitchDecision(currentName: "missing", accounts: [
            usage("b", session: 5, weekly: 5),
        ])
        #expect(decision == nil)
    }

    @Test func candidateWithErrorIsSkipped() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", ok: false, session: 1, weekly: 1),
        ])
        #expect(decision == nil)
    }

    @Test func candidateWithoutBothPercentagesIsSkipped() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", session: 1, weekly: nil),
            usage("c", session: nil, weekly: 1),
        ])
        #expect(decision == nil)
    }

    @Test func candidateAtThresholdIsSkipped() {
        let sessionDecision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", session: 95, weekly: 1),
        ])
        #expect(sessionDecision == nil)

        let weeklyDecision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", session: 1, weekly: 95),
        ])
        #expect(weeklyDecision == nil)
    }

    @Test func lowestSessionWins() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", session: 50, weekly: 1),
            usage("c", session: 20, weekly: 1),
        ])
        #expect(decision?.target == "c")
    }

    @Test func tieKeepsEarlierAccount() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
            usage("b", session: 20, weekly: 1),
            usage("c", session: 20, weekly: 1),
        ])
        #expect(decision?.target == "b")
    }

    @Test func noCandidateDoesNothing() {
        let decision = autoSwitchDecision(currentName: "a", accounts: [
            usage("a", session: 99, weekly: 99),
        ])
        #expect(decision == nil)
    }
}
