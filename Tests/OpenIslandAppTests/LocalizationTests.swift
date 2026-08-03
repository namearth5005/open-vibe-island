import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// The app ships English, Simplified Chinese and Traditional Chinese.
///
/// `LanguageManager.t(_:)` looks a key up with `value: key`, so a key that is
/// missing from a locale renders as the raw key — `island.pose.waiting` appears
/// on screen, in a shipping build, with nothing anywhere reporting it. The lint
/// step only runs `plutil` for syntax and cannot see this at all, which is how
/// sixteen keys reached `main` translated into two locales out of three.
///
/// These tests are the missing check.
struct LocalizationTests {
    private static let locales: [LanguageManager.AppLanguage] = [.en, .zhHans, .zhHant]

    /// Read from the built bundle rather than by parsing the source files, so
    /// what is asserted is what a running app would actually resolve.
    private static func keys(for language: LanguageManager.AppLanguage) throws -> Set<String> {
        let code = language.resolvedCode
        let path = try #require(
            [code, code.lowercased()].lazy
                .compactMap { Bundle.appResources.path(forResource: $0, ofType: "lproj") }
                .first,
            "no .lproj for \(code)"
        )
        let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        let table = try #require(
            NSDictionary(contentsOf: url) as? [String: String],
            "unreadable strings table at \(url.path)"
        )
        return Set(table.keys)
    }

    /// Every locale defines every key.
    ///
    /// Written as a set difference rather than a count so a failure names the
    /// keys that are missing instead of only saying that some are.
    @Test
    func everyLocaleDefinesTheSameKeys() throws {
        let english = try Self.keys(for: .en)

        for locale in Self.locales.dropFirst() {
            let translated = try Self.keys(for: locale)

            let missing = english.subtracting(translated).sorted()
            #expect(missing.isEmpty, "\(locale.rawValue) is missing: \(missing.joined(separator: ", "))")

            let extra = translated.subtracting(english).sorted()
            #expect(extra.isEmpty, "\(locale.rawValue) defines keys English does not: \(extra.joined(separator: ", "))")
        }
    }

    /// A key that resolves to itself is a key nobody translated. This is the
    /// same claim as above, made through the API the app actually calls, so it
    /// also covers bundle resolution going wrong rather than only the files.
    @Test
    func everyIslandStringResolvesInEveryLocale() throws {
        var keys = Set<String>()
        keys.formUnion(CreaturePose.allCases.map(\.spokenStateKey))
        keys.formUnion(ReceiptItem.allCases.map(\.labelKey))
        keys.formUnion([
            IslandIdentityStripLayout.emptyMessageKey,
            IslandDetailBand.emptyMessageKey,
            Receipt.busyFooterKey,
            Receipt.emptyFooterKey,
            "island.unknownWorkspace",
            "island.unknownHost",
            "island.unknownHost.spoken",
            "island.strip.hint.jumps",
            "island.strip.hint.selects",
            "island.strip.spoken",
            "island.overflow.spoken.one",
            "island.overflow.spoken.many",
            "island.duration.underAMinute",
            "island.duration.minute",
            "island.duration.minutes",
            "island.duration.hour",
            "island.duration.hours",
            "island.duration.day",
            "island.duration.days",
            "island.detail.stalls.never",
            "island.detail.stalls.once",
            "island.detail.stalls.many",
            "island.detail.spoken.running",
            "island.detail.spoken.waiting",
            "receipt.note.unwatched",
            "receipt.note.asked",
            "receipt.spoken.none",
            "receipt.spoken.session",
            "receipt.spoken.sessions",
            "receipt.spoken.noneAsked",
            "receipt.spoken.answer",
            "receipt.spoken.answers",
            "receipt.spoken.even",
            "receipt.spoken.up",
            "receipt.spoken.down",
            "settings.stats.receipt",
            "settings.appearance.islandPart.title",
            "settings.appearance.islandScene.title",
            "settings.appearance.islandScene.note",
            "settings.appearance.islandScene.off",
            "settings.appearance.islandScene.on",
            "settings.appearance.sceneHeight.title",
            "settings.appearance.sceneHeight.note",
            "settings.appearance.sceneHeight.compact",
            "settings.appearance.sceneHeight.standard",
            "settings.appearance.sceneHeight.tall",
        ])

        for locale in Self.locales {
            let lang = LanguageManager(language: locale)
            for key in keys.sorted() {
                #expect(lang.t(key) != key, "\(key) is untranslated in \(locale.rawValue)")
            }
        }
    }

    /// Four poses, four keys. A collision would make two states of the island
    /// read identically to a screen-reader user, which is exactly the failure
    /// the pose vocabulary exists to prevent.
    @Test
    func everyPoseHasItsOwnKey() {
        let keys = CreaturePose.allCases.map(\.spokenStateKey)
        #expect(Set(keys).count == CreaturePose.allCases.count)
    }

    @Test
    func everyReceiptItemHasItsOwnKey() {
        let keys = ReceiptItem.allCases.map(\.labelKey)
        #expect(Set(keys).count == ReceiptItem.allCases.count)
    }

    /// A format string whose specifiers were dropped or retyped in translation
    /// throws at runtime or prints the wrong thing. Chinese may reorder the
    /// clauses — that is what positional specifiers are for — so this counts
    /// them rather than comparing the strings.
    @Test
    func formatStringsKeepTheirArgumentsInEveryLocale() throws {
        let arities: [String: Int] = [
            "island.strip.spoken": 5,
            "island.overflow.spoken.many": 1,
            "island.duration.minute": 1,
            "island.duration.minutes": 1,
            "island.duration.hour": 1,
            "island.duration.hours": 1,
            "island.duration.day": 1,
            "island.duration.days": 1,
            "island.detail.stalls.many": 1,
            "island.detail.spoken.running": 1,
            "island.detail.spoken.waiting": 1,
            "receipt.note.unwatched": 1,
            "receipt.note.asked": 1,
            "receipt.spoken.sessions": 1,
            "receipt.spoken.answer": 1,
            "receipt.spoken.answers": 1,
            "receipt.spoken.up": 1,
            "receipt.spoken.down": 1,
        ]

        for locale in Self.locales {
            let lang = LanguageManager(language: locale)
            for (key, expected) in arities.sorted(by: { $0.key < $1.key }) {
                let format = lang.t(key)
                // `%%` is an escaped percent and takes no argument; none of
                // these use one, but counting `%` alone would be wrong if one
                // ever did.
                let specifiers = format.components(separatedBy: "%").count - 1
                #expect(
                    specifiers == expected,
                    "\(key) in \(locale.rawValue) has \(specifiers) specifiers, expected \(expected): \(format)"
                )
            }
        }
    }

    /// The island band's user-visible text has to differ between English and
    /// Chinese, or the "translations" are English copied across.
    @Test
    func theIslandBandIsActuallyTranslated() {
        let english = LanguageManager(language: .en)
        let simplified = LanguageManager(language: .zhHans)

        for key in [
            IslandIdentityStripLayout.emptyMessageKey,
            IslandDetailBand.emptyMessageKey,
            "island.unknownHost",
            "island.unknownWorkspace",
            "island.pose.waiting",
        ] {
            #expect(english.t(key) != simplified.t(key), "\(key) reads the same in both")
        }
    }
}
