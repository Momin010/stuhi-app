import SwiftUI

// MARK: - Role picker

/// Picking a role is the entire payload of a request or an invite. There is
/// no message field anywhere in this feature: the sender says which role they
/// would fill, or which role they want filled, and that is all that travels.
/// It is the single biggest reduction in unmoderated content in the app.
struct RolePicker: View {
    let roles: [RoleTag]
    @Binding var selection: RoleTag?

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: Space.s, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s) {
            ForEach(roles) { role in
                Button {
                    selection = selection == role ? nil : role
                } label: {
                    Tag(text: role.label, filled: selection == role, icon: role.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == role ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Person detail

/// Someone else's card, reached from the "People" list.
///
/// This is `attendee_cards` and nothing more — no roster of who they have
/// worked with, no score, no rating, no "pass" or "reject". The only outward
/// action is a directed invite naming one role, which they can accept or
/// ignore. App Store Guideline 1.2 removes apps for "objectification of real
/// people" without notice, and a reject button on a face is exactly that.
struct PersonDetailView: View {
    let person: AttendeeCard
    let myTeam: MyTeam?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var neededRoles: [RoleTag] = []
    @State private var chosenRole: RoleTag?
    @State private var challengeTitle: String?
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?
    @State private var showReport = false
    @State private var showBlockConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                if !person.roles.isEmpty {
                    section("Can do") {
                        ChipRow(tags: person.roles.map { ($0.label, $0.icon) })
                    }
                }

                // A band label written by the server — never a number.
                if let experience = person.experience, !experience.isEmpty {
                    section("Experience") {
                        Text(experience)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                    }
                }

                if let langClass = person.langClass {
                    section("Works in") {
                        ChipRow(tags: [(langClass.label, "globe")])
                    }
                }

                if let challengeTitle {
                    section("First choice challenge") {
                        Text(challengeTitle)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Bios are switched off for this event, so this comes back
                // null. Render nothing at all rather than an empty heading.
                if let bio = person.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    section("About") {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                inviteBlock
                safetyBlock
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReport) {
            ReportSheet(subject: (id: person.id, name: person.name), subjectKind: "profile")
        }
        .alert("Block \(person.name)?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) { Task { await block() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see each other in the app, neither of you can send the other a request, and you will never be placed on the same team.")
        }
        .task { await loadContext() }
    }

    private var header: some View {
        HStack(spacing: Space.l) {
            Initials(name: person.name, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.screenTitle)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let primary = person.primaryRole {
                    Text(primary.label)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s)
    }

    @ViewBuilder
    private var inviteBlock: some View {
        if sent {
            HStack(spacing: Space.s) {
                Image(systemName: "checkmark")
                Text("Invite sent. They'll see it in their team tab.")
            }
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
        } else if let team = myTeam, team.isCaptain(app.profile?.id) {
            if neededRoles.isEmpty {
                Text("Your team hasn't listed any roles it still needs, so there's nothing to invite anyone to fill yet.")
                    .font(.caption)
                    .foregroundStyle(Color.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                section("Invite to \(team.title)") {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("Pick the role you'd like them to fill. That's the whole invite — there's no message.")
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        RolePicker(roles: neededRoles, selection: $chosenRole)

                        Button("Send invite") { Task { await invite(team.id) } }
                            .buttonStyle(PrimaryButtonStyle(enabled: chosenRole != nil && !busy))
                            .disabled(chosenRole == nil || busy)
                    }
                }
            }
        } else if myTeam == nil {
            Text("Start a team first, then you can invite people to it.")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Your team's captain sends the invites.")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
        }

        if let error {
            Text(error).font(.caption).foregroundStyle(Color.live)
        }
    }

    /// Report and block must be present and findable on any screen showing
    /// another person — Guideline 1.2 requires both to exist in the binary.
    private var safetyBlock: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: Space.xl) {
                Button { showReport = true } label: {
                    Label("Report", systemImage: "flag")
                }
                Button { showBlockConfirm = true } label: {
                    Label("Block", systemImage: "hand.raised")
                }
                Spacer()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.inkSecondary)
            .padding(.vertical, Space.l)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel(title)
            content()
        }
    }

    private func loadContext() async {
        if let team = myTeam, team.isCaptain(app.profile?.id) {
            neededRoles = (try? await MatchingService.rolesNeeded(
                teamId: team.id, captainId: team.captainId
            )) ?? []
        }
        if let challengeId = person.firstChoiceChallenge, let eventId = app.event?.id {
            let all = (try? await MatchingService.challenges(eventId: eventId)) ?? []
            challengeTitle = all.first { $0.id == challengeId }?.title
        }
    }

    private func invite(_ teamId: UUID) async {
        guard let role = chosenRole else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await MatchingService.invite(teamId: teamId, profileId: person.id, role: role)
            sent = true
        } catch { self.error = error.localizedDescription }
    }

    private func block() async {
        guard let me = app.profile?.id else { return }
        do {
            try await MatchingService.block(person.id, me: me)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Team detail

/// One row of `team_cards`. A team you are not on shows a head COUNT and the
/// roles it needs — never a roster. You only ever see the members of your own
/// team, which is `my_team` and lives on the main tab.
struct TeamDetailView: View {
    let team: TeamCard
    var hasTeam: Bool

    @Environment(AppState.self) private var app

    @State private var chosenRole: RoleTag?
    @State private var challengeTitle: String?
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(team.title)
                        .font(.screenTitle)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(team.memberCount == 1 ? "1 person so far" : "\(team.memberCount) people so far")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, Space.s)

                if !facts.isEmpty {
                    ChipRow(tags: facts)
                }

                if let challengeTitle {
                    section("Challenge") {
                        Text(challengeTitle)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !team.roles.isEmpty {
                    section("Looking for") {
                        ChipRow(tags: team.roles.map { ($0.label, $0.icon) })
                    }
                }

                joinBlock

                if let error {
                    Text(error).font(.caption).foregroundStyle(Color.live)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadChallenge() }
    }

    private var facts: [(String, String?)] {
        var out: [(String, String?)] = []
        if let number = team.number { out.append(("Team \(number)", "number")) }
        if let table = team.tableNumber { out.append(("Table \(table)", "mappin.and.ellipse")) }
        if let lang = team.workingLang { out.append((lang.label, "globe")) }
        if team.takesLateJoiners { out.append(("Accepts late joiners", "clock")) }
        return out
    }

    @ViewBuilder
    private var joinBlock: some View {
        if sent {
            HStack(spacing: Space.s) {
                Image(systemName: "checkmark")
                Text("Request sent. You'll hear back in the team tab.")
            }
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
        } else if hasTeam {
            Text("You're already on a team. Leave it first if you want to join another.")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else if team.roles.isEmpty {
            Text("This team hasn't listed a role it needs, so it isn't taking requests right now.")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            section("Ask to join") {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Pick the role you'd fill. That's the whole request — there's no message.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    RolePicker(roles: team.roles, selection: $chosenRole)

                    Button("Send request") { Task { await request() } }
                        .buttonStyle(PrimaryButtonStyle(enabled: chosenRole != nil && !busy))
                        .disabled(chosenRole == nil || busy)
                }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel(title)
            content()
        }
    }

    private func loadChallenge() async {
        guard let challengeId = team.challengeId, let eventId = app.event?.id else { return }
        let all = (try? await MatchingService.challenges(eventId: eventId)) ?? []
        challengeTitle = all.first { $0.id == challengeId }?.title
    }

    private func request() async {
        guard let role = chosenRole else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await MatchingService.requestToJoin(teamId: team.id, role: role)
            sent = true
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Create team

/// `match_create_team(p_event, p_challenge, p_lang, p_name)`. The challenge
/// and the working language are required because the matcher sorts on them;
/// the name is optional, and a team without one is known by its number.
struct CreateTeamView: View {
    var onCreated: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var challengeId: UUID?
    @State private var lang: WorkLang?
    @State private var challenges: [Challenge] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    field("Team name", trailing: "optional") {
                        VStack(alignment: .leading, spacing: Space.s) {
                            TextField("", text: $name)
                                .font(.system(size: 16))
                                .padding(Space.m)
                                .background(Color.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .stroke(Color.hairline, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            Text("Leave it blank and you'll be known by your team number until you pick one.")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field("Challenge") {
                        if challenges.isEmpty {
                            Text("No challenges published yet. You'll be able to start a team once they're up.")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(spacing: 0) {
                                Rule()
                                ForEach(challenges) { challenge in
                                    Button {
                                        challengeId = challenge.id
                                    } label: {
                                        HStack(spacing: Space.m) {
                                            Image(systemName: challengeId == challenge.id ? "checkmark.circle" : "circle")
                                                .font(.system(size: 17, weight: .medium))
                                                .foregroundStyle(challengeId == challenge.id ? Color.ink : Color.hairlineStrong)
                                            Text(challenge.title)
                                                .font(.body)
                                                .foregroundStyle(Color.ink)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, Space.m)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Rule()
                                }
                            }
                        }
                    }

                    field("Working language") {
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack(spacing: Space.s) {
                                ForEach(WorkLang.allCases) { option in
                                    Button {
                                        lang = option
                                    } label: {
                                        Tag(text: option.label, filled: lang == option, icon: "globe")
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(lang == option ? [.isButton, .isSelected] : .isButton)
                                }
                                Spacer(minLength: 0)
                            }
                            Text("The language your team actually works in. People are matched to teams they can work with.")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(Color.live)
                    }

                    Button("Create team") { Task { await create() } }
                        .buttonStyle(PrimaryButtonStyle(enabled: canCreate && !busy))
                        .disabled(!canCreate || busy)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.l)
            }
            .background(Color.canvas)
            .navigationTitle("Start a team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .task { await loadChallenges() }
    }

    private var canCreate: Bool { challengeId != nil && lang != nil }

    private func field<C: View>(
        _ title: String, trailing: String? = nil, @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel(title, trailing: trailing)
            content()
        }
    }

    private func loadChallenges() async {
        guard let eventId = app.event?.id else { return }
        challenges = (try? await MatchingService.challenges(eventId: eventId)) ?? []
    }

    private func create() async {
        guard let eventId = app.event?.id, let challengeId, let lang else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await MatchingService.createTeam(
                eventId: eventId,
                challengeId: challengeId,
                lang: lang,
                name: name.trimmingCharacters(in: .whitespaces)
            )
            onCreated()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
