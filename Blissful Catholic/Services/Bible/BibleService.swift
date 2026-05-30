//
//  BibleService.swift
//  Blissful Catholic
//
//  Lazy-loads the bundled WEBCE JSON and resolves citations into verses.
//
//  Two surfaces:
//   - `verses(forCitation:)` / `verses(for:)`  — what today's reading screen needs.
//   - `chapter(book:chapter:)` / `books()`     — what the future Bible reader needs.
//
//  Loading the ~5 MB JSON happens on a background priority task and is cached for
//  the app's lifetime; subsequent calls are instant.
//

import Foundation

@MainActor
@Observable
final class BibleService {
    static let shared = BibleService()

    private(set) var isLoaded = false
    private var bible: Bible?
    private var loadTask: Task<Bible?, Never>?

    private init() {}

    // MARK: - Public API

    /// Parse a citation string ("Acts 18:9–18", "1 Cor 12:31—13:13", "Sir 24:1–22").
    /// Pure — no async needed.
    nonisolated func parse(_ citation: String) -> [BibleReference] {
        CitationParser.parse(citation)
    }

    /// Resolve a single structured reference into its verses.
    func verses(for ref: BibleReference) async -> [BibleVerse] {
        guard let bible = await loadIfNeeded() else { return [] }
        return resolve(ref, in: bible)
    }

    /// Parse + resolve in one call. Handles disjoint citations like
    /// "Ps 23:1, 3-5" by concatenating each part's verses in order.
    func verses(forCitation citation: String) async -> [BibleVerse] {
        let refs = parse(citation)
        guard !refs.isEmpty, let bible = await loadIfNeeded() else { return [] }
        return refs.flatMap { resolve($0, in: bible) }
    }

    /// All of a chapter — primitive for the (future) Bible reader.
    func chapter(book: String, chapter: Int) async -> [BibleVerse] {
        let ref = BibleReference(
            book: book,
            startChapter: chapter, startVerse: 1,
            endChapter: chapter, endVerse: Int.max
        )
        return await verses(for: ref)
    }

    /// Book metadata for navigation UIs (code, display name, chapter count).
    func books() async -> [(code: String, name: String, chapterCount: Int)] {
        guard let bible = await loadIfNeeded() else { return [] }
        return bible.books.map { ($0.code, $0.name, $0.chapters.count) }
    }

    // MARK: - Loading

    /// Loads the bundled JSON on the first call; cached thereafter. Concurrent
    /// callers coalesce onto the same task because this method is @MainActor —
    /// any second caller sees `loadTask` already set.
    private func loadIfNeeded() async -> Bible? {
        if let bible { return bible }
        if let loadTask { return await loadTask.value }

        let task = Task.detached(priority: .utility) { Self.loadFromBundle() }
        loadTask = task
        let result = await task.value
        bible = result
        isLoaded = (result != nil)
        loadTask = nil
        return result
    }

    nonisolated private static func loadFromBundle() -> Bible? {
        guard let url = Bundle.main.url(forResource: "webce", withExtension: "json") else {
            assertionFailure("webce.json missing from bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try JSONDecoder().decode(Bible.self, from: data)
        } catch {
            assertionFailure("Failed to load webce.json: \(error)")
            return nil
        }
    }

    // MARK: - Resolver

    /// Walk a reference's chapter range and collect verses in order.
    /// `endVerse == .max` means "to the end of the chapter" (whole-chapter refs).
    private func resolve(_ ref: BibleReference, in bible: Bible) -> [BibleVerse] {
        guard let book = bible.books.first(where: { $0.code == ref.book }) else { return [] }

        // Clamp endChapter to what actually exists, so a reference like "Ps 23"
        // doesn't try to walk to Int.max.
        let lastChap = book.chapters.keys.compactMap(Int.init).max() ?? ref.endChapter
        let endChap = min(ref.endChapter, lastChap)
        guard ref.startChapter <= endChap else { return [] }

        var result: [BibleVerse] = []
        for chap in ref.startChapter...endChap {
            guard let verses = book.chapters[String(chap)] else { continue }
            let verseNums = verses.keys.compactMap(Int.init).sorted()
            let startV = (chap == ref.startChapter) ? ref.startVerse : 1
            let endV = (chap == ref.endChapter) ? ref.endVerse : Int.max
            for vn in verseNums where vn >= startV && vn <= endV {
                if let text = verses[String(vn)] {
                    result.append(BibleVerse(book: ref.book, chapter: chap, verse: vn, text: text))
                }
            }
        }
        return result
    }
}
