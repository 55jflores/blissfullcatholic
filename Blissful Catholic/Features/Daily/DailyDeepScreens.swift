//
//  DailyDeepScreens.swift
//  Blissful Catholic
//
//  The deep screens reached from the Daily tab: a reading detail (drop cap),
//  the saint detail, and the reflection reader. Content is hardcoded sample for
//  Phase 1 — scripture comes from API.Bible and reflections from Claude in
//  Phase 4.
//

import SwiftUI

// MARK: - Reading

/// A Mass reading, passed from Daily into the detail screen. The body text is
/// resolved on demand from bundled WEBCE in ReadingScreen; only the citation
/// travels in the route value.
struct ReadingItem: Hashable {
    let label: String      // "First Reading" / "Responsorial Psalm" / "Second Reading" / "Gospel"
    let citation: String   // e.g. "Acts 18:9–18", "Daniel 3:52, 53, 54, 55, 56"
}

struct ReadingScreen: View {
    let reading: ReadingItem
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var showLectio = false
    @State private var verses: [BibleVerse] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: reading.label, title: reading.citation, onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: reading.label, color: pal.accent).padding(.bottom, 10)
                    Ornament(color: pal.accent).frame(maxWidth: 220).padding(.vertical, 22)

                    if isLoading {
                        loadingState
                    } else if verses.isEmpty {
                        unresolvedState
                    } else {
                        DropCapText(formattedBody)
                        responseBox
                        translationFooter
                    }

                    AICTAButton(title: "Pray this with Lectio Divina",
                                subtitle: "A guided, prayerful reading") {
                        showLectio = true
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 140)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadVerses() }
        .sheet(isPresented: $showLectio) {
            AIReflectionView(
                feature: "lectio",
                prompt: lectioPrompt,
                title: "Lectio Divina",
                reason: "Sign in to pray Lectio Divina."
            )
        }
    }

    // MARK: States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().tint(pal.accent)
            Text("Loading the passage…")
                .font(LumenType.serif(14).italic()).foregroundStyle(t.inkMid)
        }
        .padding(.top, 4)
    }

    private var unresolvedState: some View {
        Text("This passage couldn't be resolved against the bundled translation. Try checking the citation against your Bible or missal.")
            .font(LumenType.serif(15))
            .foregroundStyle(t.inkMid)
            .lineSpacing(4)
    }

    /// The liturgical response after the reading. Skipped for the Responsorial
    /// Psalm, which has its own antiphon-based response pattern (the assembly's
    /// refrain repeats between strophes), not "The Word of the Lord."
    @ViewBuilder
    private var responseBox: some View {
        if reading.label != "Responsorial Psalm" {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: responseLabel, color: t.inkSoft)
                Text(responseText)
                    .font(LumenType.display(18).italic())
                    .foregroundStyle(t.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface2, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.rule, lineWidth: 0.5))
            .padding(.top, 24)
        }
    }

    private var translationFooter: some View {
        Text("World English Bible · Catholic Edition · Public Domain")
            .font(LumenType.ui(10).italic())
            .foregroundStyle(t.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 16)
    }

    // MARK: Derived

    /// Concatenates the resolved verses; inserts a blank line between verses
    /// that aren't consecutive (lectionary citations like "Ex 34:4b-6, 8-9"
    /// resolve to a sequence with a gap between 6 and 8).
    private var formattedBody: String {
        var result = ""
        var prev: BibleVerse?
        for v in verses {
            if let p = prev {
                let consecutive = (v.chapter == p.chapter && v.verse == p.verse + 1)
                result += consecutive ? " " : "\n\n"
            }
            result += v.text
            prev = v
        }
        return result
    }

    private var responseLabel: String {
        reading.label == "Gospel" ? "The Gospel of the Lord" : "The Word of the Lord"
    }

    private var responseText: String {
        reading.label == "Gospel"
            ? "Praise to you, Lord Jesus Christ."
            : "Thanks be to God."
    }

    private var lectioPrompt: String {
        if verses.isEmpty {
            return "Lead me in praying Lectio Divina with this passage — \(reading.citation)."
        }
        return "Lead me in praying Lectio Divina with this passage — \(reading.citation):\n\n\(formattedBody)"
    }

    private func loadVerses() async {
        verses = await BibleService.shared.verses(forCitation: reading.citation)
        isLoading = false
    }
}

/// Body text with a large serif drop cap on the first letter.
private struct DropCapText: View {
    let text: String
    init(_ text: String) { self.text = text }

    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal

    var body: some View {
        let paragraphs = text.components(separatedBy: "\n\n")
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { i, para in
                if i == 0, !para.isEmpty {
                    Text(dropCapped(para))
                        .lineSpacing(6)
                } else {
                    Text(para)
                        .font(LumenType.serif(17))
                        .foregroundStyle(t.ink)
                        .lineSpacing(6)
                }
            }
        }
    }

    /// A drop-cap paragraph: a large accent first letter, then serif body — built
    /// as one AttributedString (iOS 26 deprecated `Text + Text`).
    private func dropCapped(_ para: String) -> AttributedString {
        var head = AttributedString(String(para.prefix(1)))
        head.font = LumenType.display(52)
        head.foregroundColor = pal.accent
        var rest = AttributedString(String(para.dropFirst()))
        rest.font = LumenType.serif(17)
        rest.foregroundColor = t.ink
        head.append(rest)
        return head
    }
}

// MARK: - Saint

struct SaintScreen: View {
    let saint: Saint
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var showReflect = false

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: headerEyebrow, title: saint.name, onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artworkHeader

                    VStack(alignment: .leading, spacing: 0) {
                        if let patronage = saint.patronage {
                            Eyebrow(text: patronage, color: pal.accent)
                        }
                        Text(saint.name)
                            .font(LumenType.display(36))
                            .foregroundStyle(t.ink)
                            .tracking(-0.5)
                            .padding(.top, 8)
                        if let title = saint.title {
                            Text(title)
                                .font(LumenType.serif(14).italic())
                                .foregroundStyle(t.inkMid)
                                .padding(.top, 6)
                        }

                        Ornament(color: pal.accent).padding(.vertical, 22)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(bioParagraphs.enumerated()), id: \.offset) { _, p in
                                Text(p).font(LumenType.serif(15)).foregroundStyle(t.ink).lineSpacing(6)
                            }
                        }

                        attributionFooter

                        AICTAButton(title: "Reflect on this saint",
                                    subtitle: "What their witness offers you today") {
                            showReflect = true
                        }
                        .padding(.top, 28)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 140)
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showReflect) {
            AIReflectionView(
                feature: "saint",
                prompt: reflectPrompt,
                title: saint.name,
                reason: "Sign in to reflect on the saints."
            )
        }
    }

    // MARK: Derived

    /// Eyebrow above the title — uses today's date and the saint's rank/title
    /// (e.g. "Memorial · Sep 23", "Solemnity · Aug 15").
    private var headerEyebrow: String {
        let date = Date().formatted(.dateTime.month(.abbreviated).day())
        if let title = saint.title { return "\(title) · \(date)" }
        return date
    }

    /// Split the bio into paragraphs on the `\n\n` delimiter we use in saints.json.
    private var bioParagraphs: [String] {
        saint.bio.components(separatedBy: "\n\n")
    }

    /// Hero artwork. Uses bundled public-domain painting when present; falls
    /// back to the procedural `ArtPlate` for saints we haven't curated artwork
    /// for yet (Patrick) or where no PD portrait exists (Padre Pio).
    ///
    /// Layout note: a clear-color frame controls the container size, and the
    /// image is rendered as an overlay on top of it. This is the only reliable
    /// way I've found to keep an aspect-fill image from ballooning its parent
    /// VStack to the image's intrinsic width (which dragged the rest of the
    /// screen's content off the left edge in the first pass).
    @ViewBuilder
    private var artworkHeader: some View {
        if let uiImage = bundledArtwork {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 4)
        } else {
            ArtPlate(label: saint.artPlateLabel, hue: 15, height: 260, cornerRadius: 0)
        }
    }

    /// Resolve the bundled painting. Files live in `Resources/saint-art/{key}.jpg`
    /// in the source tree, but Xcode's synchronized file group flattens the
    /// directory, so they're at the bundle root keyed by `{key}.jpg` at runtime.
    /// Nil when no artwork is present for this saint key.
    private var bundledArtwork: UIImage? {
        guard let url = Bundle.main.url(forResource: saint.key, withExtension: "jpg"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// Honest provenance for both the bio and the artwork. The bio attribution
    /// always applies; the artwork credit appears only when bundled art exists.
    private var attributionFooter: some View {
        VStack(spacing: 4) {
            if let artwork = saint.artwork {
                Text("\(artwork.artist) · \(artwork.title) (\(artwork.year))")
                    .font(LumenType.ui(10).italic())
                    .foregroundStyle(t.inkSoft)
                    .multilineTextAlignment(.center)
                Text(artwork.source)
                    .font(LumenType.ui(9))
                    .foregroundStyle(t.inkSoft.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Text("Facts drawn from the 1913 Catholic Encyclopedia and Vatican biographical sources. Devotional prose written for Blissful Catholic.")
                .font(LumenType.ui(10).italic())
                .foregroundStyle(t.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, saint.artwork == nil ? 0 : 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    /// AI reflection prompt — passes the saint's facts and bio so the response
    /// is grounded rather than generated from the model's general knowledge.
    private var reflectPrompt: String {
        var prompt = "Tell me about \(saint.name)"
        if let title = saint.title { prompt += " (\(title))" }
        prompt += " — their life and witness — and what their example offers me today.\n\n"
        prompt += "Background:\n\(saint.bio)"
        return prompt
    }
}

// MARK: - Monthly Devotion

/// Deep screen for the month's traditional Catholic devotion (Sacred Heart in
/// June, Holy Rosary in October, and so on). Mirrors `SaintScreen` in shape —
/// artwork hero, body paragraphs, AI CTA — but with content drawn from
/// `monthly-devotions.json`.
struct MonthlyDevotionScreen: View {
    let devotion: MonthlyDevotion
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var showReflect = false

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: headerEyebrow, title: devotion.name,
                            onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artworkHeader

                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: devotion.subtitle, color: pal.accent)
                        Text(devotion.name)
                            .font(LumenType.display(32))
                            .foregroundStyle(t.ink)
                            .tracking(-0.5)
                            .padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)

                        Ornament(color: pal.accent).padding(.vertical, 22)

                        Text(devotion.intro)
                            .font(LumenType.display(18).italic())
                            .foregroundStyle(t.ink)
                            .lineSpacing(5)
                            .padding(.bottom, 18)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(reflectionParagraphs.enumerated()),
                                    id: \.offset) { _, p in
                                Text(p)
                                    .font(LumenType.serif(15))
                                    .foregroundStyle(t.ink)
                                    .lineSpacing(6)
                            }
                        }

                        attributionFooter

                        AICTAButton(title: "Reflect on this devotion",
                                    subtitle: "Pray with the month's intention") {
                            showReflect = true
                        }
                        .padding(.top, 28)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 140)
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showReflect) {
            AIReflectionView(
                feature: "devotion",
                prompt: reflectPrompt,
                title: devotion.name,
                reason: "Sign in to reflect on the month's devotion."
            )
        }
    }

    // MARK: Derived

    /// Eyebrow above the title — the full month name. Reads naturally
    /// alongside the devotion's title ("June · The Sacred Heart of Jesus").
    private var headerEyebrow: String {
        let comps = DateComponents(month: devotion.month)
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return date.formatted(.dateTime.month(.wide))
    }

    private var reflectionParagraphs: [String] {
        devotion.reflection.components(separatedBy: "\n\n")
    }

    /// Hero artwork. Same Color.clear-overlay trick as `SaintScreen.artworkHeader`
    /// — without it, an aspect-fill image will balloon its parent VStack to the
    /// image's intrinsic width and drag the body text off-screen.
    @ViewBuilder
    private var artworkHeader: some View {
        if let uiImage = bundledArtwork {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 4)
        } else {
            ArtPlate(label: devotion.name.uppercased(), hue: 28,
                     height: 260, cornerRadius: 0)
        }
    }

    /// Resolve the bundled painting at `Resources/devotion-art/{key}.jpg`. Xcode
    /// flattens synchronized folders so the file is at the bundle root.
    private var bundledArtwork: UIImage? {
        guard let url = Bundle.main.url(forResource: devotion.key, withExtension: "jpg"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// Honest provenance, parallel to `SaintScreen.attributionFooter`.
    private var attributionFooter: some View {
        VStack(spacing: 4) {
            if let artwork = devotion.artwork {
                Text("\(artwork.artist) · \(artwork.title) (\(artwork.year))")
                    .font(LumenType.ui(10).italic())
                    .foregroundStyle(t.inkSoft)
                    .multilineTextAlignment(.center)
                Text(artwork.source)
                    .font(LumenType.ui(9))
                    .foregroundStyle(t.inkSoft.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Text("Grounded in the Roman Missal, the Catechism, and the traditions of the Church. Devotional prose written for Blissful Catholic.")
                .font(LumenType.ui(10).italic())
                .foregroundStyle(t.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, devotion.artwork == nil ? 0 : 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    /// Prompt seed for the AI sheet — grounds the model in the devotion's own
    /// text rather than the model's general knowledge of Catholic tradition.
    private var reflectPrompt: String {
        """
        Help me pray with the Catholic devotion of \(devotion.name) — the traditional focus of \(devotion.subtitle.lowercased()).

        Background:
        \(devotion.intro)

        \(devotion.reflection)

        Offer a brief, personal reflection — just a few sentences — and one specific way I can carry this devotion into today.
        """
    }
}

// MARK: - Reflection

/// Renders today's AI-generated reflection from `DailyReflectionStore`. The home
/// `DailyView` is responsible for triggering the load; this screen just observes
/// the store and renders its phase.
struct ReflectionScreen: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var store = DailyReflectionStore.shared

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: headerEyebrow, title: "Today's Reflection",
                            onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: eyebrowText, color: pal.accent).padding(.bottom, 10)
                    Ornament(color: pal.accent).frame(maxWidth: 220).padding(.vertical, 22)

                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 140)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .ready:
            if let r = store.reflection {
                DropCapText(r.body)
                footer(for: r)
            } else {
                placeholder("Today's reflection isn't available yet.")
            }
        case .loading:
            loadingState
        case .error(let msg):
            placeholder(msg)
        case .signedOut:
            placeholder("Sign in to see your reflection for today.")
        case .idle:
            placeholder("Today's reflection isn't available yet.")
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().tint(pal.accent)
            Text("Composing today's reflection…")
                .font(LumenType.serif(14).italic())
                .foregroundStyle(t.inkMid)
        }
        .padding(.top, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(LumenType.serif(15))
            .foregroundStyle(t.inkMid)
            .lineSpacing(4)
    }

    private func footer(for r: DailyReflection) -> some View {
        VStack(spacing: 8) {
            Ornament(color: t.inkSoft).frame(maxWidth: 160)
            Text("A reflection grounded in today's Gospel · generated for you")
                .font(LumenType.ui(10).italic())
                .foregroundStyle(t.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    // MARK: Derived

    private var headerEyebrow: String {
        Date().formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Reflection on Mark 11:11–26" when ready; generic before.
    private var eyebrowText: String {
        if case .ready = store.phase, let r = store.reflection {
            return "Reflection on \(r.gospelCitation)"
        }
        return "Today's Reflection"
    }
}
