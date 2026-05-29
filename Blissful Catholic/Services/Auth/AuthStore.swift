//
//  AuthStore.swift
//  Blissful Catholic
//
//  Observable auth state (Phase 4). The app is LOCAL-FIRST: you can pray, journal,
//  and use the Rosary with no account. Sign-in is only needed for AI features
//  (and, later, Plus + sync). This store holds the current session and exposes a
//  fresh access token for the AI proxy.
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit
import CryptoKit

enum AuthError: LocalizedError {
    case noPresenter
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Couldn't open the sign-in screen. Please try again."
        case .missingIDToken: return "Google didn't return a valid token. Please try again."
        }
    }
}

@MainActor
@Observable
final class AuthStore {
    /// The current Supabase session, or nil when signed out.
    private(set) var session: Session?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }

    /// One-shot message to surface after an auth deep link resolves (shown by the
    /// app root, then cleared).
    var authNotice: String?

    private let client = SupabaseManager.shared.client

    init() {
        // Restore a persisted session on launch (Supabase keeps it in the Keychain).
        // `try?` → nil on a fresh install with no stored session.
        Task { session = try? await client.auth.session }
    }

    // MARK: Email

    func signIn(email: String, password: String) async throws {
        session = try await client.auth.signIn(email: email, password: password)
    }

    /// Creates an account. With "Confirm email" OFF, a session comes back
    /// immediately; if it's ON, `session` stays nil and the caller should tell the
    /// user to check their inbox.
    func signUp(email: String, password: String) async throws {
        _ = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: SupabaseConfig.authRedirectURL
        )
        session = try? await client.auth.session
    }

    /// Completes an auth deep link (email confirmation, magic link). Auto-signs the
    /// user in when possible; otherwise reports that the email is confirmed (the
    /// verify step already confirmed it server-side before this redirect).
    func handle(url: URL) async {
        do {
            session = try await client.auth.session(from: url)
            authNotice = "You're signed in. Welcome."
        } catch {
            authNotice = "Your email is confirmed. Please sign in."
        }
    }

    // MARK: Google (native)

    /// Native Google Sign-In: get a Google ID token via GIDSignIn, then exchange it
    /// with Supabase.
    func signInWithGoogle() async throws {
        GIDSignIn.sharedInstance.configuration =
            GIDConfiguration(clientID: SupabaseConfig.googleIOSClientID)

        guard let presenter = Self.topViewController() else { throw AuthError.noPresenter }

        // GoogleSignIn embeds a nonce in the ID token, so we must control it: hash
        // goes to Google (lands in the token), raw goes to Supabase (it re-hashes
        // and compares). Lets us keep "Skip nonce checks" OFF.
        let nonce = Self.makeNonce()

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce.hashed
            )
        } catch {
            // GIDSignIn user-cancel: domain com.google.GIDSignIn, code -5. Treat as a
            // silent cancellation rather than an error to surface.
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 { throw CancellationError() }
            throw error
        }
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingIDToken }
        let accessToken = result.user.accessToken.tokenString

        session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nonce.raw
            )
        )
    }

    // MARK: Nonce

    /// (raw, hashed) pair. The raw nonce goes to Supabase; the SHA256 `hashed` one
    /// goes to the provider so it lands in the ID token. Used by Google and Apple.
    static func makeNonce() -> (raw: String, hashed: String) {
        let raw = randomNonce()
        return (raw, sha256(raw))
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < charset.count { result.append(charset[Int(byte)]) }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Apple (native)

    /// Exchange an Apple identity token for a Supabase session. The raw `nonce` is
    /// the one whose SHA256 was set on the Apple request (see SignInView).
    func signInWithApple(idToken: String, nonce: String) async throws {
        session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signOut() async {
        try? await client.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        session = nil
    }

    // MARK: Presentation

    /// The top-most view controller, so Google's sheet presents above the sign-in sheet.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    // MARK: For backend calls

    /// A fresh access token (the SDK refreshes it if expired). Pass this as the
    /// `Authorization: Bearer` header to the Next.js AI proxy.
    func accessToken() async -> String? {
        try? await client.auth.session.accessToken
    }
}
