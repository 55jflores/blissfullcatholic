//
//  SignInView.swift
//  Blissful Catholic
//
//  The sign-in sheet (Phase 4). Presented from Profile, and (next) whenever a
//  signed-out user taps an AI feature. Email first; Google + Apple buttons land
//  in the following steps. Lumen-styled.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(\.lumenTokens) private var t
    @Environment(\.lumenPalette) private var pal
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Optional context line, e.g. "Sign in to receive a personalized reflection."
    var reason: String? = nil

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var appleRawNonce = ""

    private enum Field { case email, password }
    @FocusState private var focusedField: Field?

    private var cta: String { mode == .signIn ? "Sign in" : "Create account" }
    private var togglePrompt: String {
        mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in"
    }
    private var canSubmit: Bool {
        !isWorking && email.contains("@") && password.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let reason {
                    Text(reason)
                        .font(LumenType.serif(14).italic())
                        .foregroundStyle(t.inkMid)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    field("Email", text: $email, isSecure: false)
                        .focused($focusedField, equals: .email)
                    field("Password", text: $password, isSecure: true)
                        .focused($focusedField, equals: .password)
                }

                if let errorText {
                    Text(errorText)
                        .font(LumenType.ui(12))
                        .foregroundStyle(pal.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LumenPrimaryButton(title: isWorking ? "…" : cta) { submit() }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                Button {
                    withAnimation { mode = mode == .signIn ? .signUp : .signIn; errorText = nil }
                } label: {
                    Text(togglePrompt)
                        .font(LumenType.ui(13))
                        .foregroundStyle(pal.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                dividerLabel

                SignInWithAppleButton(.signIn) { request in
                    let nonce = AuthStore.makeNonce()
                    appleRawNonce = nonce.raw
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = nonce.hashed
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(.capsule)
                .disabled(isWorking)

                Button { signInWithGoogle() } label: {
                    Image("ContinueWithGoogle")   // Google's official button (light/dark variants)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
            .padding(24)
        }
        .background(t.bg.ignoresSafeArea())
        // If a deep link (email confirmation) signs the user in while this sheet
        // is still open, close it.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Welcome", color: pal.accent)
                Text(mode == .signIn ? "Sign in" : "Create your account")
                    .font(LumenType.display(28))
                    .foregroundStyle(t.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(t.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(t.surface, in: .circle)
                    .overlay(Circle().strokeBorder(t.rule, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(LumenType.serif(15))
        .foregroundStyle(t.ink)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(t.surface, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.rule, lineWidth: 0.5))
    }

    private var dividerLabel: some View {
        HStack(spacing: 12) {
            Rectangle().fill(t.rule).frame(height: 0.5)
            Text("or").font(LumenType.ui(11)).foregroundStyle(t.inkSoft)
            Rectangle().fill(t.rule).frame(height: 0.5)
        }
        .padding(.vertical, 2)
    }

    private func signInWithGoogle() {
        focusedField = nil // dismiss the keyboard
        errorText = nil
        isWorking = true
        Task {
            do {
                try await auth.signInWithGoogle()
                if auth.isSignedIn { dismiss() }
            } catch is CancellationError {
                // user dismissed Google sheet — no error to show
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorText = "Apple didn't return a valid token. Please try again."
                return
            }
            isWorking = true
            Task {
                do {
                    try await auth.signInWithApple(idToken: idToken, nonce: appleRawNonce)
                    if auth.isSignedIn { dismiss() }
                } catch {
                    errorText = error.localizedDescription
                }
                isWorking = false
            }
        case .failure(let error):
            // User canceled the Apple sheet — not an error to surface.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorText = error.localizedDescription
        }
    }

    private func submit() {
        focusedField = nil // dismiss the keyboard
        errorText = nil
        isWorking = true
        Task {
            do {
                switch mode {
                case .signIn: try await auth.signIn(email: email, password: password)
                case .signUp: try await auth.signUp(email: email, password: password)
                }
                if auth.isSignedIn {
                    dismiss()
                } else {
                    // signUp with email confirmation ON returns no session.
                    errorText = "Check your email to confirm your account, then sign in."
                    mode = .signIn
                }
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    SignInView(reason: "Sign in to receive a personalized reflection.")
        .environment(AuthStore())
        .environment(\.lumenTokens, .parchment)
        .environment(\.lumenPalette, .for(.easter))
}
