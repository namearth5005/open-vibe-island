import Foundation

/// The companion's resting pose. The pose IS the status readout -- if it did
/// not encode session state it would be decoration sitting beside a separate
/// status display, paying attention-rent for no information.
///
/// There is deliberately no `completed` case. Completion is a transient beat,
/// after which the companion settles into whichever resting pose the remaining
/// sessions call for. A pose that lingered would show a stale fact.
enum CompanionPose: String, CaseIterable, Sendable {
    /// Nothing is running.
    case sleeping
    /// At least one session is working.
    case alert
    /// A session needs approval or an answer.
    case attending

    /// Base name of the still image in the Companion resource directory.
    var assetName: String { "companion-\(rawValue)" }
}

/// Motion policy, separated from the view so it can be tested without SwiftUI.
enum CompanionMotion {
    /// Reduce-motion is honoured unconditionally -- it is an accessibility
    /// setting, not a preference to weigh against aesthetics.
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}
