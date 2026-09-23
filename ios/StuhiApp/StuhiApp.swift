import SwiftUI

@main
struct StuhiApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.boot() }
                .tint(.ink)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            switch app.phase {
            case .launching:
                LaunchView()
            case .gate:
                GateView()
                    .transition(.opacity)
            case .auth(let intent):
                AuthView(intent: intent)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
    }
}

/// Shown only while a stored session is being restored. Deliberately just the
/// wordmark — a spinner here reads as "broken" more often than "loading".
private struct LaunchView: View {
    var body: some View {
        Wordmark(height: 26)
            .opacity(0.9)
    }
}
