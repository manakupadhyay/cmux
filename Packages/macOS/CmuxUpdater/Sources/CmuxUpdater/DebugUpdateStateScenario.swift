#if DEBUG
import Foundation
@preconcurrency import Sparkle

/// A synthetic update state the debug menu can show, so every pill and popover variant can be
/// previewed without a real update. Actions inside the popover move between these states the
/// way the real flow would, and restarting clears the preview.
public enum DebugUpdateStateScenario: String, CaseIterable, Hashable, Sendable {
    case updateAvailable
    case checking
    case downloading
    case extracting
    case restartToUpdate
    case readyNoAgents
    case readyAgentsWorking
    case readyRiskyAgents
    case readyWaitingForAgents
    case noUpdates

    /// The label shown for this scenario in the debug menu.
    public var menuTitle: String {
        switch self {
        case .updateAvailable:
            return String(localized: "update.debug.state.updateAvailable", defaultValue: "Update Available")
        case .checking:
            return String(localized: "update.debug.state.checking", defaultValue: "Checking")
        case .downloading:
            return String(localized: "update.debug.state.downloading", defaultValue: "Downloading")
        case .extracting:
            return String(localized: "update.debug.state.extracting", defaultValue: "Preparing")
        case .restartToUpdate:
            return String(localized: "update.readyWaiting", defaultValue: "Update Ready")
        case .readyNoAgents:
            return String(localized: "update.debug.state.readyNoAgents", defaultValue: "Update Ready: No Agents")
        case .readyAgentsWorking:
            return String(localized: "update.debug.state.readyAgentsWorking", defaultValue: "Update Ready: Agents Working")
        case .readyRiskyAgents:
            return String(localized: "update.debug.state.readyRiskyAgents", defaultValue: "Update Ready: Risky Agents")
        case .readyWaitingForAgents:
            return String(localized: "update.debug.state.readyWaitingForAgents", defaultValue: "Update Ready: Waiting for Agents")
        case .noUpdates:
            return String(localized: "update.debug.state.noUpdates", defaultValue: "No Updates")
        }
    }

    /// Builds the state. `show` replaces the previewed state; `end` clears the preview.
    @MainActor
    func state(show: @escaping @MainActor (DebugUpdateStateScenario) -> Void, end: @escaping @MainActor () -> Void) -> UpdateState {
        switch self {
        case .updateAvailable:
            return .updateAvailable(.init(appcastItem: Self.item, reply: { _ in }))
        case .checking:
            return .checking(.init(cancel: { end() }))
        case .downloading:
            return .downloading(.init(cancel: { end() }, expectedLength: 143_414_809, progress: 57_000_000))
        case .extracting:
            return .extracting(.init(progress: 0.6))
        case .restartToUpdate:
            return .installing(.init(retryTerminatingApplication: { end() }, dismiss: {}))
        case .noUpdates:
            return .notFound(.init(acknowledgement: { end() }))
        case .readyNoAgents:
            return held(.empty, mode: .quietMoment, show: show, end: end)
        case .readyAgentsWorking:
            return held(UpdateRelaunchBlockers(agents: [Self.codex], runningCommandCount: 0), mode: .quietMoment, show: show, end: end)
        case .readyRiskyAgents:
            return held(
                UpdateRelaunchBlockers(agents: [Self.claude, Self.codex], runningCommandCount: 2),
                mode: .askingUser,
                show: show,
                end: end
            )
        case .readyWaitingForAgents:
            return held(Self.waitingBlockers, mode: .waitingForAgents, show: show, end: end)
        }
    }

    private static let waitingBlockers = UpdateRelaunchBlockers(agents: [claude, codex], runningCommandCount: 0)

    @MainActor
    private func held(
        _ blockers: UpdateRelaunchBlockers,
        mode: UpdateRelaunchHoldMode,
        show: @escaping @MainActor (DebugUpdateStateScenario) -> Void,
        end: @escaping @MainActor () -> Void
    ) -> UpdateState {
        .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: { end() },
            dismiss: {},
            relaunchBlockers: blockers,
            holdMode: mode,
            updateWhenClear: mode != .waitingForAgents && !blockers.workingAgents.isEmpty
                ? { show(.readyWaitingForAgents) }
                : nil
        ))
    }

    private static let claude = UpdateRelaunchAgent(
        id: "debug-claude", name: "Claude Code", location: "cmux", safety: .risky, activity: "Bash: swift build"
    )
    private static let codex = UpdateRelaunchAgent(
        id: "debug-codex", name: "Codex", location: "hq", safety: .care, activity: "Thinking"
    )

    private static var item: SUAppcastItem {
        SUAppcastItem(dictionary: [
            "title": "cmux 0.64.26",
            "pubDate": "Wed, 30 Sep 2026 12:00:00 +0000",
            "enclosure": [
                "url": "https://example.com/cmux.dmg",
                "length": "143414809",
                "sparkle:version": "106",
                "sparkle:shortVersionString": "0.64.26",
            ],
        ]) ?? SUAppcastItem.empty()
    }
}
#endif
