import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Offline copy

/// Everything the pass needs to draw itself, and nothing more.
///
/// Five hundred people arriving at one university building will flatten the
/// wifi at exactly the moment the door needs to move, so the pass cannot
/// depend on a live request to appear. This is the small, boring subset that
/// gets written to UserDefaults: no ids, no email, nothing that would matter
/// if the device were lost.
private struct CachedPass: Codable, Equatable {
    var code: String
    var state: TicketState
    var admittedAt: Date?
    var eventName: String
    var holderName: String
}

/// One saved pass per event, so last year's code can never surface at this
/// year's door.
private enum PassCache {
    private static func key(_ eventId: UUID) -> String {
        "pass.cached.\(eventId.uuidString.lowercased())"
    }

    static func load(eventId: UUID) -> CachedPass? {
        guard let data = UserDefaults.standard.data(forKey: key(eventId)) else { return nil }
        return try? JSONDecoder().decode(CachedPass.self, from: data)
    }

    static func save(_ pass: CachedPass, eventId: UUID) {
        // A cancelled pass must never keep working offline — the whole point
        // of voiding it is that it stops opening the door.
        guard pass.state != .void else { return clear(eventId: eventId) }
        guard let data = try? JSONEncoder().encode(pass) else { return }
        UserDefaults.standard.set(data, forKey: key(eventId))
    }

    static func clear(eventId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(eventId))
    }
}

/// The attendee's own admission pass.
///
/// STUHI has no Luma Plus and therefore no Luma API — Luma is only the public
/// signup form. The app issues its own QR instead. The code below the surface
/// is 32 random hex characters and nothing else: no name, no email, no user
/// id. Somebody photographing this screen over a shoulder learns nothing.
struct PassView: View {
    @Environment(AppState.self) private var app

    @State private var ticket: Ticket?
    /// What is actually on screen — from the saved copy first, then replaced
    /// by the server's answer if it differs.
    @State private var shown: CachedPass?
    @State private var meals: [ScheduleItem] = []
    @State private var claims: [MealClaim] = []
    @State private var qr: UIImage?
    @State private var loading = true
    @State private var error: String?
    /// True when the refresh failed and what you are looking at is the saved
    /// copy. Deliberately not an error state: the QR stays up.
    @State private var showingSavedCopy = false

    /// Whatever the brightness was before we hijacked it.
    @State private var previousBrightness: CGFloat?

    private var needsAccount: Bool {
        app.isBrowsingAnonymously || app.profile == nil
    }

    /// Re-fetch whenever the signed-in person or the current event changes.
    private var reloadKey: String {
        "\(app.profile?.id.uuidString ?? "-")|\(app.event?.id.uuidString ?? "-")"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Pass", subtitle: app.event?.name)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .task(id: reloadKey) { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if needsAccount {
            centred {
                SignInPrompt(
                    title: "Your pass lives here",
                    message: "Sign in to get your admission code for STUHI events."
                )
            }
        } else if loading && shown == nil {
            centred { ProgressView().tint(Color.inkSecondary) }
        } else if let shown {
            pass(shown)
        } else if let error {
            // Nothing saved and nothing reachable. Only now is an error state
            // the honest thing to show.
            centred {
                EmptyStateView(
                    icon: "wifi.slash",
                    title: "Can't reach STUHI",
                    message: "\(error)\n\nYour pass will appear here once you're back on a connection. Open this screen once while you have signal and it stays available offline.",
                    actionTitle: "Try again",
                    action: { Task { await load() } }
                )
            }
        } else {
            centred {
                EmptyStateView(
                    icon: "qrcode",
                    title: "No pass yet",
                    message: """
                    Your pass appears here as soon as you're on the guest list for \
                    \(app.event?.name ?? "the event"). If you've already signed up, check you used \
                    the same email address here as you did on the signup form.
                    """
                )
            }
        }
    }

    private func centred<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack {
            Spacer(minLength: 0)
            inner()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The pass itself

    private func pass(_ pass: CachedPass) -> some View {
        ScrollView {
            VStack(spacing: Space.l) {
                holder(pass)
                qrPanel
                if showingSavedCopy { savedCopyNote }
                stateBlock(pass)
                if !meals.isEmpty { mealsSection }
                footnote
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xxl)
        }
        // Door scanners are cameras, and a camera cannot read a QR off a dim
        // screen — especially with auto-brightness having wound the display
        // down in a dark venue. Peg the brightness while the pass is up and
        // hand it straight back, so we don't leave someone's phone burning at
        // full blast for the rest of the day.
        .onAppear {
            if previousBrightness == nil { previousBrightness = UIScreen.main.brightness }
            UIScreen.main.brightness = 1.0
        }
        .onDisappear {
            if let previousBrightness { UIScreen.main.brightness = previousBrightness }
            previousBrightness = nil
        }
    }

    /// Drawn from the pass itself rather than from `app`, so it reads correctly
    /// even when nothing has been fetched this launch.
    private func holder(_ pass: CachedPass) -> some View {
        VStack(spacing: 2) {
            Text(pass.holderName)
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            if !pass.eventName.isEmpty {
                Text(pass.eventName)
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Space.xs)
    }

    /// Calm, small, and never in place of the code. Somebody at a door needs to
    /// know the screen is a saved copy, not to be told something went wrong.
    private var savedCopyNote: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .medium))
            Text("Saved copy — this still scans at the door.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var qrPanel: some View {
        // The QR is drawn pure black on pure white and does NOT follow the
        // colour scheme. Two reasons, both fatal at a door: readers look for
        // dark modules on a light field and mostly refuse an inverted code,
        // and a dark backing in a dark room gives the scanner's camera no
        // contrast to lock onto. So: explicit white plate, always.
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.white)

            if let qr {
                Image(uiImage: qr)
                    .resizable()
                    // No smoothing: a blurred module edge is a failed scan.
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
                    .padding(Space.l)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel("Your admission code. Show this screen to staff at the door.")
    }

    @ViewBuilder
    private func stateBlock(_ pass: CachedPass) -> some View {
        switch pass.state {
        case .issued:
            Tag(text: "NOT YET ADMITTED")

        case .admitted:
            VStack(spacing: Space.xs) {
                Tag(text: "ADMITTED", filled: true, icon: "checkmark")
                if let at = pass.admittedAt {
                    Text("Admitted at \(ScanFormat.time.string(from: at))")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

        case .void:
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("This pass is no longer valid")
                        .font(.rowTitle)
                    Text("It has been cancelled, so it won't be accepted at the door. Talk to the STUHI desk.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.live)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Color.live, lineWidth: 1)
            )
        }
    }

    // MARK: - Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("Meals", trailing: "\(claims.count) of \(meals.count)")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                        if index > 0 { Rule() }
                        mealRow(meal)
                    }
                }
            }
        }
    }

    private func mealRow(_ meal: ScheduleItem) -> some View {
        let claim = claims.first { $0.scheduleItemId == meal.id }

        return HStack(spacing: Space.m) {
            Image(systemName: "fork.knife")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.inkTertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(meal.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                Text(meal.startsAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer(minLength: Space.s)

            if claim != nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    Text("Collected").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.ink)
            } else {
                Text("Not yet")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }

    private var footnote: some View {
        VStack(spacing: Space.s) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.live)
                    .multilineTextAlignment(.center)
            }
            Text("The code is random and holds no personal details, so a photo of this screen gives nothing away. Your screen brightens on its own here — scanners need it.")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s)
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        guard !needsAccount, let profile = app.profile, let event = app.event else {
            loading = false
            return
        }
        error = nil
        showingSavedCopy = false

        // Draw the saved copy first. At a door on a flattened network the pass
        // has to be on screen now, not after a round trip — the refresh below
        // then quietly corrects it if anything has changed.
        if let saved = PassCache.load(eventId: event.id) {
            if shown != saved {
                shown = saved
                qr = qrImage(from: saved.code)
            }
            loading = false
        } else {
            loading = true
        }

        do {
            // RLS only ever hands back your own ticket, but filter anyway so a
            // second event's pass can never leak into this screen.
            let tickets: [Ticket] = try await Supabase.shared.select(
                "tickets",
                filters: [Supabase.eq("event_id", event.id), Supabase.eq("profile_id", profile.id)],
                limit: 1
            )
            ticket = tickets.first

            if let ticket {
                let fresh = CachedPass(
                    code: ticket.code,
                    state: ticket.state,
                    admittedAt: ticket.admittedAt,
                    eventName: event.name,
                    holderName: profile.name
                )
                // Redraw the QR only when the code itself moved — rendering is
                // not free and the code almost never changes.
                if qr == nil || fresh.code != shown?.code {
                    qr = qrImage(from: fresh.code)
                }
                if shown != fresh { shown = fresh }
                PassCache.save(fresh, eventId: event.id)

                // Meals are a nicety, not the thing that opens the door, so a
                // failure here must not take the pass down with it.
                if let rows: [ScheduleItem] = try? await Supabase.shared.select(
                    "schedule_items",
                    filters: [Supabase.eq("event_id", event.id), Supabase.eq("kind", "meal")],
                    order: "starts_at.asc"
                ) { meals = rows }
                if let rows: [MealClaim] = try? await Supabase.shared.select(
                    "meal_claims",
                    filters: [Supabase.eq("ticket_id", ticket.id)]
                ) { claims = rows }
            } else {
                // The server answered and says there is no ticket. Anything
                // saved is stale, so drop it.
                PassCache.clear(eventId: event.id)
                shown = nil
                qr = nil
                meals = []
                claims = []
            }
        } catch {
            if shown != nil {
                // We have something to show. Say so calmly and keep the code up.
                showingSavedCopy = true
            } else {
                self.error = error.localizedDescription
            }
        }

        loading = false
    }

    // MARK: - QR

    private func qrImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // "M" recovers from about 15% damage — enough for a fingerprint or a
        // cracked screen — without the extra modules that "Q" or "H" would add
        // to a code this short.
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        // The generator emits roughly one pixel per module. Scale the CIImage
        // itself by a whole number so every module lands on an exact block of
        // pixels; letting the view stretch the tiny original would soften the
        // edges and a scanner would hunt for the finder patterns.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
