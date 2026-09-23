import SwiftUI

/// The chooser that runs before sign-in.
///
/// Two audiences, one binary — Guideline 4.3(a) forbids shipping the same app
/// twice under different bundle ids, so the split happens here instead.
///
/// The third route matters as much as the first two: Guideline 5.1.1(v) says
/// "if your app doesn't include significant account-based features, let people
/// use it without a login". Schedule and challenges are public content, so
/// they must be reachable without an account or a reviewer will call it a
/// login wall.
struct GateView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)

            VStack(spacing: Space.l) {
                Wordmark(height: 30)
                Text("Nuorten startup- ja\ninnovaatioyhdistys ry")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer(minLength: Space.xl)

            if let event = app.event {
                eventStrip(event)
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.xl)
            }

            VStack(spacing: Space.m) {
                MicroLabel("Continue as")

                choice(
                    title: "Member",
                    detail: "Attending an event, or part of the STUHI community.",
                    icon: "person",
                    action: { app.phase = .auth(.member) }
                )

                choice(
                    title: "Monk or core team",
                    detail: "You're active at STUHI and have a stuhi.org address.",
                    icon: "key",
                    action: { app.phase = .auth(.monk) }
                )
            }
            .padding(.horizontal, Space.page)

            Button {
                app.browseAnonymously()
            } label: {
                HStack(spacing: 6) {
                    Text("Just looking around")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
            }
            .padding(.top, Space.xl)

            Spacer(minLength: Space.l)
        }
    }

    private func eventStrip(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                if event.isLive { LiveDot() }
                MicroLabel(event.isLive ? "Happening now" : "Next event")
            }
            Text(event.name)
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
            HStack(spacing: Space.s) {
                Text(event.startsAt.formatted(.dateTime.day().month(.abbreviated)))
                if let venue = event.venue {
                    Text("·")
                    Text(venue).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.m)
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    private func choice(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.hairlineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
