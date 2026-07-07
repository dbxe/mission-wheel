import Testing

@testable import MissionWheelCore

@Test func triggersOnFirstHorizontalWheelTickByDefault() {
    var engine = ScrollDecisionEngine()

    let decision = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )

    #expect(decision == .trigger)
}

@Test func absorbsRepeatedScrollInsideCooldown() {
    var engine = ScrollDecisionEngine(cooldown: 0.8)

    let first = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let second = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.3)
    )

    #expect(first == .trigger)
    #expect(second == .suppress)
}

@Test func oppositeDirectionBypassesCooldownAndTriggers() {
    var engine = ScrollDecisionEngine(cooldown: 0.8)

    let first = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let second = engine.evaluate(
        ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.3)
    )

    #expect(first == .trigger)
    #expect(second == .trigger)
}

@Test func oppositeDirectionTriggerStartsItsOwnCooldown() {
    var engine = ScrollDecisionEngine(cooldown: 0.8)

    let first = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let opposite = engine.evaluate(
        ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.3)
    )
    let repeatedOpposite = engine.evaluate(
        ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.5)
    )

    #expect(first == .trigger)
    #expect(opposite == .trigger)
    #expect(repeatedOpposite == .suppress)
}

@Test func defaultCooldownIsShortEnoughForQuickReuse() {
    var engine = ScrollDecisionEngine()

    let first = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let second = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.3)
    )

    #expect(first == .trigger)
    #expect(second == .trigger)
}

@Test func triggersAgainAfterCooldown() {
    var engine = ScrollDecisionEngine(cooldown: 0.8)

    _ = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )

    let decision = engine.evaluate(
        ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10.9)
    )

    #expect(decision == .trigger)
}

@Test func ignoresContinuousScrollByDefault() {
    var engine = ScrollDecisionEngine()

    let decision = engine.evaluate(
        ScrollSample(unitDeltaX: 4, pointDeltaX: 4, fixedPointDeltaX: 0, isContinuous: true, time: 10)
    )

    #expect(decision == .passThrough)
}

@Test func routesPositiveDeltaToMissionControlByDefault() {
    var router = WindowActionRouter()

    let action = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )

    #expect(action == .missionControl)
}

@Test func routesNegativeDeltaToApplicationWindowsByDefault() {
    var router = WindowActionRouter()

    let action = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )

    #expect(action == .applicationWindows)
}

@Test func nextScrollAfterMissionControlSelectsWindowRegardlessOfDirection() {
    var router = WindowActionRouter()

    let open = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let selectWithLeft = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 11)
    )
    let normalLeftAfterSelection = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 12)
    )

    #expect(open == .missionControl)
    #expect(selectWithLeft == .missionControl)
    #expect(normalLeftAfterSelection == .applicationWindows)
}

@Test func missionControlSelectionWindowExpires() {
    var router = WindowActionRouter(missionControlSelectionTimeout: 2)

    let open = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let expiredLeft = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 13)
    )

    #expect(open == .missionControl)
    #expect(expiredLeft == .applicationWindows)
}

@Test func resetClearsPendingMissionControlSelection() {
    var router = WindowActionRouter()

    let open = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    router.resetTransientState()
    let leftAfterReset = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 11)
    )

    #expect(open == .missionControl)
    #expect(leftAfterReset == .applicationWindows)
}

@Test func resetAllowsRightScrollToOpenMissionControlAgain() {
    var router = WindowActionRouter()

    let open = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    router.resetTransientState()
    let rightAfterReset = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 11)
    )

    #expect(open == .missionControl)
    #expect(rightAfterReset == .missionControl)
}

@Test func swappedDirectionsStillAllowEitherDirectionToSelectAfterMissionControl() {
    var router = WindowActionRouter(swapDirections: true)

    let open = router.action(
        for: ScrollSample(unitDeltaX: -1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 10)
    )
    let selectWithRight = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 11)
    )
    let normalRightAfterSelection = router.action(
        for: ScrollSample(unitDeltaX: 1, pointDeltaX: 0, fixedPointDeltaX: 0, isContinuous: false, time: 12)
    )

    #expect(open == .missionControl)
    #expect(selectWithRight == .missionControl)
    #expect(normalRightAfterSelection == .applicationWindows)
}
