import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var tab: Tab = .home

    enum Tab: Hashable {
        case home, challenges, team, pass, more
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "house") }

            ChallengesView()
                .tag(Tab.challenges)
                .tabItem { Label("Challenges", systemImage: "target") }

            // Team matching needs an account — an anonymous browser has no
            // profile to match. Rather than hide the tab and leave a hole,
            // show it and explain, so the value is visible before signing up.
            TeamView()
                .tag(Tab.team)
                .tabItem { Label("Team", systemImage: "person.2") }

            PassView()
                .tag(Tab.pass)
                .tabItem { Label("Pass", systemImage: "qrcode") }

            MoreView()
                .tag(Tab.more)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

/// Shown inside a tab when the feature genuinely needs an account.
struct SignInPrompt: View {
    let title: String
    let message: String
    @Environment(AppState.self) private var app

    var body: some View {
        EmptyStateView(
            icon: "person.crop.circle",
            title: title,
            message: message,
            actionTitle: "Sign in or create an account",
            action: { app.phase = .gate }
        )
    }
}
