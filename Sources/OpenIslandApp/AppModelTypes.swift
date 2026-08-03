import AppKit
import CoreGraphics
import Foundation
import OpenIslandCore

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

// MARK: - v6 island preferences

/// What the closed island renders in the right slot. Chosen in the
/// Personalization tab; the pill layout only varies by content width.
enum IslandRightSlot: String, CaseIterable, Identifiable, Sendable {
    case count   // "×N" badge
    case agents  // colored dot stack, one per active agent tool
    case geode    // procedural shard for the featured session, grows as it runs
    case creature // drawn creature for the featured session; pose carries state
    case none     // pill collapses — useful if you just want the bars

    var id: String { rawValue }

    /// Slots that render the featured session's shard state.
    ///
    /// Sound cues and the growth ticker both gate on this. They used to test
    /// `== .geode` by equality, which meant any new shard-rendering slot shipped
    /// silent and frozen with no error anywhere — so the predicate is named once
    /// here rather than repeated at each call site.
    var rendersShard: Bool {
        self == .geode || self == .creature
    }
}

/// What the closed island renders in the center label (external displays
/// only — on MacBook the physical notch covers this space so we suppress
/// the label regardless).
enum IslandCenterLabel: String, CaseIterable, Identifiable, Sendable {
    case sessionName  // e.g. "open-island"
    case agentAction  // e.g. "Claude · editing"
    case off

    var id: String { rawValue }
}

// MARK: - v8 island preferences

enum IslandAppearanceDisplayProfile: String, CaseIterable, Identifiable, Sendable {
    case notch
    case topBar

    var id: String { rawValue }
}

struct IslandAppearancePreferences: Equatable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var centerLabel: IslandCenterLabel = .agentAction
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes
    var scene: IslandSceneVisibility = .off
    var sceneHeight: IslandSceneHeight = .standard
}

/// Whether the opened panel draws the island above its session list.
///
/// Off by default, and deliberately independent of `rightSlot`: that preference
/// governs the *closed pill's* right slot, and someone who picked a creature
/// there did not thereby ask for a landscape in their panel. Gating one on the
/// other would also mean this preference shipping `off` silently withdrew a
/// pill creature an existing user had already opted into.
enum IslandSceneVisibility: String, CaseIterable, Identifiable, Sendable {
    case off
    case on

    var id: String { rawValue }

    var isVisible: Bool { self == .on }
}

/// How much island you get.
///
/// A multiplier on the scene's natural 3.6:1 band rather than a set of point
/// values, so the three options stay correct at both panel widths — 540pt on a
/// notch Mac and 520 on an external display — instead of encoding one and being
/// wrong on the other.
///
/// This changes the *panel's* height, not the scene's share of a fixed one. The
/// panel's height is computed from its session list (`OverlayPanelController.`
/// `openedContentHeight`) and then hard-clipped, so a band that took its height
/// out of the existing budget would make a taller island silently show fewer
/// sessions. Growing the window instead keeps the list whole and makes the
/// preference mean what it says.
enum IslandSceneHeight: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case tall

    var id: String { rawValue }

    /// Multiplier on `IslandSceneLayout.bandAspect`'s natural height.
    ///
    /// `standard` is 1 so the shipped artwork is drawn at the aspect it was cut
    /// at. The other two crop or reveal sky — the background is drawn `.fill`
    /// and bottom-anchored, so the ground line the creatures stand on never
    /// moves and the horizon is never stretched.
    var scale: CGFloat {
        switch self {
        case .compact: 0.74
        case .standard: 1
        case .tall: 1.26
        }
    }
}

enum IslandUsageDisplay: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case compact

    var id: String { rawValue }
}

enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }

    func timelineInterval(presence: IslandSessionPresence, isActionable: Bool) -> TimeInterval? {
        guard self == .animatedDot else { return nil }
        return presence == .running || isActionable ? 1.0 / 15.0 : nil
    }
}

enum IslandSessionGroup: String, CaseIterable, Identifiable, Sendable {
    case none
    case state
    case agent
    case project

    var id: String { rawValue }
}

enum IslandSessionSort: String, CaseIterable, Identifiable, Sendable {
    case attention
    case lastUpdate

    var id: String { rawValue }
}

enum IslandCompletedStaleThreshold: String, CaseIterable, Identifiable, Sendable {
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case twentyMinutes
    case never

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .twoMinutes:    return 2 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .twentyMinutes: return 20 * 60
        case .never:         return .infinity
        }
    }
}

struct IslandSessionSection: Identifiable {
    let id: String
    let title: String
    let sessions: [AgentSession]
}
