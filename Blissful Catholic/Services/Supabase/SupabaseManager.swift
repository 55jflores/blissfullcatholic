//
//  SupabaseManager.swift
//  Blissful Catholic
//
//  The app's single Supabase client (Phase 4). Auth goes iOS → Supabase DIRECT;
//  the AI proxy goes iOS → Next.js → Claude (it needs the JWT this client mints).
//

import Foundation
import Supabase

enum SupabaseConfig {
    /// Project URL — public.
    static let url = URL(string: "https://thyxvywjmjqiyqxkjxnk.supabase.co")!

    /// The PUBLISHABLE key (sb_publishable_…). Designed to ship in clients — RLS
    /// protects the data. This is NOT the secret key (that lives only on the server).
    ///
    /// ⚠️ PASTE the full publishable key here — same value as
    ///    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in the web repo's .env.local.
    static let publishableKey = "sb_publishable_RZcSM76-aA2bsuDh9v-ZWQ_j_qnOgrI"

    /// Google iOS OAuth client ID (public — identifies the app to Google).
    /// Its reversed form is registered as a URL scheme in the target's Info → URL Types.
    static let googleIOSClientID =
        "222756209200-ucjcvrhuaq7i9iqc8od57366ucllrj4c.apps.googleusercontent.com"

    /// The Next.js backend that proxies AI calls (iOS → Next.js → Claude).
    static let apiBaseURL = URL(string: "https://blissfulcatholic.com")!

    /// Deep link Supabase redirects to after email confirmation / magic links.
    /// Registered as a URL scheme in the target's Info → URL Types, and added to
    /// Supabase → Auth → URL Configuration → Redirect URLs.
    static let authRedirectURL = URL(string: "blissfulcatholic://auth-callback")!
}

/// App-wide Supabase client singleton.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey
        )
    }
}
