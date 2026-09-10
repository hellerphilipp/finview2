import Foundation
import Observation

/// Shared navigation state so any view can change the selected sidebar section
/// (e.g. a Dashboard button jumping to Review).
@Observable
final class AppRouter {
    var selection: SidebarItem?

    init() {
        if let raw = ProcessInfo.processInfo.environment["TALLY_VIEW"],
           let item = SidebarItem(rawValue: raw) {
            selection = item
        } else {
            selection = .dashboard
        }
    }
}
