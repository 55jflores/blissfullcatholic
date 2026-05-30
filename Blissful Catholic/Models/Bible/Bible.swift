//
//  Bible.swift
//  Blissful Catholic
//
//  The bundled WEBCE (World English Bible, Catholic Edition — public domain)
//  models. The JSON is generated from the eBible.org USFM source by the web
//  repo's scripts/build-webce-json.mjs.
//
//  The `Bible` type matches the JSON shape on disk (loaded once by BibleService).
//  `BibleReference` and `BibleVerse` are the runtime types views work with.
//

import Foundation

// MARK: - On-disk model (Decodable, matches webce.json)
//
// Marked `nonisolated` because the target is compiled with default-isolation
// MainActor. Without it, the synthesized Decodable conformance would be
// inferred as @MainActor and could not be used from BibleService's detached
// background-priority load task.

nonisolated struct Bible: Decodable {
    let translation: String          // "WEB-CE"
    let name: String                 // "World English Bible (Catholic Edition)"
    let license: String              // "Public Domain"
    let books: [BibleBook]
}

nonisolated struct BibleBook: Decodable {
    let code: String                 // USFM code: "GEN", "JHN", "1PE", "SIR", …
    let name: String                 // "Genesis", "John", "1 Peter", "Sirach", …
    /// chapter (as a string-keyed Int) → verse (string-keyed Int) → text.
    /// JSON keys are always strings; we treat them as integers via lookup.
    let chapters: [String: [String: String]]
}

// MARK: - Runtime types

/// A structured Bible reference. Spans one or more verses, possibly across
/// chapters (e.g., "1 Cor 12:31—13:13").
nonisolated struct BibleReference: Hashable, Sendable {
    let book: String                 // USFM code
    let startChapter: Int
    let startVerse: Int
    let endChapter: Int              // may equal startChapter
    let endVerse: Int                // may equal startVerse; Int.max = "to end of chapter"

    var spansChapters: Bool { startChapter != endChapter }

    /// Human-readable rendering, e.g. "Acts 18:9–18" or "1 Cor 12:31–13:13".
    /// (We don't display this — citations come from the upstream readings API
    /// already formatted — but it's useful in debug/logging.)
    var displayString: String {
        if startChapter == endChapter && startVerse == endVerse {
            return "\(book) \(startChapter):\(startVerse)"
        }
        if startChapter == endChapter {
            return "\(book) \(startChapter):\(startVerse)–\(endVerse)"
        }
        return "\(book) \(startChapter):\(startVerse)–\(endChapter):\(endVerse)"
    }
}

/// A single verse for display.
nonisolated struct BibleVerse: Identifiable, Hashable, Sendable {
    let book: String                 // USFM code
    let chapter: Int
    let verse: Int
    let text: String

    var id: String { "\(book)-\(chapter)-\(verse)" }
}
