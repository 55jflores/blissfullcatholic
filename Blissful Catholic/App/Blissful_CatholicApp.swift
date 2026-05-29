//
//  Blissful_CatholicApp.swift
//  Blissful Catholic
//
//  App entry point. Phase 2: a local SwiftData ModelContainer is created here and
//  shared app-wide (CloudKit deferred — see [[phase2-swiftdata]]). The profile
//  store reads the container's main context.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct Blissful_CatholicApp: App {
    private let modelContainer: ModelContainer
    @State private var profile: UserProfileStore
    @State private var theme = ThemeController()
    @State private var auth = AuthStore()

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        modelContainer = container
        _profile = State(initialValue: UserProfileStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            LumenThemeProvider {
                AppRootView()
            }
            .environment(profile)
            .environment(theme)
            .environment(auth)
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) { return }
                Task { await auth.handle(url: url) }
            }
            .alert(
                "Blissful Catholic",
                isPresented: Binding(
                    get: { auth.authNotice != nil },
                    set: { if !$0 { auth.authNotice = nil } }
                )
            ) {
                Button("OK", role: .cancel) { auth.authNotice = nil }
            } message: {
                Text(auth.authNotice ?? "")
            }
        }
        .modelContainer(modelContainer)
    }
}
