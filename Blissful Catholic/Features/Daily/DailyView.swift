//
//  DailyView.swift
//  Blissful Catholic
//
//  Tab 1 — the home, in Lumen. Verse of the day, today's Mass readings, the
//  saint of the day, a reflection, and a burning-candle intention. The readings,
//  saint, and reflection now push their detail screens.
//

import SwiftUI
import SwiftData

enum DailyRoute: Hashable {
    case reading(ReadingItem)
    case saint
    case reflection
}

struct DailyView: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.modelContext) private var context

    @State private var prayed = false
    @State private var showReflection = false
    @State private var liturgy = LiturgyStore()
    private let now = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LumenScreenHeader(eyebrow: headerEyebrow, title: monthDay) {
                        LumenIconButton(systemImage: "bell")
                    }

                    verse
                    Ornament(color: t.inkSoft)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 22)

                    VStack(spacing: 16) {
                        reflectWithAI
                        readingsCard
                        NavigationLink(value: DailyRoute.saint) { saintCard }
                            .buttonStyle(.plain)
                        NavigationLink(value: DailyRoute.reflection) { reflectionCard }
                            .buttonStyle(.plain)
                        intentionSection
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 120)
            }
            .background(t.bg.ignoresSafeArea())
            .navigationDestination(for: DailyRoute.self) { route in
                switch route {
                case .reading(let r): ReadingScreen(reading: r)
                case .saint:          SaintScreen()
                case .reflection:     ReflectionScreen()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await liturgy.loadToday() }
            .task(id: liturgy.today?.date) { await loadFirstVerses() }
        }
        .sheet(isPresented: $showReflection) {
            AIReflectionView(
                feature: "daily",
                prompt: "Give me a short, personal reflection to pray with today."
            )
        }
    }

    // MARK: Reflect with AI

    private var reflectWithAI: some View {
        AICTAButton(title: "Reflect with your companion",
                    subtitle: "A reflection shaped for you, today") {
            showReflection = true
        }
    }

    // MARK: Verse hero

    /// Verse of the day: the first verse of today's Gospel, resolved against
    /// bundled WEBCE. Nil while loading or if today's readings haven't arrived.
    private var verseHero: (text: String, citation: String)? {
        guard let gospel = gospelReading,
              let first = firstVerses[gospel.citation] else { return nil }
        let book = Self.bookName(fromCitation: gospel.citation)
        return (first.text, "\(book) \(first.chapter):\(first.verse)")
    }

    private var gospelReading: ReadingItem? {
        readings?.first(where: { $0.label == "Gospel" })
    }

    /// "Mark 11:11-26" → "Mark"; "1 Peter 4:7-13" → "1 Peter". Takes everything
    /// before the last whitespace that precedes the chapter:verse colon.
    private static func bookName(fromCitation citation: String) -> String {
        guard let colon = citation.firstIndex(of: ":") else { return citation }
        let head = citation[..<colon]
        guard let lastSpace = head.lastIndex(of: " ") else { return String(head) }
        return String(citation[..<lastSpace])
    }

    @ViewBuilder
    private var verse: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hero = verseHero {
                Text("\u{201C}\(hero.text)\u{201D}")
                    .font(LumenType.display(26, weight: .medium).italic())
                    .foregroundStyle(t.ink)
                    .lineSpacing(4)
                Eyebrow(text: hero.citation, color: t.inkSoft)
            } else {
                Text("Today's word is being prepared.")
                    .font(LumenType.display(26, weight: .medium).italic())
                    .foregroundStyle(t.ink)
                    .lineSpacing(4)
                    .redacted(reason: .placeholder)
                Eyebrow(text: "Scripture", color: t.inkSoft)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 22)
        .animation(.easeInOut(duration: 0.35), value: verseHero?.citation)
    }

    // MARK: Mass readings

    /// Today's readings derived from `liturgy.today` — nil while the liturgy is
    /// loading or if the upstream readings source is unreachable.
    private var readings: [ReadingItem]? {
        guard let raw = liturgy.today?.readings else { return nil }
        return raw.map { ReadingItem(label: $0.label, citation: $0.citation) }
    }

    /// First verse per reading citation, resolved from bundled WEBCE. Serves two
    /// surfaces: the row preview text, and the verse-of-the-day hero (which
    /// needs the full BibleVerse for its chapter:verse eyebrow).
    @State private var firstVerses: [String: BibleVerse] = [:]

    private func loadFirstVerses() async {
        guard let readings else { return }
        for r in readings where firstVerses[r.citation] == nil {
            let verses = await BibleService.shared.verses(forCitation: r.citation)
            if let first = verses.first, !first.text.isEmpty {
                firstVerses[r.citation] = first
            }
        }
    }

    private static let readingNumerals = ["i", "ii", "iii", "iv"]

    @ViewBuilder
    private var readingsCard: some View {
        if let readings, !readings.isEmpty {
            LumenCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Mass · \(massEyebrowSuffix)", color: pal.accent)
                            Text("Today's Readings")
                                .font(LumenType.display(22))
                                .foregroundStyle(t.ink)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                    ForEach(Array(readings.enumerated()), id: \.offset) { i, r in
                        NavigationLink(value: DailyRoute.reading(r)) {
                            readingRow(index: i, reading: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// e.g. "Trinity Sunday" on a Solemnity; weekday-of-season otherwise.
    private var massEyebrowSuffix: String {
        if let day = liturgy.today, !day.isFeria { return day.celebration }
        return "\(weekday) · \(liturgy.today?.season ?? pal.name)"
    }

    private func readingRow(index i: Int, reading r: ReadingItem) -> some View {
        HStack(spacing: 14) {
            Text(i < Self.readingNumerals.count ? Self.readingNumerals[i] : "\(i + 1)")
                .font(LumenType.display(16, weight: .semibold).italic())
                .foregroundStyle(pal.accent)
                .frame(width: 30, height: 30)
                .background(t.surface3, in: .circle)
                .overlay(Circle().strokeBorder(t.rule, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "\(r.label) · \(r.citation)", color: t.inkSoft)
                if let preview = firstVerses[r.citation]?.text, !preview.isEmpty {
                    Text(preview)
                        .font(LumenType.serif(14))
                        .foregroundStyle(t.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.inkSoft)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(Rectangle().fill(t.ruleSoft).frame(height: 0.5), alignment: .top)
    }

    // MARK: Saint of the day

    private var saintCard: some View {
        LumenCard(padding: 0) {
            HStack(spacing: 0) {
                ArtPlate(label: "ST. RITA · 1381", hue: 20, width: 108, height: 130, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Memorial", color: pal.accent)
                        Text("St. Rita of Cascia").font(LumenType.display(22)).foregroundStyle(t.ink)
                        Text("Patroness of impossible causes")
                            .font(LumenType.serif(12).italic()).foregroundStyle(t.inkMid)
                    }
                    Spacer(minLength: 0)
                    Text("Wife, mother, widow, and Augustinian — known for the wound she bore on her forehead.")
                        .font(LumenType.serif(12)).foregroundStyle(t.inkMid).lineSpacing(2)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Reflection

    private var reflectionCard: some View {
        LumenCard {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Reflection · 3 min read", color: pal.accent)
                Text("On the kind of joy that does not depend on circumstance.")
                    .font(LumenType.display(19)).foregroundStyle(t.ink).lineSpacing(2)
                Text("“Your grief will become joy” — not be replaced, not be undone. The Lord names a transformation only sorrow can prepare us for…")
                    .font(LumenType.serif(13)).foregroundStyle(t.inkMid).lineSpacing(3)
                HStack(spacing: 8) {
                    Text("F")
                        .font(LumenType.display(12).italic()).foregroundStyle(t.goldDeep)
                        .frame(width: 22, height: 22).background(t.surface3, in: .circle)
                    Text("Fr. Henri Nouwen, OP").font(LumenType.ui(11)).foregroundStyle(t.inkSoft)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Intention

    private var intentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Today's intention", color: t.inkSoft).padding(.horizontal, 4)
            LumenCard(padding: 16) {
                HStack(spacing: 14) {
                    Candle(size: 22, lit: prayed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("For my mother's health.").font(LumenType.display(17)).foregroundStyle(t.ink)
                        Text("Day 4 · burning").font(LumenType.ui(11)).foregroundStyle(t.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Button { logPrayed() } label: {
                        Text(prayed ? "Prayed" : "I prayed")
                            .font(LumenType.ui(11, weight: .medium))
                            .foregroundStyle(prayed ? .white : pal.accent)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(prayed ? pal.accent : .clear, in: .capsule)
                            .overlay(Capsule().strokeBorder(prayed ? .clear : t.rule, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: prayed) { _, now in now }
                }
            }
        }
    }

    private func logPrayed() {
        if !prayed {
            let session = PrayerSession()
            session.date = .now
            session.feature = .examen
            session.completed = true
            session.notes = "Intention"
            context.insert(session)
            try? context.save()
        }
        prayed.toggle()
    }

    /// Header eyebrow — prefers the real liturgical day when loaded; falls back to
    /// the locally-computed season + weekday when offline or still loading.
    private var headerEyebrow: String {
        guard let day = liturgy.today else { return "\(pal.name) · \(weekday)" }
        if day.isFeria { return "\(day.season ?? pal.name) · \(weekday)" }
        return day.celebration
    }

    private var weekday: String { now.formatted(.dateTime.weekday(.wide)) }
    private var monthDay: String { now.formatted(.dateTime.month(.abbreviated).day()) }
}

#Preview {
    DailyView()
        .environment(\.lumenTokens, .parchment)
        .environment(\.lumenPalette, .for(.easter))
        .modelContainer(PreviewSupport.container)
}
