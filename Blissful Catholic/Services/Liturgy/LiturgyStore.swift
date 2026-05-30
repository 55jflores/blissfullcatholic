//
//  LiturgyStore.swift
//  Blissful Catholic
//
//  Fetches the day's liturgical info (season, color, celebration/saint, rank) from
//  the backend's /api/liturgy (romcal — calendar facts, no copyright). Reading
//  citations + scripture text are layered on later. Falls back gracefully when
//  offline: the UI keeps using the locally-computed season.
//

import Foundation

struct LiturgicalDay: Decodable {
    let date: String          // YYYY-MM-DD
    let celebration: String   // e.g. "The Ascension of the Lord" / "Friday of the 8th week of Ordinary Time"
    let rank: String          // SOLEMNITY | FEAST | MEMORIAL | OPT_MEMORIAL | SUNDAY | FERIA | …
    let season: String?       // e.g. "Ordinary Time"
    let seasonKey: String?
    let color: String?        // e.g. "GREEN"
    let colorHex: String?
    let cycle: String?
    /// Today's Mass reading *citations* (label + reference, no text). iOS
    /// resolves them against bundled WEBCE locally via `BibleService`.
    /// `nil` when the upstream readings source is unreachable.
    let readings: [ReadingCitation]?

    var isFeria: Bool { rank == "FERIA" }
}

struct ReadingCitation: Decodable, Hashable, Sendable, Identifiable {
    let label: String         // "First Reading" | "Responsorial Psalm" | "Second Reading" | "Gospel"
    let citation: String      // e.g. "Acts 18:9–18", "Daniel 3:52, 53, 54, 55, 56"

    var id: String { label + citation }
}

@MainActor
@Observable
final class LiturgyStore {
    private(set) var today: LiturgicalDay?

    private let base = SupabaseConfig.apiBaseURL

    /// Loads today's liturgical day (no-op if already loaded for the current date).
    func loadToday() async {
        let date = Self.localDateString()
        if today?.date == date { return }

        guard var comps = URLComponents(
            url: base.appending(path: "api/liturgy"), resolvingAgainstBaseURL: false
        ) else { return }
        comps.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = comps.url else { return }

        // Bypass URLSession's local cache — the response is small and the CDN already
        // caches at the edge. Local caching here once bit us: a stale pre-readings
        // payload sat in the device cache for an hour even after the backend was
        // updated, returning `today` with `readings == nil`.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            today = try JSONDecoder().decode(LiturgicalDay.self, from: data)
        } catch {
            // Offline / decode failure — leave `today` as-is; UI falls back.
        }
    }

    /// Today's date in the device's local calendar, as YYYY-MM-DD.
    private static func localDateString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
