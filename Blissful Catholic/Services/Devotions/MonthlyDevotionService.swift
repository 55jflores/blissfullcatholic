//
//  MonthlyDevotionService.swift
//  Blissful Catholic
//
//  Lazy-loads bundled monthly-devotions.json and returns the devotion for a
//  given month. Same lazy-load pattern as SaintService and BibleService.
//
//  Twelve fixed entries — one per month — so resolution is trivial: clamp the
//  month into [1, 12] and look it up.
//

import Foundation

@MainActor
@Observable
final class MonthlyDevotionService {
    static let shared = MonthlyDevotionService()

    private(set) var isLoaded = false
    private var catalog: MonthlyDevotionCatalog?
    private var loadTask: Task<MonthlyDevotionCatalog?, Never>?

    private init() {}

    // MARK: - Public API

    /// Resolve the devotion for a given calendar month. `month` is 1-indexed
    /// (1 = January … 12 = December); the calling view should pass the month
    /// from `Calendar.current.component(.month, from: date)`. Nil only if the
    /// catalog failed to load — every month should have an entry.
    func devotion(forMonth month: Int) async -> MonthlyDevotion? {
        guard let catalog = await loadIfNeeded() else { return nil }
        return catalog.devotions.first { $0.month == month }
    }

    /// Convenience: resolve the devotion for the month of the given date.
    func devotion(for date: Date) async -> MonthlyDevotion? {
        let month = Calendar.current.component(.month, from: date)
        return await devotion(forMonth: month)
    }

    // MARK: - Loading

    /// Loads bundled `monthly-devotions.json` on the first call; cached
    /// thereafter. Concurrent callers coalesce onto the same task.
    private func loadIfNeeded() async -> MonthlyDevotionCatalog? {
        if let catalog { return catalog }
        if let loadTask { return await loadTask.value }

        let task = Task.detached(priority: .utility) { Self.loadFromBundle() }
        loadTask = task
        let result = await task.value
        catalog = result
        isLoaded = (result != nil)
        loadTask = nil
        return result
    }

    nonisolated private static func loadFromBundle() -> MonthlyDevotionCatalog? {
        guard let url = Bundle.main.url(forResource: "monthly-devotions",
                                        withExtension: "json") else {
            assertionFailure("monthly-devotions.json missing from bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(MonthlyDevotionCatalog.self, from: data)
        } catch {
            assertionFailure("Failed to load monthly-devotions.json: \(error)")
            return nil
        }
    }
}
