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
    case saint(Saint)
    case devotion(MonthlyDevotion)
    case reflection
    case intentions
}

struct DailyView: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.modelContext) private var context
    @Environment(AuthStore.self) private var auth
    @Environment(UserProfileStore.self) private var profile

    @State private var showReflection = false
    @State private var liturgy = LiturgyStore()
    @State private var reflectionStore = DailyReflectionStore.shared

    /// Active intentions sorted most-recent-first. The card features the first
    /// one; the deep list (`IntentionsListView`) shows them all.
    @Query(filter: #Predicate<Intention> { $0.completedAt == nil },
           sort: \Intention.createdAt, order: .reverse)
    private var activeIntentions: [Intention]
    /// Today's Gospel text + citation, cached after `loadDailyReflection` resolves
    /// them. Used to ground the "Reflect with your companion" sheet prompt so its
    /// AI sees the same passage the reflection card was generated from.
    @State private var todayGospelText = ""
    @State private var todayGospelCitation = ""
    private let now = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LumenScreenHeader(eyebrow: headerEyebrow, title: monthDay)

                    verse
                    Ornament(color: t.inkSoft)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 22)

                    VStack(spacing: 16) {
                        reflectWithAI
                        readingsCard
                        saintCard
                        devotionCard
                        reflectionCard
                        intentionCard
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 120)
            }
            .background(t.bg.ignoresSafeArea())
            .navigationDestination(for: DailyRoute.self) { route in
                switch route {
                case .reading(let r):  ReadingScreen(reading: r)
                case .saint(let s):    SaintScreen(saint: s)
                case .devotion(let d): MonthlyDevotionScreen(devotion: d)
                case .reflection:      ReflectionScreen()
                case .intentions:      IntentionsListView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await liturgy.loadToday() }
            .task { await loadMonthlyDevotion() }
            .task(id: liturgy.today?.date) { await loadFirstVerses() }
            .task(id: liturgy.today?.celebration) { await loadSaint() }
            .task(id: liturgy.today?.date) { await loadDailyReflection() }
            .task(id: auth.isSignedIn) { await loadDailyReflection() }
        }
        .sheet(isPresented: $showReflection) {
            AIReflectionView(
                feature: "daily",
                prompt: companionPrompt
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

    /// Today's saint resolved from `liturgy.today.celebration` against the bundled
    /// saints catalog. Nil whenever the day is a feria, a Sunday, or a celebration
    /// outside the catalog (the first cut covers ~30 high-traffic saints).
    @State private var todaySaint: Saint?

    private func loadSaint() async {
        guard let celebration = liturgy.today?.celebration else {
            todaySaint = nil
            return
        }
        todaySaint = await SaintService.shared.resolve(celebration: celebration)
    }

    /// Display string for the liturgical rank shown as the saint card's eyebrow.
    private var rankDisplay: String {
        switch liturgy.today?.rank {
        case "SOLEMNITY":      return "Solemnity"
        case "FEAST":          return "Feast"
        case "MEMORIAL":       return "Memorial"
        case "OPT_MEMORIAL":   return "Optional Memorial"
        default:               return "Today"
        }
    }

    /// Resolves the bundled public-domain painting for this saint. Same lookup
    /// as `SaintScreen.bundledArtwork`. Nil for saints with no curated artwork
    /// (Patrick, Padre Pio at this time), which fall back to the procedural
    /// `ArtPlate` below.
    private func bundledArtwork(for saint: Saint) -> UIImage? {
        guard let url = Bundle.main.url(forResource: saint.key, withExtension: "jpg"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// 140×170 art slot for the Daily card. Bumped up from the original 108×130
    /// so that multi-figure Renaissance paintings stay legible at thumbnail size.
    @ViewBuilder
    private func saintArtThumbnail(for saint: Saint) -> some View {
        if let uiImage = bundledArtwork(for: saint) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 170)
                .clipped()
        } else {
            ArtPlate(label: saint.artPlateLabel, hue: 20, width: 140, height: 170, cornerRadius: 0)
        }
    }

    /// Hidden entirely on days the catalog can't resolve — cleaner than showing
    /// a stale saint.
    @ViewBuilder
    private var saintCard: some View {
        if let saint = todaySaint {
            NavigationLink(value: DailyRoute.saint(saint)) {
                LumenCard(padding: 0) {
                    HStack(spacing: 14) {
                        saintArtThumbnail(for: saint)
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Eyebrow(text: rankDisplay, color: pal.accent)
                                Text(saint.name)
                                    .font(LumenType.display(22))
                                    .foregroundStyle(t.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let patronage = saint.patronage {
                                    Text(patronage)
                                        .font(LumenType.serif(12).italic()).foregroundStyle(t.inkMid)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(saint.blurb)
                                .font(LumenType.serif(12)).foregroundStyle(t.inkMid).lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Monthly devotion

    /// This month's traditional Catholic devotion (Sacred Heart in June, Holy
    /// Rosary in October, …). Twelve fixed entries — one per month — so this is
    /// never nil in practice unless the catalog fails to load from the bundle.
    @State private var monthlyDevotion: MonthlyDevotion?

    /// Loaded once on view appear from the system calendar's current month.
    /// The devotion is a month-long anchor, so there's no need to re-load when
    /// the liturgical day rolls over — the calendar month is what matters here.
    private func loadMonthlyDevotion() async {
        monthlyDevotion = await MonthlyDevotionService.shared.devotion(for: Date())
    }

    /// Resolve the bundled devotion painting. Same flat-bundle lookup as
    /// `bundledArtwork(for: Saint)` — Xcode 16 synchronized groups put every
    /// resource at the bundle root, so the key alone is the lookup.
    private func bundledArtwork(for devotion: MonthlyDevotion) -> UIImage? {
        guard let url = Bundle.main.url(forResource: devotion.key, withExtension: "jpg"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// 140×170 thumbnail — matches the saint card's slot so the two cards read
    /// as a visual pair (today's person + this month's anchor). Falls back to
    /// the procedural `ArtPlate` when no curated painting is bundled.
    @ViewBuilder
    private func devotionArtThumbnail(for devotion: MonthlyDevotion) -> some View {
        if let uiImage = bundledArtwork(for: devotion) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 170)
                .clipped()
        } else {
            ArtPlate(label: devotion.name.uppercased(), hue: 28,
                     width: 140, height: 170, cornerRadius: 0)
        }
    }

    /// Mirrors the saint card layout — painting thumbnail on the left, text on
    /// the right. Drills into `MonthlyDevotionScreen` with the full artwork.
    @ViewBuilder
    private var devotionCard: some View {
        if let devotion = monthlyDevotion {
            NavigationLink(value: DailyRoute.devotion(devotion)) {
                LumenCard(padding: 0) {
                    HStack(spacing: 14) {
                        devotionArtThumbnail(for: devotion)
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Eyebrow(text: devotion.subtitle, color: pal.accent)
                                Text(devotion.name)
                                    .font(LumenType.display(20))
                                    .foregroundStyle(t.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Text(devotion.intro)
                                .font(LumenType.serif(12))
                                .foregroundStyle(t.inkMid)
                                .lineSpacing(2)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Reflection

    /// Only the reflection generated *for today's date* counts as "ready" — the
    /// store may still hold yesterday's cached value briefly after midnight
    /// rollover until the new one arrives.
    private var todaysReflection: DailyReflection? {
        guard let r = reflectionStore.reflection,
              r.date == liturgy.today?.date else { return nil }
        return r
    }

    /// State-aware reflection card:
    ///   - ready: tappable preview → ReflectionScreen
    ///   - loading: a small skeleton while the AI call is in flight
    ///   - error: a quiet error pill
    ///   - signedOut / idle: hidden (the "Reflect with your companion" CTA at
    ///     the top already handles signed-out users who want AI)
    @ViewBuilder
    private var reflectionCard: some View {
        if let r = todaysReflection {
            NavigationLink(value: DailyRoute.reflection) {
                LumenCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Today's Reflection · ~2 min", color: pal.accent)
                        Text(Self.reflectionPreview(r.body))
                            .font(LumenType.display(19).italic())
                            .foregroundStyle(t.ink)
                            .lineSpacing(3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("On today's Gospel · \(r.gospelCitation)")
                            .font(LumenType.ui(11))
                            .foregroundStyle(t.inkSoft)
                            .padding(.top, 6)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if reflectionStore.phase == .loading {
            LumenCard {
                HStack(spacing: 10) {
                    ProgressView().tint(pal.accent)
                    Text("Composing today's reflection…")
                        .font(LumenType.serif(14).italic())
                        .foregroundStyle(t.inkMid)
                }
            }
        } else if case .error(let msg) = reflectionStore.phase {
            LumenCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load today's reflection.")
                        .font(LumenType.serif(14))
                        .foregroundStyle(t.inkMid)
                    Text(msg)
                        .font(LumenType.ui(11))
                        .foregroundStyle(t.inkSoft)
                        .lineLimit(2)
                }
            }
        }
        // .idle and .signedOut → hidden; the top "Reflect with your companion"
        // button is the sign-in / AI entry point in those states.
    }

    /// First two sentences (or first ~180 chars) of the body, for the card preview.
    static func reflectionPreview(_ body: String) -> String {
        let chars = Array(body)
        var sentenceEnds: [Int] = []
        for (i, c) in chars.enumerated() where c == "." || c == "!" || c == "?" {
            sentenceEnds.append(i)
            if sentenceEnds.count == 2 { break }
        }
        if sentenceEnds.count == 2 {
            return String(chars[0...sentenceEnds[1]])
        }
        return body.count > 180 ? String(body.prefix(180)) + "…" : body
    }

    /// Fetch today's Gospel text from BibleService and hand it to the
    /// DailyReflectionStore (which handles caching + the AI call). Idempotent —
    /// fires on liturgy-loaded and on sign-in transitions. Also caches the
    /// Gospel text + citation into `@State` so the companion sheet's prompt can
    /// reuse them without a second BibleService lookup.
    private func loadDailyReflection() async {
        guard let day = liturgy.today,
              let gospel = day.readings?.first(where: { $0.label == "Gospel" })
        else { return }
        let token = await auth.accessToken()
        let verses = await BibleService.shared.verses(forCitation: gospel.citation)
        let gospelText = verses.map(\.text).joined(separator: " ")
        todayGospelText = gospelText
        todayGospelCitation = gospel.citation
        let personalization = AppContext.current(profile: profile).systemPromptFragment
        await reflectionStore.loadIfNeeded(
            date: day.date,
            gospelCitation: gospel.citation,
            gospelText: gospelText,
            token: token,
            personalization: personalization
        )
    }

    /// Prompt for the "Reflect with your companion" sheet. Grounds the AI in
    /// today's Gospel when we have it; falls back to a generic ask when the
    /// passage hasn't resolved yet (offline, mid-load, or signed out).
    private var companionPrompt: String {
        guard !todayGospelText.isEmpty else {
            return "Give me a short, personal reflection to pray with today."
        }
        return """
        Pray with me on today's Gospel — \(todayGospelCitation):

        "\(todayGospelText)"

        Offer a brief, personal reflection — just a few sentences — and give me one specific thing to bring into prayer today.
        """
    }

    // MARK: Intention

    /// Most-recently-created active intention, "featured" on the home card.
    private var featuredIntention: Intention? { activeIntentions.first }

    @ViewBuilder
    private var intentionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Today's intention", color: t.inkSoft)
                Spacer()
                if !activeIntentions.isEmpty {
                    NavigationLink(value: DailyRoute.intentions) {
                        HStack(spacing: 2) {
                            Text("View all").font(LumenType.ui(11))
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                        .foregroundStyle(t.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            if let featured = featuredIntention {
                LumenCard(padding: 16) {
                    HStack(spacing: 14) {
                        // Left side — candle + text — taps into the deep list.
                        NavigationLink(value: DailyRoute.intentions) {
                            HStack(spacing: 14) {
                                Candle(size: 22, lit: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(featured.text)
                                        .font(LumenType.display(17))
                                        .foregroundStyle(t.ink)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Text(intentionMetaLine(featured))
                                        .font(LumenType.ui(11))
                                        .foregroundStyle(t.inkSoft)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        prayedButton(for: featured)
                    }
                }
            } else {
                NavigationLink(value: DailyRoute.intentions) {
                    HStack(spacing: 14) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(pal.accent)
                        Text("Set a prayer intention")
                            .font(LumenType.display(17).italic())
                            .foregroundStyle(t.inkMid)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(t.inkSoft)
                    }
                    .padding(16)
                    .background(t.surface, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(t.rule, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func intentionMetaLine(_ intention: Intention) -> String {
        var parts = ["Day \(intention.dayCount)"]
        if intention.prayerCount > 0 {
            parts.append("\(intention.prayerCount) \(intention.prayerCount == 1 ? "prayer" : "prayers")")
        }
        if intention.prayedToday {
            parts.append("prayed today")
        }
        return parts.joined(separator: " · ")
    }

    private func prayedButton(for intention: Intention) -> some View {
        Button { logPrayed(intention) } label: {
            Text(intention.prayedToday ? "Prayed" : "I prayed")
                .font(LumenType.ui(11, weight: .medium))
                .foregroundStyle(intention.prayedToday ? .white : pal.accent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(intention.prayedToday ? pal.accent : .clear, in: .capsule)
                .overlay(Capsule()
                    .strokeBorder(intention.prayedToday ? .clear : pal.accent.opacity(0.5),
                                  lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: intention.prayedToday) { _, now in now }
    }

    private func logPrayed(_ intention: Intention) {
        guard !intention.prayedToday else { return }
        intention.prayerCount += 1
        intention.lastPrayedAt = .now

        // Also create a PrayerSession so the day shows up as "active" in the
        // streak garden (Profile → Days of Prayer). The `notes` keeps a
        // breadcrumb back to which intention prompted this — useful later when
        // we want a per-day "what you prayed for" view.
        let session = PrayerSession()
        session.date = .now
        session.feature = .intention
        session.completed = true
        session.notes = intention.text
        context.insert(session)

        try? context.save()
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
