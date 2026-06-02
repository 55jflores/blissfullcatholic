//
//  MonthlyDevotion.swift
//  Blissful Catholic
//
//  The Catholic tradition assigns a devotional focus to each month — the Holy
//  Name in January, the Sacred Heart in June, the Holy Rosary in October, and
//  so on. We surface these as a small monthly card in the Daily flow, with a
//  deep screen that explains the devotion and roots it in Church history.
//
//  Bundled as monthly-devotions.json; resolved by month number (1–12) in
//  MonthlyDevotionService. Twelve entries, one per month.
//

import Foundation

nonisolated struct MonthlyDevotion: Decodable, Hashable, Sendable, Identifiable {
    /// Month number (1 = January, 12 = December). Doubles as the natural ID
    /// and the lookup key against today's calendar month.
    let month: Int
    /// Stable kebab-case identifier, prefixed `devotion-` so it never collides
    /// with a saint key in the flattened bundle root (Xcode 16 synchronized
    /// groups put every resource at the bundle root — see SaintScreen.bundledArtwork).
    /// Doubles as the artwork filename (`{key}.jpg`).
    let key: String
    /// Display name (e.g. "The Sacred Heart of Jesus"). Shown as the card title
    /// and the deep screen's hero.
    let name: String
    /// One-line context shown beneath the name (e.g. "Traditional June Devotion").
    let subtitle: String
    /// Single-paragraph intro shown on the Daily card and at the top of the deep
    /// screen. Aim for two or three sentences.
    let intro: String
    /// Longer body for the deep screen. Paragraphs separated by `\n\n`. Includes
    /// the historical anchor (when the feast or devotion was established) and a
    /// short pastoral reflection on what the devotion offers a Catholic today.
    let reflection: String

    /// Public-domain Catholic artwork bundled at `Resources/devotion-art/{key}.jpg`.
    /// Reuses the `SaintArtwork` shape (artist · title · year · source) since the
    /// attribution fields are identical. Nil = no curated art yet; the deep
    /// screen falls back to the procedural `ArtPlate`.
    let artwork: SaintArtwork?

    var id: Int { month }
}

/// On-disk shape of `monthly-devotions.json` — versioned envelope so the
/// catalog can grow without breaking decode.
nonisolated struct MonthlyDevotionCatalog: Decodable {
    let version: Int
    let devotions: [MonthlyDevotion]
}
