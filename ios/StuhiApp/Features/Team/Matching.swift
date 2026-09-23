import Foundation

// Every matching query lives here, deliberately.
//
// The app never touches a raw matching table. It reads four views and calls
// the `match_*` functions, because both of those enforce row-level security
// and hide anybody either side has blocked. A raw table read comes back empty
// or, worse, plausible but wrong.
//
//   team_cards     — the team browse surface. A size COUNT, never a roster.
//   attendee_cards — the only surface on which one attendee sees another.
//   my_links       — my requests and invites, split by `my_side`.
//   my_team        — my own roster, one row per member.
//
// The shape of the feature:
//   * A team declares the roles it still NEEDS.
//   * A person with no team sends a REQUEST naming the role they would fill.
//   * A team sends an INVITE naming the role they want filled.
//   * Both are directed, both need the other side to accept, and neither
//     carries a free-text message — the entire payload is a role code. That
//     is the whole moderation story for this feature, and it is why there is
//     no message field anywhere below.
//   * There is no swiping, rating or ranking of people. App Store Guideline
//     1.2 treats that as objectification and pulls apps for it.

// MARK: - Enums

/// `work_lang_t`. The language a team actually works in.
enum WorkLang: String, Codable, CaseIterable, Identifiable {
    case fi, en

    var id: String { rawValue }

    /// Shown on a chip, in the language itself.
    var label: String { self == .fi ? "Suomi" : "English" }

    /// Shown in a sentence.
    var longLabel: String { self == .fi ? "Finnish" : "English" }
}

/// `lang_class_t`. What an attendee can work in.
enum LangClass: String, Codable {
    case fiOnly = "fi_only"
    case enOnly = "en_only"
    case both

    var label: String {
        switch self {
        case .fiOnly: return "Finnish only"
        case .enOnly: return "English only"
        case .both:   return "Finnish or English"
        }
    }
}

/// `link_dir_t`.
enum LinkDirection: String, Codable {
    /// A person asking to join a team.
    case request
    /// A team asking a person to join.
    case invite
}

/// Which end of a link I am on. `my_links.my_side` reports the SIDE, not the
/// role in the exchange: 'person' if I am the attendee on the link, 'team' if
/// I am on the team it points at. Whether that makes me sender or recipient
/// depends on the direction — see `MyLink.needsMyAnswer`.
enum LinkSide: String, Codable {
    case person, team
}

// MARK: - View models

/// One row of `team_cards`. There is deliberately no roster and no
/// description here: you get a count, and the roles they still need.
struct TeamCard: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var eventId: UUID?
    var number: Int?
    var tableNumber: Int?
    var challengeId: UUID?
    var workingLang: WorkLang?
    var name: String?
    var acceptsLate: Bool?
    var state: String?
    var size: Int?
    var neededRoles: [RoleTag]?

    enum CodingKeys: String, CodingKey {
        case id, number, name, state, size
        case eventId = "event_id"
        case tableNumber = "table_number"
        case challengeId = "challenge_id"
        case workingLang = "working_lang"
        case acceptsLate = "accepts_late"
        case neededRoles = "needed_roles"
    }

    /// Teams are numbered before they are named, so a card can have no name.
    var title: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let number { return "Team \(number)" }
        return "Team"
    }

    var memberCount: Int { size ?? 0 }
    var roles: [RoleTag] { neededRoles ?? [] }
    var takesLateJoiners: Bool { acceptsLate ?? false }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One row of `attendee_cards` — everything one attendee may see about
/// another, and nothing else.
struct AttendeeCard: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var displayName: String?
    var primaryRole: RoleTag?
    var secondaryRole: RoleTag?
    /// A band LABEL such as "Some experience". Never a number, never a score.
    var experience: String?
    var langClass: LangClass?
    var firstChoiceChallenge: UUID?
    /// Null while `events.bio_enabled` is false, which it currently is.
    var bio: String?

    enum CodingKeys: String, CodingKey {
        case id, experience, bio
        case displayName = "display_name"
        case primaryRole = "primary_role"
        case secondaryRole = "secondary_role"
        case langClass = "lang_class"
        case firstChoiceChallenge = "first_choice_challenge"
    }

    var name: String {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Attendee" : trimmed
    }

    var roles: [RoleTag] { [primaryRole, secondaryRole].compactMap { $0 } }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The other side of a link, from `match_link_card`. It has no id column —
/// on purpose: an invite you received tells you who sent it, not their row.
struct LinkPersonCard: Decodable, Equatable {
    var displayName: String?
    var primaryRole: RoleTag?
    var secondaryRole: RoleTag?
    var experience: String?
    var langClass: LangClass?
    var firstChoiceChallenge: UUID?
    var bio: String?

    enum CodingKeys: String, CodingKey {
        case experience, bio
        case displayName = "display_name"
        case primaryRole = "primary_role"
        case secondaryRole = "secondary_role"
        case langClass = "lang_class"
        case firstChoiceChallenge = "first_choice_challenge"
    }

    var name: String {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Someone" : trimmed
    }
}

/// One row of `my_links`.
struct MyLink: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var teamId: UUID?
    var profileId: UUID?
    var direction: LinkDirection?
    var roleCode: RoleTag?
    var createdAt: Date?
    var expiresAt: Date?
    var mySide: LinkSide?
    /// Deliberately uniform server-side copy. Dismissed, expired and
    /// superseded all collapse into one string so that nobody learns they
    /// were specifically turned down. Show it verbatim; never reword it and
    /// never name the other party.
    var outcome: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, outcome
        case teamId = "team_id"
        case profileId = "profile_id"
        case roleCode = "role_code"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case mySide = "my_side"
    }

    /// Still waiting on somebody. An unresolved link carries no outcome.
    var isOpen: Bool {
        guard let outcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outcome.isEmpty
        else { return true }
        return ["pending", "open", "waiting"].contains(outcome.lowercased())
    }

    var side: LinkSide { mySide ?? .person }

    /// True when the other party is waiting on me.
    ///
    /// A request points at a team, so the TEAM answers it. An invite points at
    /// a person, so the PERSON answers it. Getting this backwards files live
    /// requests under "Earlier" and silently strands people, which is the exact
    /// failure this feature exists to prevent.
    var needsMyAnswer: Bool {
        switch (direction, side) {
        case (.request, .team):   return true
        case (.invite,  .person): return true
        default:                  return false
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One row of `my_team` — one member of my own team.
struct MyTeamRow: Codable, Identifiable, Equatable, Hashable {
    var teamId: UUID
    var number: Int?
    var tableNumber: Int?
    var challengeId: UUID?
    var workingLang: WorkLang?
    var name: String?
    var captainId: UUID?
    var profileId: UUID
    var displayName: String?
    var roleInTeam: RoleTag?
    var joinedVia: String?
    var joinedAt: Date?
    var isTableHost: Bool?

    var id: String { "\(teamId.uuidString)-\(profileId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case number, name
        case teamId = "team_id"
        case tableNumber = "table_number"
        case challengeId = "challenge_id"
        case workingLang = "working_lang"
        case captainId = "captain_id"
        case profileId = "profile_id"
        case displayName = "display_name"
        case roleInTeam = "role_in_team"
        case joinedVia = "joined_via"
        case joinedAt = "joined_at"
        case isTableHost = "is_table_host"
    }

    var memberName: String {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Team-mate" : trimmed
    }
}

/// My team, folded up from its rows. `my_team` repeats the team columns on
/// every member row, so the header is taken from the first one.
struct MyTeam: Identifiable, Equatable, Hashable {
    let id: UUID
    var number: Int?
    var tableNumber: Int?
    var challengeId: UUID?
    var workingLang: WorkLang?
    var name: String?
    var captainId: UUID?
    var members: [MyTeamRow]

    var title: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let number { return "Team \(number)" }
        return "Your team"
    }

    func isCaptain(_ profileId: UUID?) -> Bool {
        guard let profileId, let captainId else { return false }
        return profileId == captainId
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(rows: [MyTeamRow]) {
        guard let first = rows.first else { return nil }
        id = first.teamId
        number = first.number
        tableNumber = first.tableNumber
        challengeId = first.challengeId
        workingLang = first.workingLang
        name = first.name
        captainId = first.captainId
        members = rows.sorted { a, b in
            // Captain first, then in joining order.
            if a.profileId == first.captainId { return true }
            if b.profileId == first.captainId { return false }
            return (a.joinedAt ?? .distantPast) < (b.joinedAt ?? .distantPast)
        }
    }
}

// MARK: - Service

enum MatchingService {

    /// What a `jsonb`-returning `match_*` function hands back. Every field is
    /// optional because the functions answer in whichever shape suits them;
    /// all we need out of it is "did this go wrong, and what do I tell them".
    struct LinkResult: Decodable {
        var ok: Bool?
        var status: String?
        var message: String?
        var error: String?
        var reason: String?

        var problem: String? {
            if let error, !error.isEmpty { return error }
            guard ok == false else { return nil }
            if let message, !message.isEmpty { return message }
            if let reason, !reason.isEmpty { return reason }
            return "That didn't go through. Try again in a moment."
        }
    }

    private struct ProfileIdRow: Decodable {
        let profileId: UUID
        enum CodingKeys: String, CodingKey { case profileId = "profile_id" }
    }

    // ── Reading ───────────────────────────────────────────────────────────

    /// The id of the team I am on, or nil. Scalar uuid, nullable.
    static func myTeamId() async throws -> UUID? {
        try await Supabase.shared.rpc("match_my_team", [:], as: UUID?.self)
    }

    /// Whether this profile has filled in enough to be matched. The server
    /// owns the definition of "enough" — the app must not second-guess it,
    /// because it changes with the event's settings (bios are off right now).
    static func profileIsComplete(_ profileId: UUID) async throws -> Bool {
        try await Supabase.shared.rpc(
            "match_profile_is_complete",
            ["p_profile": profileId.uuidString.lowercased()],
            as: Bool.self
        )
    }

    /// My own roster. One row per member; nobody else's roster is readable.
    static func myTeam(id: UUID) async throws -> MyTeam? {
        let rows: [MyTeamRow] = try await Supabase.shared.select(
            "my_team", filters: [Supabase.eq("team_id", id)]
        )
        return MyTeam(rows: rows)
    }

    /// The team browse surface for an event.
    static func teamCards(eventId: UUID) async throws -> [TeamCard] {
        try await Supabase.shared.select(
            "team_cards",
            filters: [Supabase.eq("event_id", eventId)],
            order: "number.asc.nullslast",
            limit: 100
        )
    }

    /// One team card by id — used to read my own team's needed roles.
    static func teamCard(id: UUID) async throws -> TeamCard? {
        let rows: [TeamCard] = try await Supabase.shared.select(
            "team_cards", filters: [Supabase.eq("id", id)], limit: 1
        )
        return rows.first
    }

    /// The roles a captain's team still needs.
    static func rolesNeeded(byCaptain captainId: UUID) async throws -> [RoleTag] {
        let roles: [RoleTag]? = try await Supabase.shared.rpc(
            "match_roles_needed_by",
            ["p_captain": captainId.uuidString.lowercased()],
            as: [RoleTag]?.self
        )
        return roles ?? []
    }

    /// The roles my team is asking for. The card is the cheaper answer; the
    /// function is the fallback for when my own team isn't on the browse
    /// surface (it stops being listed once it fills up).
    static func rolesNeeded(teamId: UUID, captainId: UUID?) async throws -> [RoleTag] {
        if let card = try? await teamCard(id: teamId), !card.roles.isEmpty {
            return card.roles
        }
        guard let captainId else { return [] }
        return (try? await rolesNeeded(byCaptain: captainId)) ?? []
    }

    /// People to browse. The function returns ids only — it decides who is
    /// visible — and `attendee_cards` turns them into something showable.
    static func browsePeople(limit: Int = 50) async throws -> [AttendeeCard] {
        let ids: [ProfileIdRow] = try await Supabase.shared.rpc(
            "match_browse_people", ["p_limit": limit], as: [ProfileIdRow].self
        )
        let order = ids.map(\.profileId)
        guard !order.isEmpty else { return [] }

        let cards: [AttendeeCard] = try await Supabase.shared.select(
            "attendee_cards", filters: [inFilter("id", order)]
        )
        // Keep the order the function chose; it is the ranking.
        let byId = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byId[$0] }
    }

    static func attendeeCard(id: UUID) async throws -> AttendeeCard? {
        let rows: [AttendeeCard] = try await Supabase.shared.select(
            "attendee_cards", filters: [Supabase.eq("id", id)], limit: 1
        )
        return rows.first
    }

    /// Every link I am part of, newest first. Split it on `my_side`.
    static func myLinks() async throws -> [MyLink] {
        try await Supabase.shared.select(
            "my_links", order: "created_at.desc", limit: 100
        )
    }

    /// The person on the other end of a link.
    static func linkCard(_ linkId: UUID) async throws -> LinkPersonCard? {
        let rows: [LinkPersonCard] = try await Supabase.shared.rpc(
            "match_link_card",
            ["p_link": linkId.uuidString.lowercased()],
            as: [LinkPersonCard].self
        )
        return rows.first
    }

    /// Cards for a batch of links, keyed by link id. Best effort — one that
    /// fails leaves that row reading "Someone" rather than failing the screen.
    static func linkCards(_ links: [MyLink]) async -> [UUID: LinkPersonCard] {
        // Concurrent: one round trip of wait, not one per link.
        await withTaskGroup(of: (UUID, LinkPersonCard?).self) { group in
            for link in links {
                group.addTask { (link.id, try? await linkCard(link.id)) }
            }
            var out: [UUID: LinkPersonCard] = [:]
            for await (id, card) in group { out[id] = card }
            return out
        }
    }

    static func challenges(eventId: UUID) async throws -> [Challenge] {
        try await Supabase.shared.select(
            "challenges",
            filters: [Supabase.eq("event_id", eventId)],
            order: "ordinal.asc"
        )
    }

    // ── Writing ───────────────────────────────────────────────────────────

    /// Returns the new team's id.
    static func createTeam(
        eventId: UUID, challengeId: UUID, lang: WorkLang, name: String?
    ) async throws -> UUID? {
        var args: [String: Any] = [
            "p_event": eventId.uuidString.lowercased(),
            "p_challenge": challengeId.uuidString.lowercased(),
            "p_lang": lang.rawValue,
        ]
        if let name, !name.isEmpty { args["p_name"] = name }
        return try await Supabase.shared.rpc("match_create_team", args, as: UUID?.self)
    }

    /// Ask to join a team, offering to fill one role. No message: the role
    /// code is the whole payload.
    static func requestToJoin(teamId: UUID, role: RoleTag) async throws {
        try await sendLink(teamId: teamId, direction: .request, role: role, profileId: nil)
    }

    /// Invite someone to fill one role on my team.
    static func invite(teamId: UUID, profileId: UUID, role: RoleTag) async throws {
        try await sendLink(teamId: teamId, direction: .invite, role: role, profileId: profileId)
    }

    private static func sendLink(
        teamId: UUID, direction: LinkDirection, role: RoleTag, profileId: UUID?
    ) async throws {
        var args: [String: Any] = [
            "p_team": teamId.uuidString.lowercased(),
            "p_dir": direction.rawValue,
            "p_role": role.rawValue,
        ]
        if let profileId { args["p_profile"] = profileId.uuidString.lowercased() }
        try await call("match_send_link", args)
    }

    /// Accepting is one server-side step: it joins the team, resolves this
    /// link and supersedes my other open ones. Doing that in the app would
    /// leave somebody on two teams if the network dropped halfway.
    static func accept(linkId: UUID) async throws {
        try await call("match_accept_link", ["p_link": linkId.uuidString.lowercased()])
    }

    /// Dismissing is silent. The other side sees the same uniform outcome
    /// string as an expired link — they are never told they were turned down.
    static func dismiss(linkId: UUID) async throws {
        try await call("match_dismiss_link", ["p_link": linkId.uuidString.lowercased()])
    }

    static func withdraw(linkId: UUID) async throws {
        try await call("match_withdraw_link", ["p_link": linkId.uuidString.lowercased()])
    }

    /// Fire-and-forget read receipt for something in my inbox.
    static func markSeen(linkId: UUID) async {
        try? await Supabase.shared.rpcVoid(
            "match_mark_seen", ["p_link": linkId.uuidString.lowercased()]
        )
    }

    static func leaveTeam(reason: String = "self") async throws {
        try await call("match_leave_team", ["p_reason": reason])
    }

    static func setLookingForTeam(_ looking: Bool, profileId: UUID) async throws {
        try await Supabase.shared.update(
            "profiles",
            filters: [Supabase.eq("id", profileId)],
            values: ["looking_for_team": looking]
        )
    }

    static func block(_ otherId: UUID, me: UUID) async throws {
        try await Supabase.shared.insertRaw("blocks", [
            "blocker_id": me.uuidString.lowercased(),
            "blocked_id": otherId.uuidString.lowercased(),
        ])
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// Call a `jsonb`-returning function and surface its own complaint, if it
    /// made one, as the error the screen shows. A body we can't parse is not
    /// a failure — the call returned 2xx, so the work was done.
    private static func call(_ name: String, _ args: [String: Any]) async throws {
        do {
            let result = try await Supabase.shared.rpc(name, args, as: LinkResult.self)
            if let problem = result.problem { throw StuhiError.message(problem) }
        } catch is DecodingError {
            return
        }
    }

    /// PostgREST `in.(a,b,c)`.
    static func inFilter(_ column: String, _ ids: [UUID]) -> URLQueryItem {
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        return URLQueryItem(name: column, value: "in.(\(list))")
    }
}
