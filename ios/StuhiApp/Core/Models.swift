import Foundation

// Wire models. Column names are snake_case in Postgres; CodingKeys map them
// rather than using a global key strategy, so a schema change fails loudly at
// the one model that changed instead of silently everywhere.

// MARK: - Enums

enum AccountRole: String, Codable, CaseIterable {
    case member, monk, staff, admin

    var isMonk: Bool { self != .member }
    var canScan: Bool { self == .staff || self == .admin }
    var isAdmin: Bool { self == .admin }

    var label: String {
        switch self {
        case .member: return "Member"
        case .monk:   return "Monk"
        case .staff:  return "Staff"
        case .admin:  return "Core team"
        }
    }
}

enum RoleTag: String, Codable, CaseIterable, Identifiable {
    case design, frontend, backend, hardware, ai, business, media

    var id: String { rawValue }

    var label: String {
        switch self {
        case .design:   return "Design"
        case .frontend: return "Frontend"
        case .backend:  return "Backend"
        case .hardware: return "Hardware"
        case .ai:       return "AI / ML"
        case .business: return "Business"
        case .media:    return "Media"
        }
    }

    /// SF Symbol. Every name here is verified against the SF Symbols catalogue —
    /// a wrong name renders as a blank space with no compile error.
    var icon: String {
        switch self {
        case .design:   return "paintbrush"
        case .frontend: return "macwindow"
        case .backend:  return "server.rack"
        case .hardware: return "cpu"
        case .ai:       return "brain"
        case .business: return "chart.line.uptrend.xyaxis"
        case .media:    return "video"
        }
    }
}

enum Audience: String, Codable {
    case `public`, attendee, monk
}

enum TicketState: String, Codable {
    case issued, admitted, void
}

// MARK: - Profile

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var email: String
    var fullName: String
    var displayName: String
    var accountRole: AccountRole
    var bio: String?
    var primaryRole: RoleTag?
    var secondaryRole: RoleTag?
    var skillLevel: Int?
    var languages: [String]
    var lookingForTeam: Bool
    var pushOptedIn: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, bio, languages
        case fullName = "full_name"
        case displayName = "display_name"
        case accountRole = "account_role"
        case primaryRole = "primary_role"
        case secondaryRole = "secondary_role"
        case skillLevel = "skill_level"
        case lookingForTeam = "looking_for_team"
        case pushOptedIn = "push_opted_in"
    }

    /// True once the attendee has filled in enough to be matched.
    var isMatchReady: Bool {
        primaryRole != nil && !(bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var name: String { displayName.isEmpty ? fullName : displayName }
}

// MARK: - Event

struct Event: Codable, Identifiable, Equatable {
    let id: UUID
    var slug: String
    var name: String
    var tagline: String?
    var venue: String?
    var venueAddress: String?
    var startsAt: Date
    var endsAt: Date

    enum CodingKeys: String, CodingKey {
        case id, slug, name, tagline, venue
        case venueAddress = "venue_address"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    var isLive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }

    var hasEnded: Bool { Date() > endsAt }

    /// Whole days until the event starts. Compared as calendar dates, not
    /// timestamps — comparing against "now" truncates the partial day and
    /// reads one lower than it should.
    var daysUntil: Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date())
        let to = cal.startOfDay(for: startsAt)
        return cal.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

// MARK: - Challenge

struct Challenge: Codable, Identifiable, Equatable {
    let id: UUID
    var eventId: UUID
    var ordinal: Int
    var title: String
    var summary: String
    var body: String
    var partner: String?
    var prize: String?

    enum CodingKeys: String, CodingKey {
        case id, ordinal, title, summary, body, partner, prize
        case eventId = "event_id"
    }
}

// MARK: - Schedule

struct ScheduleItem: Codable, Identifiable, Equatable {
    let id: UUID
    var eventId: UUID
    var startsAt: Date
    var endsAt: Date?
    var title: String
    var detail: String?
    var location: String?
    var kind: String
    var forAudience: Audience

    enum CodingKeys: String, CodingKey {
        case id, title, detail, location, kind
        case eventId = "event_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case forAudience = "for_audience"
    }

    var isMeal: Bool { kind == "meal" }

    var isNow: Bool {
        let now = Date()
        guard now >= startsAt else { return false }
        return now <= (endsAt ?? startsAt.addingTimeInterval(3600))
    }

    var icon: String {
        switch kind {
        case "meal":     return "fork.knife"
        case "ceremony": return "trophy"
        case "break":    return "cup.and.saucer"
        default:         return "calendar"
        }
    }
}

// MARK: - Announcement

struct Announcement: Codable, Identifiable, Equatable {
    let id: UUID
    var eventId: UUID?
    var title: String
    var body: String
    var forAudience: Audience
    var pinned: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, pinned
        case eventId = "event_id"
        case forAudience = "for_audience"
        case createdAt = "created_at"
    }

    var isInternal: Bool { forAudience == .monk }
}

// MARK: - Ticket

struct Ticket: Codable, Identifiable, Equatable {
    let id: UUID
    var eventId: UUID
    var profileId: UUID
    var code: String
    var state: TicketState
    var admittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, code, state
        case eventId = "event_id"
        case profileId = "profile_id"
        case admittedAt = "admitted_at"
    }
}

// MARK: - Errors

enum StuhiError: LocalizedError {
    case notSignedIn
    case http(Int, String)
    case decoding(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You need to sign in first."
        case .http(let code, let body):
            // Surface Supabase's own message when it gives one — it is usually
            // the actually useful sentence.
            if let msg = Self.extractMessage(body) { return msg }
            return "Server error (\(code))."
        case .decoding(let what):
            return "Couldn't read the response (\(what))."
        case .message(let m):
            return m
        }
    }

    private static func extractMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in ["msg", "message", "error_description", "error", "hint"] {
            if let s = obj[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
