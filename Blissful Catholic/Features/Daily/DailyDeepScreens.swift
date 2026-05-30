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
            LumenDeepHeader(eyebrow: reading.label, title: reading.citation, onBack: { dismiss() }) {
                LumenIconButton(systemImage: "bookmark")
            }
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
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var showReflect = false

    private let saintName = "St. Rita of Cascia"
    private let patronages = ["Impossible causes", "Abused wives", "Widows", "Wounded"]
    private let bio = [
        "Born in Roccaporena, Umbria, Rita longed for the cloister from a young age but was given in marriage at twelve to a hot-tempered nobleman. For eighteen years she endured his cruelty in patience and prayer, eventually winning his conversion shortly before he was murdered in a vendetta.",
        "Her two sons swore to avenge their father. Rita prayed they might die rather than commit the sin of revenge — and within the year both succumbed to illness, reconciled to God.",
        "Widowed and childless, she sought entry into the Augustinian monastery at Cascia. Refused three times, she was finally admitted after, by tradition, her patron saints transported her there in the night.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: "Memorial · May 22", title: "St. Rita of Cascia", onBack: { dismiss() }) {
                LumenIconButton(systemImage: "bookmark")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArtPlate(label: "ST. RITA · MARGHERITA LOTTI · 1381–1457", hue: 15, height: 260, cornerRadius: 0)

                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Patroness of Impossible Causes", color: pal.accent)
                        Text("St. Rita of Cascia")
                            .font(LumenType.display(36))
                            .foregroundStyle(t.ink)
                            .tracking(-0.5)
                            .padding(.top, 8)
                        Text("Wife, mother, widow, Augustinian nun.")
                            .font(LumenType.serif(14).italic())
                            .foregroundStyle(t.inkMid)
                            .padding(.top, 6)

                        Ornament(color: pal.accent).padding(.vertical, 22)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(bio.enumerated()), id: \.offset) { _, p in
                                Text(p).font(LumenType.serif(15)).foregroundStyle(t.ink).lineSpacing(6)
                            }
                        }

                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(patronages, id: \.self) { tag in
                                Text(tag)
                                    .font(LumenType.ui(11))
                                    .foregroundStyle(t.inkMid)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(t.surface, in: .capsule)
                                    .overlay(Capsule().strokeBorder(t.rule, lineWidth: 0.5))
                            }
                        }
                        .padding(.top, 22)

                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: "Prayer to St. Rita", color: t.inkSoft)
                            Text("“O holy patroness of those in need, pray for us in this hour — that no cause may seem too lost to bring before the Father.”")
                                .font(LumenType.display(17).italic())
                                .foregroundStyle(t.ink)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surface2, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.rule, lineWidth: 0.5))
                        .padding(.top, 22)

                        AICTAButton(title: "Reflect on this saint",
                                    subtitle: "What their witness offers you today") {
                            showReflect = true
                        }
                        .padding(.top, 22)
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
                prompt: "Tell me about \(saintName) — their life and witness — and what their example offers me today.",
                title: saintName,
                reason: "Sign in to reflect on the saints."
            )
        }
    }
}

// MARK: - Reflection

struct ReflectionScreen: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    private let paragraphs = [
        "“Your grief will become joy.” The Lord does not say it will be replaced. He does not say it will be undone. He names a transformation — a turning — that only sorrow could have prepared.",
        "This is hard to receive. We are tempted to imagine joy as a kind of forgetting, or as the absence of suffering. But the Risen Lord still bears his wounds. The glorified body of the Son of God carries the marks of nails.",
        "What if the joy he promises is exactly the kind that remembers — that holds the whole of our story, and finds, at the bottom, that we were not alone?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            LumenDeepHeader(eyebrow: "Reflection · 3 min", title: "Friday of Easter VI") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "On joy that is given", color: pal.accent)
                    Text("The kind of joy that does not depend on circumstance.")
                        .font(LumenType.display(30))
                        .foregroundStyle(t.ink)
                        .tracking(-0.4)
                        .padding(.top, 8)

                    Ornament(color: pal.accent).padding(.vertical, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            Text(p).font(LumenType.serif(16)).foregroundStyle(t.ink).lineSpacing(6)
                        }
                    }

                    HStack(spacing: 12) {
                        Text("N")
                            .font(LumenType.display(16).italic())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(LinearGradient(colors: [pal.accent, pal.accentSoft],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fr. Henri Nouwen, OP").font(LumenType.display(15)).foregroundStyle(t.ink)
                            Text("Adapted from The Inner Voice of Love")
                                .font(LumenType.ui(11)).foregroundStyle(t.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "heart").foregroundStyle(pal.accent)
                    }
                    .padding(14)
                    .background(t.surface2, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(t.rule, lineWidth: 0.5))
                    .padding(.top, 24)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 140)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
