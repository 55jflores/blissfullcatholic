//
//  ProfileView.swift
//  Blissful Catholic
//
//  Tab 5 ("You") — reskinned to Lumen: identity, the streak "garden" of candles,
//  stats, sacramental record, and preferences. The Appearance section is wired
//  to the real ThemeController (replacing Lumen's prototype Tweaks panel), so
//  the user can switch ground (Parchment/Cathedral) and season live.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(UserProfileStore.self) private var profile
    @Environment(ThemeController.self) private var theme
    @Environment(AuthStore.self) private var auth

    @Query private var sessions: [PrayerSession]
    @Query private var entries: [JournalEntry]
    @Query private var rosaries: [RosaryLog]

    @State private var isEditing = false
    @State private var showSignIn = false

    // Streak data, derived from real activity.
    private var activeDays: Set<Date> {
        Streak.activeDays(from: sessions.map(\.date) + entries.map(\.date) + rosaries.map(\.date))
    }
    private var gardenLit: [Bool] { Streak.lastNDays(42, activeDays: activeDays) }
    private var litCount: Int { gardenLit.filter { $0 }.count }
    private var rangeLabel: String {
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let start = Calendar.current.date(byAdding: .day, value: -41, to: .now)!
        return (start.formatted(f) + " — " + Date().formatted(f)).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LumenScreenHeader(eyebrow: "Profile", title: firstName) {
                    LumenIconButton(systemImage: "gearshape") { isEditing = true }
                }

                VStack(spacing: 20) {
                    identityCard
                    streakGarden
                    statsRow
                    sacramentalRecord
                    accountSection
                    appearanceSection
                    preferencesSection
                    devReset
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 120)
        }
        .background(t.bg.ignoresSafeArea())
        .sheet(isPresented: $isEditing) { ProfileEditView() }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Account", color: t.inkSoft).padding(.horizontal, 4)
            LumenCard(padding: 0) {
                if let email = auth.email {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in").font(LumenType.display(16)).foregroundStyle(t.ink)
                            Text(email).font(LumenType.serif(12).italic()).foregroundStyle(t.inkMid)
                        }
                        Spacer()
                        Button { Task { await auth.signOut() } } label: {
                            Text("Sign out")
                                .font(LumenType.ui(11, weight: .medium))
                                .foregroundStyle(pal.accent)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .overlay(Capsule().strokeBorder(pal.accent, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                } else {
                    Button { showSignIn = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign in").font(LumenType.display(16)).foregroundStyle(t.ink)
                                Text("Unlock personalized AI reflections")
                                    .font(LumenType.serif(12).italic()).foregroundStyle(t.inkMid)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.inkSoft)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Identity

    private var identityCard: some View {
        Button { isEditing = true } label: {
            HStack(spacing: 14) {
                Text(initialLetter)
                    .font(LumenType.display(24).italic())
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [pal.accent, pal.accentSoft],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .circle)
                    .overlay(Circle().strokeBorder(t.surface, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.greetingName)
                        .font(LumenType.display(20))
                        .foregroundStyle(t.ink)
                    Text(subtitleLine)
                        .font(LumenType.serif(12).italic())
                        .foregroundStyle(t.inkMid)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.inkSoft)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(t.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.rule, lineWidth: 0.5))
            .lumenShadow(t)
        }
        .buttonStyle(.plain)
    }

    // MARK: Streak garden

    private var streakGarden: some View {
        LumenCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Days of Prayer", color: pal.accent)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(litCount)").font(LumenType.display(36)).foregroundStyle(t.ink)
                            Text("of 42").font(LumenType.display(22).italic()).foregroundStyle(t.inkMid)
                        }
                    }
                    Spacer()
                    Text(rangeLabel)
                        .font(LumenType.mono(10)).tracking(0.6).foregroundStyle(t.inkSoft)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(gardenLit.enumerated()), id: \.offset) { i, lit in
                        Candle(size: 12, lit: lit, flicker: i == 41 && lit)
                            .opacity(lit ? 1 : 0.35)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background(t.surface3, in: .rect(cornerRadius: 10))

                HStack {
                    Text("S M T W T F S")
                    Spacer()
                    Text("WEEKLY")
                }
                .font(LumenType.mono(9)).tracking(0.6).foregroundStyle(t.inkSoft)
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile("\(rosaries.count)", "Rosaries")
            statTile("\(entries.count)", "Journal entries")
            statTile("23", "Saints met")
        }
    }

    private func statTile(_ num: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(num).font(LumenType.display(28)).foregroundStyle(t.ink)
            Text(label).font(LumenType.ui(10)).foregroundStyle(t.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 12)
        .background(t.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(t.rule, lineWidth: 0.5))
    }

    // MARK: Sacramental record

    private let sacraments: [(name: String, detail: String, cta: String?)] = [
        ("Last Confession", "14 days ago · Fr. Jameson", "Examine"),
        ("Next Mass", "Sat 5:00 PM · Vigil", "Locate"),
        ("Last Communion", "Sunday May 19", nil),
    ]

    private var sacramentalRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Sacramental Life", color: t.inkSoft).padding(.horizontal, 4)
            LumenCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(sacraments.enumerated()), id: \.offset) { i, row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(LumenType.display(16)).foregroundStyle(t.ink)
                                Text(row.detail).font(LumenType.serif(12).italic()).foregroundStyle(t.inkMid)
                            }
                            Spacer()
                            if let cta = row.cta {
                                Text(cta)
                                    .font(LumenType.ui(11, weight: .medium))
                                    .foregroundStyle(pal.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .overlay(Capsule().strokeBorder(pal.accent, lineWidth: 0.5))
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(t.ruleSoft).frame(height: 0.5) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Appearance (real settings — replaces Lumen's Tweaks)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Appearance", color: t.inkSoft).padding(.horizontal, 4)
            LumenCard(padding: 0) {
                VStack(spacing: 0) {
                    menuRow(title: "Theme", value: theme.mode.displayName) {
                        ForEach(ThemeMode.allCases) { m in
                            Button(m.displayName) { theme.mode = m }
                        }
                    }
                    Rectangle().fill(t.ruleSoft).frame(height: 0.5).padding(.leading, 18)
                    menuRow(title: "Liturgical season", value: seasonValueLabel) {
                        Button("Automatic (from date)") { theme.seasonOverride = nil }
                        ForEach(LiturgicalSeason.allCases) { s in
                            Button(LiturgicalPalette.for(s).name) { theme.seasonOverride = s }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menuRow<Content: View>(title: String, value: String,
                                        @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            HStack {
                Text(title).font(LumenType.serif(14)).foregroundStyle(t.ink)
                Spacer()
                Text(value).font(LumenType.ui(12)).foregroundStyle(t.inkSoft)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(t.inkSoft)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(t.ink)
    }

    private var seasonValueLabel: String {
        theme.seasonOverride == nil ? "Automatic" : pal.name
    }

    // MARK: Preferences (sample)

    private let preferences: [(name: String, value: String, comingSoon: Bool)] = [
        ("Daily reminder", "7:00 AM", false),
        ("Bible translation", "RSV-2CE", false),
        ("Parish", "St. Cecilia", false),
        ("iCloud sync", "Coming soon", true),
    ]

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Preferences", color: t.inkSoft).padding(.horizontal, 4)
            LumenCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(preferences.enumerated()), id: \.offset) { i, row in
                        HStack {
                            Text(row.name).font(LumenType.serif(14)).foregroundStyle(t.ink)
                            Spacer()
                            Text(row.value).font(LumenType.ui(12)).foregroundStyle(t.inkSoft)
                            if !row.comingSoon {
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(t.inkSoft)
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .opacity(row.comingSoon ? 0.5 : 1)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(t.ruleSoft).frame(height: 0.5) }
                        }
                    }
                }
            }
        }
    }

    private var devReset: some View {
        Button(role: .destructive) {
            profile.onboardingComplete = false
        } label: {
            Text("Reset onboarding (dev)")
                .font(LumenType.ui(11))
                .foregroundStyle(t.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Helpers

    private var firstName: String {
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.split(separator: " ").first { return String(first) }
        return trimmed.isEmpty ? "You" : trimmed
    }
    private var initialLetter: String {
        String(profile.greetingName.first ?? "✦").uppercased()
    }
    private var subtitleLine: String {
        if let b = profile.background {
            return "\(b.displayName) · St. Cecilia Parish"
        }
        return "St. Cecilia Parish"
    }
}

#Preview {
    ProfileView()
        .environment(UserProfileStore.preview)
        .environment(ThemeController())
        .environment(AuthStore())
        .environment(\.lumenTokens, .parchment)
        .environment(\.lumenPalette, .for(.easter))
        .modelContainer(PreviewSupport.container)
}
