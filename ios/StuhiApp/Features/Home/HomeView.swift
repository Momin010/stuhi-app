import SwiftUI

/// The first tab: who's on, what's happening now, and what's just been said.
///
/// The countdown numeral is the anchor of the screen — everything else is
/// signage around it.
struct HomeView: View {
    @Environment(AppState.self) private var app

    @State private var schedule: [ScheduleItem] = []
    @State private var announcements: [Announcement] = []
    @State private var isLoading = true
    @State private var isFirstLoad = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    hero
                    if app.event != nil { nowAndNext }
                    feed
                }
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await load() }
        }
        .background(Color.canvas)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.m) {
            Wordmark(height: 18)
            Spacer(minLength: Space.m)

            if app.isBrowsingAnonymously {
                Button("Sign in") { app.phase = .gate }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
            } else if let profile = app.profile {
                Initials(name: profile.name, size: 32)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
        .overlay(alignment: .bottom) { Rule() }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let event = app.event {
            Group {
                if event.isLive {
                    liveHero(event)
                } else if event.hasEnded {
                    endedHero(event)
                } else {
                    countdownHero(event)
                }
            }
            .padding(.horizontal, Space.page)
        } else {
            EmptyStateView(
                icon: "calendar",
                title: "Nothing scheduled yet",
                message: "There's no event on the calendar right now. When the next one is announced, it lands here first."
            )
        }
    }

    private func liveHero(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                LiveDot()
                MicroLabel("Happening now")
            }
            Text(event.name)
                .font(.screenTitle)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            venueLine(event)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endedHero(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("Last event")
            Text(event.name)
                .font(.screenTitle)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("That's a wrap")
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countdownHero(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Zero days left reads as a broken counter rather than "today",
            // so that one case gets a word instead of a numeral.
            if event.daysUntil == 0 {
                Text("TODAY")
                    .font(.display(52))
                    .foregroundStyle(Color.ink)
                MicroLabel("Starts later today")
                    .padding(.top, Space.xs)
            } else {
                Text("\(event.daysUntil)")
                    .font(.display(64))
                    .foregroundStyle(Color.ink)
                MicroLabel(event.daysUntil == 1 ? "Day to go" : "Days to go")
                    .padding(.top, Space.xs)
            }

            Text(event.name)
                .font(.screenTitle)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.l)

            venueLine(event)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func venueLine(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(dateRange(event))
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)

            if let venue = event.venue, !venue.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11, weight: .medium))
                    Text(venue).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func dateRange(_ event: Event) -> String {
        let cal = Calendar.current
        let from = event.startsAt
        let to = event.endsAt
        if cal.isDate(from, inSameDayAs: to) {
            return from.formatted(.dateTime.day().month(.wide))
        }
        if cal.component(.month, from: from) == cal.component(.month, from: to) {
            let day = from.formatted(.dateTime.day())
            return "\(day)–\(to.formatted(.dateTime.day().month(.wide)))"
        }
        return "\(from.formatted(.dateTime.day().month(.abbreviated))) – \(to.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: - Now & next

    /// The item running right now, then the next two after it.
    private var upNext: [ScheduleItem] {
        let now = Date()
        let live = schedule.first(where: \.isNow).map { [$0] } ?? []
        let next = schedule.filter { !$0.isNow && $0.startsAt > now }.prefix(2)
        return live + Array(next)
    }

    private var nowAndNext: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Now & next", trailing: "See all")

            if isLoading && schedule.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.l)
            } else if let error, schedule.isEmpty {
                errorBlock(error)
            } else if upNext.isEmpty {
                Text("Nothing else on today.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.vertical, Space.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rule() }
                        scheduleRow(item)
                    }
                }
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
            }
        }
        .padding(.horizontal, Space.page)
    }

    private func scheduleRow(_ item: ScheduleItem) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            HStack(spacing: 5) {
                Text(item.startsAt.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.ink)
                if item.isNow { LiveDot() }
            }
            .frame(width: 64, alignment: .leading)

            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let location = item.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.m)
    }

    // MARK: - Feed

    private var feed: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Updates")

            if isLoading && announcements.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.l)
            } else if let error, announcements.isEmpty {
                errorBlock(error)
            } else if announcements.isEmpty {
                EmptyStateView(
                    icon: "bell",
                    title: "No updates yet",
                    message: "Anything the organisers post shows up here."
                )
            } else {
                ForEach(announcements) { announcement in
                    announcementCard(announcement)
                }
            }
        }
        .padding(.horizontal, Space.page)
    }

    private func announcementCard(_ announcement: Announcement) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                if announcement.isInternal {
                    Tag(text: "INTERNAL", filled: true, icon: "lock")
                }
                Text(announcement.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(announcement.body)
                    .font(.body)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(announcement.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.top, Space.xs)
            }
        }
        // Monk-only posts get a full-ink outline rather than the usual
        // hairline, so internal content is obvious at a glance.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.ink, lineWidth: announcement.isInternal ? 1 : 0)
        )
    }

    // MARK: - Error

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.inkSecondary)

            Button("Try again") { Task { await load() } }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, Space.s)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // The event is loaded at launch; pull-to-refresh fetches it again.
        if app.event == nil || !isFirstLoad { await app.loadEvent() }
        isFirstLoad = false

        do {
            // Announcements don't depend on the schedule — fetch both at once.
            async let posts: [Announcement] = Supabase.shared.select(
                "announcements",
                order: "pinned.desc,created_at.desc",
                limit: 20
            )
            if let eventId = app.event?.id {
                let cal = Calendar.current
                let dayStart = cal.startOfDay(for: Date())
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]

                let items: [ScheduleItem] = try await Supabase.shared.select(
                    "schedule_items",
                    filters: [
                        Supabase.eq("event_id", eventId),
                        URLQueryItem(name: "starts_at", value: "gte.\(iso.string(from: dayStart))"),
                        URLQueryItem(name: "starts_at", value: "lt.\(iso.string(from: dayEnd))"),
                    ],
                    order: "starts_at.asc"
                )
                schedule = items
            } else {
                schedule = []
            }

            // Audience filtering is the database's job — an attendee's token
            // simply never sees the monk rows.
            announcements = try await posts
        } catch {
            self.error = error.localizedDescription
        }
    }
}
