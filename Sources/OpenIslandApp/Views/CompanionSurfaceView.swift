import AppKit
import OpenIslandCore
import SwiftUI

// MARK: - Geometry

/// The destination surface's measurements, separated from its drawing.
///
/// Round 1's creature was 58 × 54pt inside a 211pt scene and nothing in the
/// codebase said so — the number was a consequence of five layout constants and
/// could only be found by rendering. The whole failure was a size, and a size is
/// exactly the kind of claim a test can hold. So the geometry is a value here,
/// and `CompanionSurfaceTests` asserts the share rather than trusting it.
enum CompanionSurfaceLayout {
    /// Landscape, because the subject is a tall figure and the record beside it
    /// is a narrow column: stacking them would either shorten the companion or
    /// push the record off the bottom of a window nobody scrolls.
    static let defaultSize = CGSize(width: 880, height: 620)
    /// Not the width at which the paper stops fitting — that is 348 — but the
    /// width at which the *stage* stops being wide enough for the widest body to
    /// be as tall as the frame allows. At 760 the two broadest codex frames go
    /// width-limited by about 10pt, which is round 1's failure in miniature: the
    /// subject bounded by something other than its frame.
    /// `theFrameAndNotTheColumnIsWhatBoundsTheCompanion` holds this line.
    static let minimumSize = CGSize(width: 800, height: 520)

    /// Fixed rather than proportional. The paper does not reflow — `Receipt`
    /// caps it at 300pt — so every point given to this column past what the
    /// paper needs is a point taken from the companion for nothing.
    static let recordWidth: CGFloat = 348
    static let recordPadding: CGFloat = 24

    static let stageHorizontalPadding: CGFloat = 30
    /// Sky left above the companion's head, as a fraction of the stage's height.
    ///
    /// A fraction rather than a constant so the share below holds at every
    /// window size — a fixed inset would make the companion shrink faster than
    /// the window and reproduce round 1's actual failure, which was a subject
    /// that did not scale with its frame.
    static let skyHeadroomFraction: CGFloat = 0.14
    /// Where the ground meets the sky, as a fraction of the stage's height.
    static let horizonFraction: CGFloat = 0.78
    /// How far the companion's feet stand *into* the meadow rather than on the
    /// horizon line. Round 1's note that the creature reads as a sticker is
    /// partly this: a figure whose baseline is exactly a colour boundary looks
    /// pasted onto the boundary.
    static let groundBite: CGFloat = 14
    /// The state line and the day's runtime, printed on the ground band.
    static let captionHeight: CGFloat = 40

    /// The band the paper is centred in.
    ///
    /// `Receipt` caps the slip at `maximumPaperWidth` and insets it, so this is
    /// the width that makes the cap the binding constraint — anything narrower
    /// and the paper shrinks instead of the column.
    static let receiptBandWidth = recordWidth - recordPadding * 2 + Receipt.horizontalInset * 2

    static func stageSize(in window: CGSize) -> CGSize {
        CGSize(width: max(0, window.width - recordWidth), height: window.height)
    }

    static func horizon(inStage stage: CGSize) -> CGFloat {
        stage.height * horizonFraction
    }

    /// The box the sprite is fitted into. Its bottom edge is just below the
    /// horizon, so the companion stands in the meadow rather than on the line.
    static func companionBox(inStage stage: CGSize) -> CGSize {
        CGSize(
            width: max(0, stage.width - stageHorizontalPadding * 2),
            height: max(0, horizon(inStage: stage) + groundBite - stage.height * skyHeadroomFraction)
        )
    }

    /// What `aspectRatio(contentMode: .fit)` actually draws.
    ///
    /// Sprites are trimmed to their content, so the aspect varies by species and
    /// pose and one axis is always slack — which is precisely how round 1 ended
    /// up reporting a creature "budget" that no drawing ever filled. The share
    /// that matters is the share of the *drawn* box, and that needs the aspect.
    static func drawnSize(aspect: CGFloat, in box: CGSize) -> CGSize {
        guard aspect > 0, box.width > 0, box.height > 0 else { return .zero }
        let widthLimited = CGSize(width: box.width, height: box.width / aspect)
        return widthLimited.height <= box.height
            ? widthLimited
            : CGSize(width: box.height * aspect, height: box.height)
    }

    /// The companion's height as a fraction of the window's, which is the
    /// measurement round 1 failed: 54pt of creature in a 211pt scene is 26%.
    static func heightShare(aspect: CGFloat, in window: CGSize) -> CGFloat {
        guard window.height > 0 else { return 0 }
        let box = companionBox(inStage: stageSize(in: window))
        return drawnSize(aspect: aspect, in: box).height / window.height
    }

    /// Every sprite ships 192px tall, trimmed, so the aspect is the width alone.
    /// Read off the loaded image rather than tabulated, because a re-export that
    /// changed a trim would otherwise silently invalidate every measurement here.
    @MainActor
    static func aspect(of frameName: String) -> CGFloat {
        guard let image = CreatureSprite.image(named: frameName), image.size.height > 0 else {
            // The fallback silhouette fills its box, so it has the box's aspect.
            return 1
        }
        return image.size.width / image.size.height
    }
}

// MARK: - Vocabulary

/// Localization keys, kept out of the view bodies for the same reason
/// `CreaturePose.spokenStateKey` is: a test can then assert that four states map
/// to four distinct keys without depending on what any locale translates them
/// to, and without having to be `@MainActor` to ask.
extension CompanionState {
    var captionKey: String { "companion.state.\(rawValue)" }
}

extension RewardObject {
    var nameKey: String { "reward.object.\(rawValue)" }
}

extension RewardRarity {
    /// What this tier asks of you, in words. Stars alone say a lantern is rarer
    /// than a coin; they do not say why, and why is the only thing that makes
    /// the shelf worth reading twice.
    ///
    /// `four` borrows `three`'s pool and its caption with it — it is unreachable
    /// and shelves nothing of its own, so a fourth line would describe a row
    /// that is never drawn.
    var shelfCaptionKey: String {
        switch self {
        case .one: "companion.tier.one"
        case .two: "companion.tier.two"
        case .three, .four: "companion.tier.three"
        }
    }
}

// MARK: - Ground

/// The surface's two grounds and the marks that sit on them.
///
/// `STYLE-SPEC.md` §11.4 is explicit that the destination surface does not
/// inherit the pill's derivation: those values are dark because they were
/// scaled to clear 3:1 against near-black, and applying them to a surface that
/// is not near-black costs all the colour and buys nothing. The stage colours
/// are therefore the spec's scene palette at face value, on which the `#211e12`
/// line the sprites are drawn with measures 10.82:1.
///
/// **Every text colour here is a colour, not an opacity.** That is the same
/// argument `IslandDesignPalette.Paper` makes and for the same reason: a
/// transparency reads as "a bit quieter" and is in fact an unmeasured blend
/// with whatever is behind it. The first draft of this surface set its secondary
/// text with `.opacity(0.42)` over near-black and `.opacity(0.6)` over the
/// meadow, which measure 3.57:1 and 3.80:1 — under the 4.5:1 bar the receipt
/// beside them is held to. Derived to a target luminance instead, the property
/// holds by construction and `CompanionContrastTests` checks it.
enum CompanionPalette {
    /// Contrast floor for body text and anything smaller, which is everything
    /// on this surface.
    static let bodyTextContrast = 4.5

    enum Stage {
        static let skyHigh = CreatureColor(red: 0x7B, green: 0xC9, blue: 0xA4)
        static let skyLow = CreatureColor(red: 0xA6, green: 0xDB, blue: 0xB0)
        static let hill = CreatureColor(red: 0x97, green: 0xB7, blue: 0x6A)
        /// The meadow, and the ground every mark on the stage is measured
        /// against. The sky is lighter than it everywhere, so clearing the
        /// meadow clears the whole stage.
        static let ground = CreatureColor(red: 0xB4, green: 0xDE, blue: 0x6F)

        /// The spec's line work, unmodified: 10.8:1 on the meadow.
        static let ink = CreatureColor(red: 0x21, green: 0x1E, blue: 0x12)
        /// The same ink lifted until it recedes without dropping under the bar.
        static let quietInk = ink.scaledToLuminance(0.086)

        static var skyHighColor: Color { Color(skyHigh) }
        static var skyLowColor: Color { Color(skyLow) }
        static var hillColor: Color { Color(hill) }
        static var groundColor: Color { Color(ground) }
        static var inkColor: Color { Color(ink) }
        static var quietInkColor: Color { Color(quietInk) }
    }

    enum Record {
        /// The panel's ink, which is what the receipt was drawn to lie on.
        static let ground = CreatureColor(red: 0x0D, green: 0x0D, blue: 0x0F)
        /// The panel's cream, which is what everything written on it is made of.
        static let stock = CreatureColor(red: 0xF1, green: 0xEA, blue: 0xD9)

        /// Three weights, all above the bar. The lowest is the one that decides
        /// the ladder — 4.5:1 against this ground needs a luminance of 0.193, so
        /// there is no room below `quiet` for a fourth.
        static let strong = stock.scaledToLuminance(0.50)
        static let body = stock.scaledToLuminance(0.30)
        static let quiet = stock.scaledToLuminance(0.21)

        static var groundColor: Color { Color(ground) }
        static var stockColor: Color { Color(stock) }
        static var strongColor: Color { Color(strong) }
        static var bodyColor: Color { Color(body) }
        static var quietColor: Color { Color(quiet) }
    }
}

// MARK: - Surface

/// The companion's own place.
///
/// A window, not a tab and not a sheet, and the reasoning is the panel's rather
/// than taste. The overlay panel dismisses on pointer exit and its width is
/// bound to the notch — a surface you are meant to linger on cannot live inside
/// something that closes when your mouse leaves, which rules out both a sheet on
/// it and any expansion of it. Settings is the other window this app has, and it
/// is a preferences window: a printed record of your day and a shelf of things
/// you have found are not preferences, and filing them there is the third
/// version of the mistake this whole round exists to undo — a destination put
/// inside a tool. Menu-bar utilities usually do have exactly one settings window
/// and nothing else; this app is one of the few with something worth visiting.
struct CompanionSurfaceView: View {
    var model: AppModel

    private var records: [SessionLogRecord] { model.sessionLogRecords }

    var body: some View {
        // Read once per render pass so the stage's runtime and the receipt's
        // date describe the same instant. Two `Date()` calls in one body is how
        // a surface opened at 23:59:59.9 prints one day on the paper and counts
        // the other in the caption.
        let now = Date()

        GeometryReader { proxy in
            let stage = CompanionSurfaceLayout.stageSize(in: proxy.size)
            HStack(spacing: 0) {
                CompanionStageView(
                    species: CompanionIdentity.species(for: records),
                    state: CompanionState(sessions: model.sessions, geode: model.geodeState),
                    runtimeToday: SessionStats.summary(
                        for: Receipt.range,
                        records: records,
                        now: now
                    ).totalRuntime,
                    size: stage,
                    lang: model.lang
                )
                .frame(width: stage.width)

                CompanionRecordColumn(records: records, now: now, lang: model.lang)
                    .frame(width: CompanionSurfaceLayout.recordWidth)
            }
        }
        .frame(
            minWidth: CompanionSurfaceLayout.minimumSize.width,
            minHeight: CompanionSurfaceLayout.minimumSize.height
        )
    }
}

// MARK: - Stage

/// Sky, ground, and the companion standing on the line between them.
///
/// Deliberately three elements. Grounding the sprite properly — contact shadow,
/// edge treatment, picking up the surrounding surface — is its own task and its
/// own contrast gate; standing the figure on a horizon is layout, and layout is
/// what stops it reading as a sticker pasted at the centre of a rectangle.
struct CompanionStageView: View {
    let species: CreatureSpecies
    let state: CompanionState
    let runtimeToday: TimeInterval
    let size: CGSize
    let lang: LanguageManager

    /// Below this the day has not really started, and "less than a minute
    /// worked today" is a stranger thing to print than nothing.
    static let runtimeFloor: TimeInterval = 60

    /// How far the distant rise breaks the horizon, as a fraction of it. Small
    /// on purpose: any more and the crest stops being a rise behind the meadow
    /// and becomes a third flat stripe across the window.
    static let crestFraction: CGFloat = 0.09

    private var stateText: String { lang.t(state.captionKey) }

    private var runtimeText: String? {
        guard runtimeToday >= Self.runtimeFloor else { return nil }
        return lang.t("companion.runtime.today", IslandDurationGrain(seconds: runtimeToday).spoken(lang))
    }

    private var box: CGSize { CompanionSurfaceLayout.companionBox(inStage: size) }

    var body: some View {
        let horizon = CompanionSurfaceLayout.horizon(inStage: size)

        ZStack(alignment: .top) {
            ground(horizon: horizon)
            companion
                .padding(.top, size.height * CompanionSurfaceLayout.skyHeadroomFraction)
            caption(horizon: horizon)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        // The stage is the light half and the record is the dark one; a hairline
        // keeps the join reading as an edge rather than as a rendering seam.
        .overlay(alignment: .trailing) {
            Rectangle().fill(.black.opacity(0.2)).frame(width: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([stateText, runtimeText].compactMap { $0 }.joined(separator: ", "))
    }

    /// Sky, one distant rise, meadow.
    ///
    /// The rise is drawn *between* them and mostly hidden by the meadow, so only
    /// its crest shows: an ellipse sitting on top of the horizon would be a
    /// mound behind the figure, and a landscape is what the crest makes of it.
    private func ground(horizon: CGFloat) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [CompanionPalette.Stage.skyHighColor, CompanionPalette.Stage.skyLowColor],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .fill(CompanionPalette.Stage.hillColor)
                .frame(width: size.width * 1.25, height: horizon * 0.5)
                .offset(y: horizon - horizon * Self.crestFraction)

            VStack(spacing: 0) {
                Color.clear.frame(height: horizon)
                CompanionPalette.Stage.groundColor
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var companion: some View {
        CreatureView(
            species: species,
            state: state,
            seed: ShardSeed.value(for: species.rawValue),
            size: box,
            alignment: .bottom
        )
    }

    /// Centred in the meadow, not pinned to the window's bottom edge — the band
    /// below the companion's feet is where a caption belongs, and pushing it
    /// further leaves a slab of empty green between the two.
    private func caption(horizon: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(stateText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CompanionPalette.Stage.inkColor)

            if let runtimeText {
                Text(runtimeText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CompanionPalette.Stage.quietInkColor)
            }
        }
        .frame(width: size.width, height: CompanionSurfaceLayout.captionHeight)
        .offset(y: horizon + (size.height - horizon - CompanionSurfaceLayout.captionHeight) / 2
            + CompanionSurfaceLayout.groundBite / 2)
    }
}

// MARK: - Record

/// Everything the day and the log account for, in one quiet column.
///
/// Dark, because the receipt is cream stock and was drawn to lie on the panel's
/// ink — and because the stage next to it must stay the loud half. The column
/// scrolls; the stage never does.
struct CompanionRecordColumn: View {
    let records: [SessionLogRecord]
    let now: Date
    let lang: LanguageManager

    var body: some View {
        ScrollView {
            CompanionRecordContent(records: records, now: now, lang: lang)
        }
        .background(CompanionPalette.Record.groundColor)
    }
}

/// The column's contents, one level out of the `ScrollView`.
///
/// Separated so it can be rendered and looked at: `ImageRenderer` produces an
/// empty frame for anything inside a `ScrollView`, which is how the first render
/// of this surface came back with a blank black column and nothing to say
/// whether the receipt and the shelf were laid out or missing.
struct CompanionRecordContent: View {
    let records: [SessionLogRecord]
    let now: Date
    let lang: LanguageManager

    private var collection: RewardCollection { RewardCollection(records: records) }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            receiptBlock
            RewardCollectionView(collection: collection, lang: lang)
        }
        .padding(CompanionSurfaceLayout.recordPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day, printed.
    ///
    /// No range control anywhere on this surface, which is the whole of what the
    /// Stats pane's `range == .today` gate was protecting: `Receipt` is wired to
    /// `Receipt.range` and cannot describe anything else, so the only way it
    /// contradicts a neighbour is if a neighbour is scoped differently. Nothing
    /// here is — the collection beside it is labelled all-time in words, and the
    /// paper carries its own date in its header.
    private var receiptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: lang.t("settings.stats.receipt"))

            ReceiptView(
                receipt: Receipt(
                    records: records,
                    now: now,
                    width: CompanionSurfaceLayout.receiptBandWidth,
                    lang: lang
                )
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct SectionHeading: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(CompanionPalette.Record.strongColor)

            Spacer(minLength: 4)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanionPalette.Record.quietColor)
            }
        }
    }
}

// MARK: - Collection

/// What the log says has been found, and what has not.
///
/// `RewardCollection` has been computing this since round 1 and no surface has
/// ever drawn it, so every object earned so far has accumulated somewhere the
/// user cannot look. Laid out by tier rather than in enum order, because the
/// tiers are the only reason one object is scarcer than another and a flat grid
/// of twelve would hide that.
struct RewardCollectionView: View {
    let collection: RewardCollection
    let lang: LanguageManager

    /// Everything but scrap. Scrap is what an interrupt leaves and is in no
    /// tier's pool — printing it as a thirteenth collectible would make an
    /// abandoned session look like a find.
    static let shelved: [RewardObject] = RewardRarity.distinctPools.flatMap(RewardObject.pool(for:))

    private var tally: [RewardObject: Int] { collection.tally }
    private var foundCount: Int { Self.shelved.filter { (tally[$0] ?? 0) > 0 }.count }
    private var scrapCount: Int { tally[.scrap] ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: lang.t("companion.collection.title"),
                trailing: lang.t("companion.collection.allTime")
            )

            Text(lang.t("companion.collection.found", foundCount, Self.shelved.count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CompanionPalette.Record.bodyColor)

            ForEach(RewardRarity.distinctPools, id: \.rawValue) { tier in
                tierRow(tier)
            }

            if foundCount == 0, scrapCount == 0 {
                Text(lang.t("companion.collection.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionPalette.Record.quietColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            scrapRow
        }
    }

    private func tierRow(_ tier: RewardRarity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(String(repeating: "★", count: tier.rawValue))
                    .font(.system(size: 10))
                    .foregroundStyle(CompanionPalette.Record.bodyColor)
                Text(lang.t(tier.shelfCaptionKey))
                    .font(.system(size: 10.5))
                    .foregroundStyle(CompanionPalette.Record.quietColor)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(RewardObject.pool(for: tier), id: \.rawValue) { object in
                    RewardObjectTile(object: object, count: tally[object] ?? 0, lang: lang)
                }
            }
        }
    }

    /// Printed below the shelf and never on it. An interrupt is the absence of a
    /// reward, and this is the count of them the log accounts for.
    private var scrapRow: some View {
        HStack(spacing: 8) {
            RewardObjectTile(object: .scrap, count: scrapCount, lang: lang, size: 34)
            Text(lang.t("companion.collection.scrap"))
                .font(.system(size: 10.5))
                .foregroundStyle(CompanionPalette.Record.quietColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// One thing, found or not.
struct RewardObjectTile: View {
    let object: RewardObject
    let count: Int
    let lang: LanguageManager
    var size: CGFloat = 46

    private var isFound: Bool { count > 0 }
    private var name: String { lang.t(object.nameKey) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                artwork
                    .frame(width: size, height: size)

                // Shown from the first find, not the second: a badge that
                // appears only at two would leave "found once" and "never
                // found" separated by nothing but colour.
                if isFound {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanionPalette.Record.groundColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(CompanionPalette.Record.stockColor, in: Capsule())
                        .offset(x: 3, y: 2)
                }
            }

            if size >= 40 {
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(isFound ? CompanionPalette.Record.strongColor : CompanionPalette.Record.quietColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: size + 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isFound
                ? "\(name), \(count)"
                : "\(name), \(lang.t("companion.collection.locked"))"
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = CreatureSprite.image(named: CreatureSprite.name(for: object)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                // A found object is itself; an unfound one is the same shape
                // with the colour taken out, so the shelf shows what is missing
                // rather than hiding it behind a question mark.
                .grayscale(isFound ? 0 : 1)
                .opacity(isFound ? 1 : 0.22)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(CompanionPalette.Record.quietColor.opacity(0.18))
        }
    }
}
