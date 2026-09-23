import SwiftUI

/// The "More" tab — settings, safety and the account.
///
/// This screen is where the App Store review is won or lost, so nothing on it
/// is buried:
///   * Guideline 1.2 wants a report mechanism, a block capability and
///     published contact information for an app with user-generated content.
///     They are the SAFETY section and the "Contact STUHI" row.
///   * Guideline 5.1.1(v) wants in-app account deletion. It is the last row
///     on the screen, in plain sight, not behind a support email.
///
/// Built from ScrollView + LazyVStack + `Rule()` rather than a stock `List`,
/// because `List` drags in system greys and insets we don't use anywhere else.
struct MoreView: View {
    @Environment(AppState.self) private var app

    @State private var showingReport = false
    @State private var showingAbout = false

    private let guidelinesURL = URL(string: "https://stuhi.org/app-terms")!
    private let privacyURL = URL(string: "https://stuhi.org/app-privacy")!
    private let termsURL = URL(string: "https://stuhi.org/app-terms")!
    private let contactURL = URL(string: "mailto:app@stuhi.org")!

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if app.isBrowsingAnonymously {
                        anonymousHeader
                    } else if let profile = app.profile {
                        identityHeader(profile)
                    }

                    if !app.isBrowsingAnonymously {
                        profileSection
                    }

                    safetySection

                    if app.canScan {
                        staffSection
                    }

                    aboutSection

                    if !app.isBrowsingAnonymously {
                        accountFooter
                    }
                }
                .padding(.bottom, Space.xxl)
            }
            .background(Color.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader("More")
                    .background(Color.canvas)
            }
            .sheet(isPresented: $showingReport) {
                ReportSheet(subject: nil, subjectKind: "general")
            }
            .sheet(isPresented: $showingAbout) {
                AboutStuhiView()
            }
        }
    }

    // MARK: - Header

    private func identityHeader(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.l) {
                Initials(name: profile.name, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.sectionTitle)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)

                    Text(profile.email)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Filled once you're a monk or above, so the status reads
                    // as a status rather than another grey label.
                    Tag(text: app.role.label, filled: app.isMonk)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xl)
        }
    }

    private var anonymousHeader: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ink)
                        Text("You're just looking around")
                            .font(.rowTitle)
                            .foregroundStyle(Color.ink)
                    }
                    Text("Make an account to get your event pass, find a team and change your settings. It takes about a minute.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Sign in or create an account") {
                        app.phase = .gate
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, Space.xs)
                }
            }
            .padding(.horizontal, Space.page)
        }
        .padding(.bottom, Space.xl)
    }

    // MARK: - Sections

    private var profileSection: some View {
        section("Your profile") {
            NavigationLink { ProfileEditView() } label: {
                MoreRow(icon: "person", title: "Edit profile")
            }
            .buttonStyle(.plain)

            Rule()

            NavigationLink { NotificationSettingsView() } label: {
                MoreRow(icon: "bell", title: "Notifications")
            }
            .buttonStyle(.plain)
        }
    }

    private var safetySection: some View {
        section("Safety") {
            if !app.isBrowsingAnonymously {
                NavigationLink { BlockedListView() } label: {
                    MoreRow(icon: "hand.raised", title: "Blocked people")
                }
                .buttonStyle(.plain)

                Rule()

                Button { showingReport = true } label: {
                    MoreRow(icon: "flag", title: "Report a problem")
                }
                .buttonStyle(.plain)

                Rule()
            }

            Link(destination: guidelinesURL) {
                MoreRow(icon: "book", title: "Community guidelines", external: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var staffSection: some View {
        section("Staff") {
            NavigationLink { ScannerView() } label: {
                MoreRow(icon: "qrcode.viewfinder", title: "Scanner")
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        section("About") {
            Link(destination: privacyURL) {
                MoreRow(icon: "lock.shield", title: "Privacy policy", external: true)
            }
            .buttonStyle(.plain)

            Rule()

            Link(destination: termsURL) {
                MoreRow(icon: "doc.text", title: "Terms", external: true)
            }
            .buttonStyle(.plain)

            Rule()

            // Guideline 1.2's "published contact information". A real,
            // obvious row — not a line of small print at the bottom.
            Link(destination: contactURL) {
                MoreRow(
                    icon: "envelope",
                    title: "Contact STUHI",
                    detail: "app@stuhi.org",
                    external: true
                )
            }
            .buttonStyle(.plain)

            Rule()

            Button { showingAbout = true } label: {
                MoreRow(icon: "info.circle", title: "About STUHI")
            }
            .buttonStyle(.plain)
        }
    }

    private var accountFooter: some View {
        VStack(spacing: Space.l) {
            Button {
                Task { await app.signOut() }
            } label: {
                Text("Sign out")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.live)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }

            NavigationLink { DeleteAccountView() } label: {
                Text("Delete account")
                    .font(.caption)
                    .foregroundStyle(Color.inkTertiary)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.xl)
    }

    // MARK: - Section chrome

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(title)
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.s)

            Rule()
            VStack(spacing: 0) { content() }
            Rule()
        }
        .padding(.bottom, Space.xl)
    }
}

// MARK: - Row

/// One tappable line: symbol, title, optional detail, chevron.
private struct MoreRow: View {
    let icon: String
    let title: String
    var detail: String?
    var external: Bool = false

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            Spacer(minLength: Space.s)

            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.m + 2)
        .contentShape(Rectangle())
    }
}

// MARK: - About

/// Who we actually are, in one screen. A reviewer looking for the publisher
/// behind a teen-facing social feature should find it here without hunting.
struct AboutStuhiView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Wordmark(height: 28)
                        Text("Nuorten startup- ja innovaatioyhdistys ry")
                            .font(.body)
                            .foregroundStyle(Color.ink)
                    }

                    Rule()

                    Text("STUHI is a Finnish non-profit association run by young people, for young people. We put on hackathons and build the tools that run them — this app is one of them.")
                        .font(.body)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Space.s) {
                        MicroLabel("Get in touch")
                        Link("app@stuhi.org", destination: URL(string: "mailto:app@stuhi.org")!)
                            .font(.rowTitle)
                            .foregroundStyle(Color.ink)
                        Text("Anything about the app, your account or your data — write to us and a real person answers.")
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Rule()

                    Text(version)
                        .font(.caption)
                        .foregroundStyle(Color.inkTertiary)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.canvas)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }
}
