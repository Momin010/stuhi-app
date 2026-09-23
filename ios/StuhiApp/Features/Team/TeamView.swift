import SwiftUI

/// The team tab.
///
/// This exists because of a specific failure: at a previous hackathon the
/// organiser posted in a "looking for a team" Discord channel, nobody ever
/// replied, and he spent the whole event alone. A passive board is not a
/// system. So this screen never leaves someone with nothing to do — there is
/// always a next action, and if every action fails, the organisers' auto-assign
/// round places them anyway.
///
/// Everything here reads a view or calls a `match_*` function. Nothing on this
/// screen carries a free-text message: a request and an invite are a role code
/// and nothing else.
struct TeamView: View {
    @Environment(AppState.self) private var app

    @State private var myTeam: MyTeam?
    @State private var teams: [TeamCard] = []
    @State private var people: [AttendeeCard] = []
    @State private var inbox: [MyLink] = []
    @State private var outbox: [MyLink] = []
    @State private var history: [MyLink] = []
    @State private var linkCards: [UUID: LinkPersonCard] = [:]
    @State private var teamTitles: [UUID: String] = [:]
    @State private var profileComplete = true
    @State private var browse: Browse = .teams
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreate = false

    private enum Browse: String, CaseIterable {
        case teams = "Teams"
        case people = "People"
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.isBrowsingAnonymously || app.profile == nil {
                    SignInPrompt(
                        title: "Find a team",
                        message: "Sign in to fill in a short profile and get matched with people to build with."
                    )
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .background(Color.canvas)
            .navigationDestination(for: AttendeeCard.self) {
                PersonDetailView(person: $0, myTeam: myTeam)
            }
            .navigationDestination(for: TeamCard.self) {
                TeamDetailView(team: $0, hasTeam: myTeam != nil)
            }
            .sheet(isPresented: $showCreate) {
                CreateTeamView(onCreated: { Task { await load() } })
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let error { errorBanner(error) }

                if !profileComplete { setUpProfileCard }

                if !inbox.isEmpty { inboxSection }

                if let myTeam {
                    myTeamSection(myTeam)
                    if myTeam.isCaptain(app.profile?.id) { invitePeopleSection }
                } else {
                    lookingSection
                    browseSection
                }

                if !outbox.isEmpty { outboxSection }
                if !history.isEmpty { historySection }
            }
            .padding(.bottom, Space.xxl)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(
                title: "Team",
                subtitle: myTeam?.title ?? "Not on a team yet"
            ) {
                if myTeam == nil {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Start a team")
                }
            }
            .background(Color.canvas)
            .overlay(alignment: .bottom) { Rule() }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.live)
        .padding(.horizontal, Space.page)
    }

    // MARK: - Sections

    private var setUpProfileCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("First things first")
            Card {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Finish your profile")
                        .font(.rowTitle)
                        .foregroundStyle(Color.ink)
                    Text("Pick what you can do and which language you work in. Teams can't find you without it.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        Text("Set up profile")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Space.xs)
                }
            }
        }
        .padding(.horizontal, Space.page)
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Waiting on you", trailing: "\(inbox.count)")
                .padding(.horizontal, Space.page)

            VStack(spacing: Space.m) {
                ForEach(inbox) { link in
                    linkCard(link)
                }
            }
            .padding(.horizontal, Space.page)
        }
    }

    private func linkCard(_ link: MyLink) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    Initials(name: linkCards[link.id]?.name ?? "?", size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkCards[link.id]?.name ?? "Someone")
                            .font(.rowTitle)
                            .foregroundStyle(Color.ink)
                        Text(inboxLine(link))
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if let role = link.roleCode {
                    ChipRow(tags: [(role.label, role.icon)])
                }

                HStack(spacing: Space.s) {
                    Button("Accept") {
                        Task { await act { try await MatchingService.accept(linkId: link.id) } }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Not now") {
                        Task { await act { try await MatchingService.dismiss(linkId: link.id) } }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func inboxLine(_ link: MyLink) -> String {
        let team = link.teamId.flatMap { teamTitles[$0] }
        if link.direction == .invite {
            if let team { return "Invited you to join \(team)" }
            return "Invited you to join their team"
        }
        return "Wants to join your team"
    }

    private func myTeamSection(_ team: MyTeam) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Your team", trailing: "\(team.members.count)")
                .padding(.horizontal, Space.page)

            VStack(alignment: .leading, spacing: Space.s) {
                ChipRow(tags: teamFacts(team))
            }
            .padding(.horizontal, Space.page)

            VStack(spacing: 0) {
                Rule()
                ForEach(team.members) { member in
                    memberRow(member, captainId: team.captainId)
                    Rule()
                }
            }

            Button("Leave team", role: .destructive) {
                Task { await act { try await MatchingService.leaveTeam() } }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.live)
            .padding(.horizontal, Space.page)
            .padding(.top, Space.m)
        }
    }

    private func teamFacts(_ team: MyTeam) -> [(String, String?)] {
        var facts: [(String, String?)] = []
        if let number = team.number { facts.append(("Team \(number)", "number")) }
        if let table = team.tableNumber { facts.append(("Table \(table)", "mappin.and.ellipse")) }
        if let lang = team.workingLang { facts.append((lang.label, "globe")) }
        return facts
    }

    private func memberRow(_ member: MyTeamRow, captainId: UUID?) -> some View {
        HStack(spacing: Space.m) {
            Initials(name: member.memberName, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s) {
                    Text(member.memberName)
                        .font(.rowTitle)
                        .foregroundStyle(Color.ink)
                    if member.profileId == captainId {
                        Image(systemName: "star")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkTertiary)
                            .accessibilityLabel("Captain")
                    }
                }
                if let role = member.roleInTeam {
                    Tag(text: role.label, icon: role.icon)
                }
            }
            Spacer(minLength: Space.s)
            if member.isTableHost == true {
                Text("Table host")
                    .font(.micro)
                    .tracking(0.9)
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.m)
    }

    private var lookingSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text("Looking for a team")
                            .font(.rowTitle)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { app.profile?.lookingForTeam ?? false },
                            set: { value in
                                guard let me = app.profile?.id else { return }
                                Task {
                                    await act {
                                        try await MatchingService.setLookingForTeam(value, profileId: me)
                                    }
                                    try? await app.loadMe()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(.ink)
                    }
                    Text("Turn this on and teams at this event can see your card and invite you. You'll also be placed automatically if you still don't have a team when the event starts — nobody is left on their own.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.page)
        }
    }

    private var outboxSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Sent", trailing: "\(outbox.count)")
                .padding(.horizontal, Space.page)
            VStack(spacing: 0) {
                Rule()
                ForEach(outbox) { link in
                    HStack(spacing: Space.m) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.inkTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outboxLine(link))
                                .font(.body)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Waiting to hear back")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer(minLength: Space.s)
                        Button("Withdraw") {
                            Task { await act { try await MatchingService.withdraw(linkId: link.id) } }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ink)
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.m)
                    Rule()
                }
            }
        }
    }

    private func outboxLine(_ link: MyLink) -> String {
        let role = link.roleCode.map { " as \($0.label)" } ?? ""
        if link.direction == .invite {
            let who = linkCards[link.id]?.name ?? "them"
            return "You invited \(who)\(role)"
        }
        let team = link.teamId.flatMap { teamTitles[$0] } ?? "a team"
        return "You asked to join \(team)\(role)"
    }

    /// Closed links. The outcome string is written by the server and is the
    /// same for dismissed, expired and superseded — it is shown exactly as it
    /// arrives, and nothing here says who did what.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("Earlier")
                .padding(.horizontal, Space.page)
            VStack(spacing: 0) {
                Rule()
                ForEach(history) { link in
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.outcome ?? "Closed")
                                .font(.body)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let role = link.roleCode {
                                Text(role.label)
                                    .font(.caption)
                                    .foregroundStyle(Color.inkTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.m)
                    Rule()
                }
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Picker("", selection: $browse) {
                ForEach(Browse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.page)

            if browse == .teams {
                if teams.isEmpty {
                    EmptyStateView(
                        icon: "person.2",
                        title: "No teams yet",
                        message: "Teams appear here as people create them. You can start your own at any time.",
                        actionTitle: "Start a team",
                        action: { showCreate = true }
                    )
                } else {
                    VStack(spacing: 0) {
                        Rule()
                        ForEach(teams) { team in
                            NavigationLink(value: team) { teamRow(team) }
                                .buttonStyle(.plain)
                            Rule()
                        }
                    }
                }
            } else {
                peopleList
            }
        }
    }

    private var invitePeopleSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            MicroLabel("People looking for a team")
                .padding(.horizontal, Space.page)
            peopleList
        }
    }

    @ViewBuilder
    private var peopleList: some View {
        if people.isEmpty {
            EmptyStateView(
                icon: "person",
                title: "Nobody listed yet",
                message: "People show up here once they've filled in their card and turned on “looking for a team”."
            )
        } else {
            VStack(spacing: 0) {
                Rule()
                ForEach(people) { person in
                    NavigationLink(value: person) { personRow(person) }
                        .buttonStyle(.plain)
                    Rule()
                }
            }
        }
    }

    // MARK: - Rows

    private func personRow(_ person: AttendeeCard) -> some View {
        HStack(spacing: Space.m) {
            Initials(name: person.name, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                if !person.roles.isEmpty {
                    ChipRow(tags: person.roles.map { ($0.label, $0.icon) })
                } else if let experience = person.experience, !experience.isEmpty {
                    Text(experience)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: Space.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }

    /// A team card is a count and a shopping list. There is no roster here —
    /// you only ever see the members of your own team.
    private func teamRow(_ team: TeamCard) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(team.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(team.memberCount)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                Image(systemName: "person.2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
                    .accessibilityLabel("\(team.memberCount) on the team")
            }
            if !team.roles.isEmpty {
                ChipRow(tags: team.roles.prefix(3).map { ($0.label, $0.icon) })
            }
            HStack(spacing: Space.s) {
                if let lang = team.workingLang {
                    Text(lang.label)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                if team.takesLateJoiners {
                    Text("Accepts late joiners")
                        .font(.caption)
                        .foregroundStyle(Color.inkTertiary)
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Loading

    private func load() async {
        guard let me = app.profile, let eventId = app.event?.id else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // Independent reads all start at once — this screen used to wait
            // for seven round trips back to back.
            async let complete = try? MatchingService.profileIsComplete(me.id)
            async let team: MyTeam? = {
                guard let teamId = try await MatchingService.myTeamId() else { return nil }
                return try await MatchingService.myTeam(id: teamId)
            }()
            async let allLinks = MatchingService.myLinks()
            async let allTeams = MatchingService.teamCards(eventId: eventId)
            // People are worth browsing whether or not I have a team: with one,
            // it is who my team can invite.
            async let browse = try? MatchingService.browsePeople()

            let links = try await allLinks
            inbox = links.filter { $0.needsMyAnswer && $0.isOpen }
            outbox = links.filter { !$0.needsMyAnswer && $0.isOpen }
            history = Array(links.filter { !$0.isOpen }.prefix(5))
            linkCards = await MatchingService.linkCards(inbox + outbox)

            myTeam = try await team
            teams = try await allTeams
            teamTitles = Dictionary(teams.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            profileComplete = await complete ?? true
            people = await browse ?? []
            error = nil

            // Fire-and-forget: nothing on screen waits for read receipts.
            let seen = inbox.map(\.id)
            Task { for id in seen { await MatchingService.markSeen(linkId: id) } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Run a mutation then reload. Keeps every button's body to one line.
    private func act(_ work: () async throws -> Void) async {
        do {
            try await work()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A row of tags that wraps.
struct ChipRow: View {
    let tags: [(String, String?)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
            Tag(text: tag.0, icon: tag.1)
        }
    }
}

extension Profile: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
