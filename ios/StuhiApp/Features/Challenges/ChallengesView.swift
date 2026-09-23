import SwiftUI

/// The challenge briefs for the current event, and the full brief behind each.

struct ChallengesView: View {
    @Environment(AppState.self) private var app

    @State private var challenges: [Challenge] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader("Challenges", subtitle: app.event?.name)
                    .overlay(alignment: .bottom) { Rule() }

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && challenges.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, challenges.isEmpty {
            VStack(spacing: Space.l) {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .medium))
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.inkSecondary)

                Button("Try again") { Task { await load() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 240)
            }
            .padding(.horizontal, Space.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if challenges.isEmpty {
            EmptyStateView(
                icon: "target",
                title: "No challenges yet",
                message: app.event == nil
                    ? "Challenges appear once the next event is announced."
                    : "The briefs go live closer to the event. Check back nearer the day."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(challenges.enumerated()), id: \.element.id) { index, challenge in
                        if index > 0 { Rule() }
                        NavigationLink {
                            ChallengeDetailView(challenge: challenge)
                        } label: {
                            row(challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func row(_ challenge: Challenge) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text(String(format: "%02d", challenge.ordinal))
                .font(.display(22))
                .foregroundStyle(Color.inkTertiary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(challenge.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(challenge.summary)
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let partner = challenge.partner, !partner.isEmpty {
                    Tag(text: partner)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: Space.s)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkTertiary)
                .padding(.top, 3)
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.l)
        .contentShape(Rectangle())
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let eventId = app.event?.id else {
            challenges = []
            return
        }

        do {
            let rows: [Challenge] = try await Supabase.shared.select(
                "challenges",
                filters: [Supabase.eq("event_id", eventId)],
                order: "ordinal.asc"
            )
            challenges = rows
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct ChallengeDetailView: View {
    let challenge: Challenge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(String(format: "%02d", challenge.ordinal))
                        .font(.display(34))
                        .foregroundStyle(Color.inkTertiary)
                    Text(challenge.title)
                        .font(.screenTitle)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hasTags {
                    HStack(spacing: Space.s) {
                        if let partner = challenge.partner, !partner.isEmpty {
                            Tag(text: partner)
                        }
                        if let prize = challenge.prize, !prize.isEmpty {
                            Tag(text: prize, filled: true, icon: "trophy")
                        }
                    }
                }

                Text(challenge.summary)
                    .font(.body)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rule()

                // LocalizedStringKey is what gives Text its markdown parsing —
                // a plain String initialiser renders the asterisks literally.
                Text(LocalizedStringKey(challenge.body))
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .tint(Color.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasTags: Bool {
        !(challenge.partner ?? "").isEmpty || !(challenge.prize ?? "").isEmpty
    }
}
