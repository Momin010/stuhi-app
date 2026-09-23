import Foundation
import Observation

/// Everything the whole app needs to know: who you are, which event is on,
/// and whether we are still finding out.
@Observable
final class AppState {
    enum Phase: Equatable {
        case launching      // restoring a stored session
        case gate           // the member / monk chooser, before sign-in
        case auth(AuthIntent)
        case signedIn
    }

    enum AuthIntent: Equatable {
        case member, monk

        var title: String { self == .monk ? "Monk sign in" : "Sign in" }
    }

    var phase: Phase = .launching
    var profile: Profile?
    var event: Event?
    var loadError: String?

    /// Set when someone browses without an account. They see the schedule and
    /// the challenges and nothing else — required by 5.1.1(v), which says to
    /// let people use the app without a login where we reasonably can.
    var isBrowsingAnonymously = false

    var role: AccountRole { profile?.accountRole ?? .member }
    var isMonk: Bool { role.isMonk }
    var canScan: Bool { role.canScan }

    // MARK: - Boot

    @MainActor
    func boot() async {
        // Profile and event in parallel — the launch screen waits for one
        // round trip, not two.
        async let event: Void = loadEvent()
        if await Supabase.shared.isSignedIn {
            do {
                try await loadMe()
                phase = .signedIn
            } catch {
                // A dead token, a deleted account, or the server being down.
                // Fall back to the gate rather than a broken signed-in shell.
                await Supabase.shared.clearSession()
                phase = .gate
            }
        } else {
            phase = .gate
        }
        await event
    }

    @MainActor
    func loadMe() async throws {
        let rows: [Profile] = try await Supabase.shared.select(
            "profiles",
            filters: [URLQueryItem(name: "id", value: "eq.\(try await currentUserId())")],
            limit: 1
        )
        guard let me = rows.first else {
            throw StuhiError.message("Your profile hasn't been created yet. Try signing in again.")
        }
        profile = me
    }

    /// The user id is inside the JWT; decoding it locally avoids a round trip.
    private func currentUserId() async throws -> String {
        guard let token = TokenStore.load()?.accessToken else { throw StuhiError.notSignedIn }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw StuhiError.notSignedIn }

        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }

        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String
        else { throw StuhiError.notSignedIn }
        return sub
    }

    @MainActor
    func loadEvent() async {
        do {
            // The soonest event that hasn't finished. Anonymous read is fine —
            // published events are public by policy.
            let rows: [Event] = try await Supabase.shared.select(
                "events",
                order: "starts_at.asc",
                limit: 1,
                authed: await Supabase.shared.isSignedIn
            )
            event = rows.first
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Transitions

    /// Throws so the sign-in screen can show why. Swallowing this error was
    /// why the sign-in button sometimes just stopped spinning and did nothing.
    @MainActor
    func signedIn() async throws {
        async let event: Void = loadEvent()
        try await loadMe()
        isBrowsingAnonymously = false
        await event
        phase = .signedIn
    }

    @MainActor
    func signOut() async {
        await Supabase.shared.signOut()
        profile = nil
        isBrowsingAnonymously = false
        phase = .gate
    }

    @MainActor
    func browseAnonymously() {
        isBrowsingAnonymously = true
        phase = .signedIn
    }
}
