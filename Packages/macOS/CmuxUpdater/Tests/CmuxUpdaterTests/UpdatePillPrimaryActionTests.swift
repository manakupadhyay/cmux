import Foundation
import Testing
@preconcurrency import Sparkle
@testable import CmuxUpdater

/// The update pill acts in one click: an available update installs and relaunches, and a
/// staged update restarts. Neither opens a popover that only repeats the same choice.
@MainActor
@Suite struct UpdatePillPrimaryActionTests {
    private func makeItem(_ version: String) -> SUAppcastItem {
        SUAppcastItem(dictionary: [
            "title": "cmux \(version)",
            "enclosure": [
                "url": "https://example.com/cmux.zip",
                "length": "1024",
                "sparkle:version": version,
                "sparkle:shortVersionString": version,
            ],
        ]) ?? SUAppcastItem.empty()
    }

    @Test func availableUpdateInstallsOnClick() {
        let model = UpdateStateModel()
        model.setState(.updateAvailable(.init(appcastItem: makeItem("0.64.26"), reply: { _ in })))

        #expect(model.pillPrimaryAction == .installLatest)
    }

    @Test func backgroundDetectedUpdateInstallsOnClick() {
        let model = UpdateStateModel()
        model.recordDetectedUpdate(makeItem("0.64.26"))

        #expect(model.pillPrimaryAction == .installLatest)
    }

    /// Sparkle staged the update and asked cmux to quit, but cmux is still running. The pill
    /// must name the restart it is waiting for, not claim an install is in progress.
    @Test func stagedUpdateRestartsOnClickAndSaysSo() {
        let model = UpdateStateModel()
        model.setState(.installing(.init(retryTerminatingApplication: {}, dismiss: {})))

        #expect(model.pillPrimaryAction == .restart)
        #expect(model.text == "Update Ready")
    }

    /// A relaunch held for a risky agent still needs the user's answer, so the click opens
    /// the popover with that question.
    @Test func heldRelaunchOpensPopover() {
        let model = UpdateStateModel()
        let risky = UpdateRelaunchAgent(id: "a", name: "Claude Code", location: "w", safety: .risky, activity: "Bash")
        model.setState(.installing(.init(
            retryTerminatingApplication: {},
            dismiss: {},
            relaunchBlockers: UpdateRelaunchBlockers(agents: [risky], runningCommandCount: 0),
            updateWhenClear: {}
        )))

        #expect(model.pillPrimaryAction == .togglePopover)
    }

    @Test func progressAndErrorStatesStillOpenPopover() {
        let model = UpdateStateModel()
        model.setState(.downloading(.init(cancel: {}, expectedLength: 100, progress: 10)))
        #expect(model.pillPrimaryAction == .togglePopover)

        model.setState(.notFound(.init(acknowledgement: {})))
        #expect(model.pillPrimaryAction == .acknowledgeNotFound)
    }
}

@MainActor
@Suite struct UpdatePillBadgeTests {
    @Test func stagedUpdatePillIsTextOnly() {
        let model = UpdateStateModel()
        model.setState(.installing(.init(retryTerminatingApplication: {}, dismiss: {})))
        #expect(!model.showsBadge)

        model.setState(.downloading(.init(cancel: {}, expectedLength: 100, progress: 10)))
        #expect(model.showsBadge)
    }
}
