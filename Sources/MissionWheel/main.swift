import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import MissionWheelCore

private enum AppError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case accessibilityNotGranted
    case eventTapUnavailable

    var description: String {
        switch self {
        case let .invalidArgument(message):
            return message
        case .accessibilityNotGranted:
            return """
            Accessibility permission is required.

            Open System Settings > Privacy & Security > Accessibility, enable Mission Wheel, then run the command again.
            If it is already enabled, remove it from the list and add ~/Applications/Mission Wheel.app again after the final install.
            """
        case .eventTapUnavailable:
            return """
            Could not create the macOS event tap.

            This usually means Accessibility permission is missing for the installed app, another tool is blocking event taps, or the process is running outside a GUI login session.
            """
        }
    }
}

private enum Command {
    case run
    case listen
    case triggerApplicationWindows
    case triggerMissionControl
    case check
}

private struct RuntimeOptions {
    var command: Command = .run
    var cooldown = ScrollDecisionEngine.defaultCooldown
    var swapDirections = false
    var debug = false
    var excludedBundleIDs: Set<String> = []
}

private let escapeKeyCode: Int64 = 53

private final class WindowActionTrigger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mission-wheel.shortcut")

    func send(_ action: WindowAction) {
        queue.async {
            self.sendSynchronously(action, logsFailure: true)
        }
    }

    @discardableResult
    func sendSynchronously(_ action: WindowAction, logsFailure: Bool = false) -> Bool {
        let succeeded: Bool
        switch action {
        case .applicationWindows:
            succeeded = showApplicationWindows()
        case .missionControl:
            succeeded = showMissionControl()
        }

        if !succeeded && logsFailure {
            logFailure(for: action)
        }

        return succeeded
    }

    private func showApplicationWindows() -> Bool {
        guard
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            return false
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        guard let dockItems = copyDockItems(from: dockElement) else {
            return false
        }

        if let bundleURL = frontmostApplication.bundleURL?.standardizedFileURL {
            for dockItem in dockItems {
                guard dockItemURL(dockItem)?.standardizedFileURL.path == bundleURL.path else {
                    continue
                }

                if performShowExpose(on: dockItem) {
                    return true
                }
            }
        }

        guard let applicationName = frontmostApplication.localizedName else {
            return false
        }

        for dockItem in dockItems {
            guard dockItemTitle(dockItem) == applicationName else {
                continue
            }

            if performShowExpose(on: dockItem) {
                return true
            }
        }

        return false
    }

    private func showMissionControl() -> Bool {
        let workspace = NSWorkspace.shared

        if let missionControlURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher"),
           workspace.open(missionControlURL) {
            return true
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        if FileManager.default.fileExists(atPath: fallbackURL.path), workspace.open(fallbackURL) {
            return true
        }

        return false
    }

    private func copyDockItems(from dockElement: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef).rawValue == 0,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)

            guard roleRef as? String == kAXListRole else {
                continue
            }

            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsRef).rawValue == 0,
                  let items = itemsRef as? [AXUIElement] else {
                return nil
            }

            return items
        }

        return nil
    }

    private func dockItemTitle(_ dockItem: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockItem, kAXTitleAttribute as CFString, &titleRef).rawValue == 0 else {
            return nil
        }

        return titleRef as? String
    }

    private func dockItemURL(_ dockItem: AXUIElement) -> URL? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockItem, kAXURLAttribute as CFString, &urlRef).rawValue == 0 else {
            return nil
        }

        if let url = urlRef as? URL {
            return url
        }

        if let urlString = urlRef as? String {
            if let url = URL(string: urlString), url.scheme != nil {
                return url
            }

            return URL(fileURLWithPath: urlString)
        }

        return nil
    }

    private func performShowExpose(on dockItem: AXUIElement) -> Bool {
        let action = "AXShowExpose" as CFString
        guard supportsAction(action, element: dockItem) else {
            return false
        }

        return AXUIElementPerformAction(dockItem, action).rawValue == 0
    }

    private func supportsAction(_ action: CFString, element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef).rawValue == 0,
              let actions = actionsRef as? [String] else {
            return false
        }

        return actions.contains(action as String)
    }

    private func logFailure(for action: WindowAction) {
        fputs("failed to trigger \(action.rawValue) for \(failureTarget(for: action))\n", stderr)
        fflush(stderr)
    }

    private func failureTarget(for action: WindowAction) -> String {
        switch action {
        case .applicationWindows:
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            return frontmostApplication?.bundleIdentifier ??
                frontmostApplication?.localizedName ??
                "unknown application"
        case .missionControl:
            return "com.apple.exposelauncher"
        }
    }
}

private final class EventTapRunner {
    private let options: RuntimeOptions
    private let windowActionTrigger = WindowActionTrigger()
    private var decisionEngine: ScrollDecisionEngine
    private var actionRouter: WindowActionRouter
    private var eventTap: CFMachPort?

    init(options: RuntimeOptions) {
        self.options = options
        self.decisionEngine = ScrollDecisionEngine(cooldown: options.cooldown)
        self.actionRouter = WindowActionRouter(swapDirections: options.swapDirections)
    }

    func run() throws {
        let tapOptions: CGEventTapOptions = options.command == .listen ? .listenOnly : .defaultTap
        var eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        if options.command == .run {
            eventMask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
        }

        guard let tap = createEventTap(options: tapOptions, eventMask: eventMask) else {
            throw AppError.eventTapUnavailable
        }

        eventTap = tap

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw AppError.eventTapUnavailable
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    private func createEventTap(options tapOptions: CGEventTapOptions, eventMask: CGEventMask) -> CFMachPort? {
        let attempts = options.command == .run ? 5 : 1

        for attempt in 1...attempts {
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: tapOptions,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                return tap
            }

            if attempt < attempts {
                Thread.sleep(forTimeInterval: 1)
            }
        }

        return nil
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown {
            actionRouter.resetTransientState()
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventKeycode) == escapeKeyCode {
                actionRouter.resetTransientState()
            }

            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let sample = ScrollSample(
            unitDeltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            pointDeltaX: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            fixedPointDeltaX: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            time: ProcessInfo.processInfo.systemUptime
        )

        if options.command == .listen {
            printEvent(event: event, sample: sample, decision: nil, action: nil)
            return Unmanaged.passUnretained(event)
        }

        if shouldPassThroughForExcludedBundleID(sample: sample) {
            return Unmanaged.passUnretained(event)
        }

        let decision = decisionEngine.evaluate(sample)
        var action: WindowAction?
        if decision.shouldTriggerShortcut {
            action = actionRouter.action(for: sample)
            if let action {
                windowActionTrigger.send(action)
            }
        }

        if options.debug {
            printEvent(event: event, sample: sample, decision: decision, action: action)
        }

        if decision.shouldSuppressEvent {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func shouldPassThroughForExcludedBundleID(sample: ScrollSample) -> Bool {
        guard !options.excludedBundleIDs.isEmpty else {
            return false
        }

        guard !sample.isContinuous, sample.preferredDeltaX != 0 else {
            return false
        }

        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }

        return options.excludedBundleIDs.contains(bundleID)
    }

    private func printEvent(event: CGEvent, sample: ScrollSample, decision: ScrollDecision?, action: WindowAction?) {
        let unitY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedY = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)

        let decisionText: String
        if let decision {
            decisionText = " decision=\(decision)"
        } else {
            decisionText = ""
        }

        let actionText = action.map { " action=\($0.rawValue)" } ?? ""

        print(
            "x(unit=\(sample.unitDeltaX), point=\(sample.pointDeltaX), fixed=\(sample.fixedPointDeltaX)) " +
                "y(unit=\(unitY), point=\(pointY), fixed=\(fixedY)) " +
                "continuous=\(sample.isContinuous ? 1 : 0)" +
                decisionText +
                actionText
        )
        fflush(stdout)
    }
}

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let runner = Unmanaged<EventTapRunner>.fromOpaque(userInfo).takeUnretainedValue()
    return runner.handleEvent(type: type, event: event)
}

private func parseOptions(arguments: [String]) throws -> RuntimeOptions {
    var options = RuntimeOptions()

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "run":
            options.command = .run
        case "listen":
            options.command = .listen
        case "trigger-application-windows":
            options.command = .triggerApplicationWindows
        case "trigger-mission-control":
            options.command = .triggerMissionControl
        case "check":
            options.command = .check
        case "--debug":
            options.debug = true
        case "--swap-directions":
            options.swapDirections = true
        case "--cooldown-ms":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]), value >= 0 else {
                throw AppError.invalidArgument("--cooldown-ms requires a non-negative number")
            }
            options.cooldown = value / 1_000
        case "--exclude-bundle-id":
            index += 1
            guard index < arguments.count else {
                throw AppError.invalidArgument("--exclude-bundle-id requires a bundle identifier or comma-separated list")
            }
            try insertExcludedBundleIDs(from: arguments[index], into: &options.excludedBundleIDs)
        case "--help", "-h":
            printUsageAndExit()
        default:
            throw AppError.invalidArgument("Unknown argument: \(argument)")
        }

        index += 1
    }

    return options
}

private func insertExcludedBundleIDs(from argument: String, into bundleIDs: inout Set<String>) throws {
    let values = argument.split(separator: ",").map {
        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }

    guard !values.isEmpty else {
        throw AppError.invalidArgument("--exclude-bundle-id requires a bundle identifier or comma-separated list")
    }

    for value in values {
        bundleIDs.insert(value)
    }
}

private func ensureAccessibilityPermission() throws {
    if !isAccessibilityTrusted(prompt: true) {
        throw AppError.accessibilityNotGranted
    }
}

private func waitForAccessibilityPermission() {
    if isAccessibilityTrusted(prompt: true) {
        return
    }

    print("waiting for Accessibility permission...")
    fflush(stdout)

    while !AXIsProcessTrusted() {
        Thread.sleep(forTimeInterval: 2)
    }
}

private func isAccessibilityTrusted(prompt: Bool) -> Bool {
    let promptKey = "AXTrustedCheckOptionPrompt"
    let options = [promptKey: prompt] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
}

private func printPermissionCheckAndExit() -> Never {
    let environment = ProcessInfo.processInfo.environment
    let termProgram = environment["TERM_PROGRAM"] ?? "unknown"
    let executablePath = Bundle.main.executablePath ?? "unknown"
    let trusted = isAccessibilityTrusted(prompt: false)

    print(
        """
        process: \(ProcessInfo.processInfo.processName)
        argv0: \(CommandLine.arguments.first ?? "unknown")
        executable: \(executablePath)
        bundle: \(Bundle.main.bundlePath)
        TERM_PROGRAM: \(termProgram)
        accessibilityTrusted: \(trusted ? "yes" : "no")
        """
    )

    if !trusted {
        print(
            """

            Open System Settings > Privacy & Security > Accessibility.
            Enable the app that launches this command, such as Terminal, iTerm2, WezTerm, VS Code, Zed, or Codex.
            For the login utility, enable ~/Applications/Mission Wheel.app separately.

            If the built binary itself appears in the list, enable that too.
            After changing the setting, quit and reopen the launching app, then run this check again.
            """
        )
    }

    exit(trusted ? 0 : 1)
}

private func printUsageAndExit() -> Never {
    print(
        """
        Usage:
          mission-wheel run [options]
          mission-wheel check
          mission-wheel listen
          mission-wheel trigger-application-windows
          mission-wheel trigger-mission-control

        Options:
          --cooldown-ms <ms>       Ignore repeated horizontal scrolls for this long after triggering. Default: 250
          --swap-directions        Make negative horizontal scroll trigger Mission Control
          --exclude-bundle-id <id> Pass matching frontmost apps through unchanged; repeatable, comma-separated accepted
          --debug                  Print handled events while running
          -h, --help               Show this help
        """
    )
    exit(0)
}

do {
    let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))

    switch options.command {
    case .check:
        printPermissionCheckAndExit()
    case .triggerMissionControl:
        exit(WindowActionTrigger().sendSynchronously(.missionControl, logsFailure: true) ? 0 : 1)
    case .triggerApplicationWindows:
        try ensureAccessibilityPermission()
        exit(WindowActionTrigger().sendSynchronously(.applicationWindows, logsFailure: true) ? 0 : 1)
    case .listen:
        try ensureAccessibilityPermission()
        print("Listening for scroll-wheel events. Move the horizontal wheel, then press Ctrl+C to stop.")
        try EventTapRunner(options: options).run()
    case .run:
        waitForAccessibilityPermission()
        if options.debug {
            let missionControlDirection = options.swapDirections ? "negative" : "positive"
            print("Mapping horizontal wheel scrolls: \(missionControlDirection) -> Mission Control, opposite -> Application Windows. Press Ctrl+C to stop.")
        }
        try EventTapRunner(options: options).run()
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
