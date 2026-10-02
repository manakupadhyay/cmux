import AppKit

/// MEASUREMENT ONLY (throwaway branch measure-sidebar-launch-leo): reports
/// the first sidebar row views to the app's launch marks.
@MainActor
public enum SidebarLaunchProbe {
    /// Called with a mark name the first time a row of that kind gets a view.
    public static var mark: ((String) -> Void)?
    static var seen: Set<String> = []

    static func rowRealized(_ key: SidebarRowKey) {
        let name: String
        switch key {
        case .workspace: name = "sidebar.first_workspace_row_view"
        case .group: name = "sidebar.first_group_row_view"
        case .section: name = "sidebar.first_section_header_view"
        case .emptySection: name = "sidebar.first_empty_section_view"
        }
        guard seen.insert(name).inserted, let mark else { return }
        mark(name)
        // After this run loop turn's Core Animation commit (order after
        // CA's beforeWaiting observer): the frame that carries the row.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            MainActor.assumeIsolated { mark(name + "_committed") }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
