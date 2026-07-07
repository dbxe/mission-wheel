import Foundation

public enum WindowAction: String, Equatable, Sendable {
    case applicationWindows = "application-windows"
    case missionControl = "mission-control"
}

public struct ScrollSample: Equatable, Sendable {
    public let unitDeltaX: Int64
    public let pointDeltaX: Int64
    public let fixedPointDeltaX: Int64
    public let isContinuous: Bool
    public let time: TimeInterval

    public init(
        unitDeltaX: Int64,
        pointDeltaX: Int64,
        fixedPointDeltaX: Int64,
        isContinuous: Bool,
        time: TimeInterval
    ) {
        self.unitDeltaX = unitDeltaX
        self.pointDeltaX = pointDeltaX
        self.fixedPointDeltaX = fixedPointDeltaX
        self.isContinuous = isContinuous
        self.time = time
    }

    public var preferredDeltaX: Int64 {
        if unitDeltaX != 0 {
            return unitDeltaX
        }

        if pointDeltaX != 0 {
            return pointDeltaX
        }

        if fixedPointDeltaX != 0 {
            return fixedPointDeltaX > 0 ? 1 : -1
        }

        return 0
    }
}

public enum ScrollDecision: Equatable, Sendable {
    case trigger
    case suppress
    case passThrough

    public var shouldTriggerShortcut: Bool {
        switch self {
        case .trigger:
            return true
        case .suppress, .passThrough:
            return false
        }
    }

    public var shouldSuppressEvent: Bool {
        switch self {
        case .trigger, .suppress:
            return true
        case .passThrough:
            return false
        }
    }
}

public struct ScrollDecisionEngine: Sendable {
    public static let defaultCooldown: TimeInterval = 0.25

    private let cooldown: TimeInterval
    private var lastTriggerSign: Int64 = 0
    private var lastTriggerTime: TimeInterval = -.infinity

    public init(cooldown: TimeInterval = Self.defaultCooldown) {
        self.cooldown = max(0, cooldown)
    }

    public mutating func evaluate(_ sample: ScrollSample) -> ScrollDecision {
        if sample.isContinuous {
            return .passThrough
        }

        let delta = sample.preferredDeltaX
        if delta == 0 {
            return .passThrough
        }

        let sign: Int64 = delta > 0 ? 1 : -1
        if sample.time - lastTriggerTime < cooldown, sign == lastTriggerSign {
            return .suppress
        }

        lastTriggerTime = sample.time
        lastTriggerSign = sign
        return .trigger
    }
}

public struct WindowActionRouter: Sendable {
    public static let defaultMissionControlSelectionTimeout: TimeInterval = 10

    private let swapDirections: Bool
    private let missionControlSelectionTimeout: TimeInterval
    private var missionControlSelectionExpiresAt: TimeInterval?

    public init(
        swapDirections: Bool = false,
        missionControlSelectionTimeout: TimeInterval = Self.defaultMissionControlSelectionTimeout
    ) {
        self.swapDirections = swapDirections
        self.missionControlSelectionTimeout = max(0, missionControlSelectionTimeout)
    }

    public mutating func action(for sample: ScrollSample) -> WindowAction? {
        let delta = sample.preferredDeltaX
        guard delta != 0 else {
            return nil
        }

        if let expiresAt = missionControlSelectionExpiresAt {
            missionControlSelectionExpiresAt = nil
            if sample.time <= expiresAt {
                return .missionControl
            }
        }

        if deltaMeansMissionControl(delta) {
            missionControlSelectionExpiresAt = sample.time + missionControlSelectionTimeout
            return .missionControl
        }

        return .applicationWindows
    }

    public mutating func resetTransientState() {
        missionControlSelectionExpiresAt = nil
    }

    private func deltaMeansMissionControl(_ delta: Int64) -> Bool {
        if swapDirections {
            return delta < 0
        }

        return delta > 0
    }
}
