import Foundation
import ActivityKit

/// The Live Activity that tracks today's class chain: it shows either the class
/// in progress (counting down to 下課) or the wait until the next class starts,
/// with a glance at what comes after.
///
/// The countdown itself is rendered with SwiftUI's timer text, so once started
/// the activity keeps ticking on the Lock Screen / Dynamic Island without the
/// app running. The app re-pushes a new `ContentState` at each class boundary
/// when it's foregrounded (or via a best-effort background refresh).
struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case inClass      // a class is happening now → count down to `pivot` (其下課時間)
            case beforeNext   // between/ before classes → count down to `pivot` (下一節上課時間)
            case done         // no more classes today
        }

        var phase: Phase
        /// Course currently relevant (the in-progress class, or the next one).
        var courseName: String
        var classroom: String
        /// The instant being counted down to (class end, or next class start).
        var pivot: Date
        /// A peek at the class after the current/next one, if any.
        var followingCourseName: String?
        var followingClassroom: String?
        var followingStart: Date?
    }

    /// Static label shown for the activity (e.g. the day).
    var title: String
}
