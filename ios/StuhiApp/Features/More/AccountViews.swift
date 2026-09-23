import SwiftUI
import UIKit
import UserNotifications

// MARK: - Notifications

/// Push settings.
///
/// Guideline 4.5.4: push notifications may not be required to use the app.
/// Saying that plainly in the UI — not only in the privacy policy — is what a
/// reviewer looks for, so the sentence below is load-bearing. The toggle is
/// off by default and everything in the app works with it off.
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var optedIn = false
    @State private var systemDenied = false
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Toggle(isOn: Binding(
                        get: { optedIn },
                        set: { newValue in
                            optedIn = newValue
                            Task { await apply(newValue) }
                        }
                    )) {
                        HStack(spacing: Space.m) {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.ink)
                            Text("Push notifications")
                                .font(.rowTitle)
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .tint(Color.ink)
                    .disabled(busy)

                    Rule()
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    MicroLabel("What we'd send you")
                    bullet("When food is out, so you don't miss a meal.")
                    bullet("Changes to the schedule — a session moving room or time.")
                    bullet("Your team placement, once you've been put on a team.")
                }

                Text("That's the whole list. We don't send marketing, and we don't send anything at night.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rule()

                Text("Notifications are completely optional. Every part of the app works with them switched off — the schedule, your pass, team matching, all of it. You'll just have to check the app yourself instead of us tapping you on the shoulder.")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if systemDenied {
                    deniedNote
                }

                if let error {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                        Text(error)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.live)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.l)
        }
        .background(Color.canvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var deniedNote: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Notifications are turned off for STUHI in iOS")
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                Text("You've said no to notifications for this app at the system level, so we can't send any until that changes. It's your choice — the app works fine without them.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Space.xs)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text("—")
                .font(.body)
                .foregroundStyle(Color.inkTertiary)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Load / apply

    private func load() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemDenied = settings.authorizationStatus == .denied
        if !loaded {
            optedIn = app.profile?.pushOptedIn ?? false
            loaded = true
        }
    }

    private func apply(_ wantsPush: Bool) async {
        guard let id = app.profile?.id else { return }
        busy = true
        error = nil

        var allowed = wantsPush
        if wantsPush {
            do {
                allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                allowed = false
            }
            if !allowed {
                // Either they said no in the prompt, or iOS never showed one
                // because it was already denied. Reflect reality in the UI.
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                systemDenied = settings.authorizationStatus == .denied
                optedIn = false
            } else {
                systemDenied = false
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        }

        do {
            try await Supabase.shared.update(
                "profiles",
                filters: [Supabase.eq("id", id)],
                values: ["push_opted_in": allowed]
            )
            try await app.loadMe()
        } catch {
            self.error = error.localizedDescription
            optedIn = app.profile?.pushOptedIn ?? false
        }
        busy = false
    }
}

// MARK: - Delete account

/// Guideline 5.1.1(v): account deletion has to be inside the app, and it has
/// to be honest about what it does. No dark patterns here — the confirmation
/// step exists so nobody deletes their account by mistake, not to talk them
/// out of it.
struct DeleteAccountView: View {
    @Environment(AppState.self) private var app

    @State private var confirmation = ""
    @State private var deleting = false
    @State private var error: String?

    private let privacyURL = URL(string: "https://stuhi.org/app-privacy")!

    private var confirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.live)
                        Text("Delete your account")
                            .font(.sectionTitle)
                            .foregroundStyle(Color.ink)
                    }
                    Text("This is permanent. Read what happens before you do it.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    MicroLabel("What gets erased")
                    point("Your name, email and bio.")
                    point("Your roles, skill level, languages and team preferences.")
                    point("Your block list, and any block someone else has on you.")
                    point("Your event pass. It stops working straight away.")
                }

                Rule()

                VStack(alignment: .leading, spacing: Space.m) {
                    MicroLabel("What STUHI keeps")
                    point("The fact that one person checked in at an event, as a number in a total. It is not linked to you, your name, or your email — we need the head count for the venue, catering and our grant reporting.")
                    point("Reports you filed stay in the moderation queue, but with your name removed from them.")
                }

                Rule()

                Text("Your account cannot be recovered afterwards. If you come back to a later STUHI event, you'll be starting from a fresh account.")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Link("Read the full retention policy", destination: privacyURL)
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .underline()

                Rule()

                VStack(alignment: .leading, spacing: Space.s) {
                    MicroLabel("Type DELETE to confirm")
                    TextField("", text: $confirmation)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(Space.m)
                        .background(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .stroke(confirmed ? Color.live : Color.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }

                if let error {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                        Text(error)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.live)
                }

                Button {
                    Task { await deleteAccount() }
                } label: {
                    Text(deleting ? "Deleting…" : "Delete my account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(confirmed && !deleting ? Color.live : Color.inkTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!confirmed || deleting)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.l)
        }
        .background(Color.canvas)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(deleting)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text("—")
                .font(.body)
                .foregroundStyle(Color.inkTertiary)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func deleteAccount() async {
        guard confirmed, !deleting else { return }
        deleting = true
        error = nil
        do {
            try await Supabase.shared.rpcVoid("delete_my_account")
            // Only sign out once the server has confirmed the deletion —
            // signing out first would leave someone stranded with a live
            // account and no way back to this screen.
            await app.signOut()
        } catch {
            // Still signed in, account untouched. Say so plainly so nobody is
            // left wondering whether it half-worked.
            self.error = "We couldn't delete your account just now — \(error.localizedDescription) Nothing has been deleted and you're still signed in. Try again, or email app@stuhi.org and we'll do it for you."
            deleting = false
        }
    }
}
