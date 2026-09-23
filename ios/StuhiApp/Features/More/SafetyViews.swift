import SwiftUI

// Guideline 1.2 — the moderation surface for an app with user-generated
// content. Three things have to exist and be reachable: a way to report, a
// way to block, and published contact information (that last one lives on
// MoreView). Everything here is deliberately plain-spoken: this is one of the
// few places in the app where precision beats friendliness.

// MARK: - Blocked people

/// The list of people you've blocked, and the way back out of it.
struct BlockedListView: View {
    @Environment(AppState.self) private var app

    @State private var rows: [BlockedPerson] = []
    @State private var loading = true
    @State private var error: String?
    @State private var working: UUID?

    struct BlockedPerson: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    private struct BlockRow: Decodable {
        let blockedId: UUID
        enum CodingKeys: String, CodingKey { case blockedId = "blocked_id" }
    }

    private struct NameRow: Decodable {
        let id: UUID
        let displayName: String
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case fullName = "full_name"
        }

        var name: String { displayName.isEmpty ? fullName : displayName }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if loading {
                    ProgressView()
                        .tint(Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.xxl)
                } else if let error {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't load your block list",
                        message: error,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                } else if rows.isEmpty {
                    EmptyStateView(
                        icon: "hand.raised",
                        title: "You haven't blocked anyone",
                        message: "Blocking someone hides them from you everywhere in the app, hides you from them, and stops the two of you being placed on the same team."
                    )
                    .padding(.top, Space.xl)
                } else {
                    Text("Blocking someone hides them from you, hides you from them, and stops you being put on the same team. You can undo it here at any time.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.page)
                        .padding(.bottom, Space.l)

                    Rule()
                    ForEach(rows) { person in
                        personRow(person)
                        Rule()
                    }
                }
            }
            .padding(.vertical, Space.l)
        }
        .background(Color.canvas)
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func personRow(_ person: BlockedPerson) -> some View {
        HStack(spacing: Space.m) {
            Initials(name: person.name, size: 40)

            Text(person.name)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: Space.s)

            Button {
                Task { await unblock(person) }
            } label: {
                if working == person.id {
                    ProgressView().tint(Color.inkSecondary)
                } else {
                    Text("Unblock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, 7)
                        .overlay(Capsule().stroke(Color.hairlineStrong, lineWidth: 1))
                }
            }
            .disabled(working != nil)
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.m)
    }

    private func load() async {
        guard let me = app.profile?.id else {
            error = StuhiError.notSignedIn.localizedDescription
            loading = false
            return
        }
        loading = true
        error = nil
        do {
            // Reading `profiles` directly cannot work here: the RLS policy that
            // enforces blocking hides the blocked person from you in both
            // directions, so a plain select returns nothing and every row would
            // read "Blocked person". `my_blocked_people()` is a security definer
            // function that returns only your own block list, names included.
            struct Row: Decodable {
                let id: UUID
                let displayName: String?
                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                }
            }
            let blocked: [Row] = try await Supabase.shared.rpc(
                "my_blocked_people", [:], as: [Row].self
            )
            rows = blocked.map {
                BlockedPerson(
                    id: $0.id,
                    name: ($0.displayName?.isEmpty == false ? $0.displayName! : "Blocked person")
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func unblock(_ person: BlockedPerson) async {
        guard let me = app.profile?.id else { return }
        working = person.id
        do {
            try await Supabase.shared.delete("blocks", filters: [
                Supabase.eq("blocker_id", me),
                Supabase.eq("blocked_id", person.id),
            ])
            rows.removeAll { $0.id == person.id }
        } catch {
            self.error = error.localizedDescription
        }
        working = nil
    }
}

// MARK: - Report

/// The report form. Presented as a sheet from anywhere a person or a piece of
/// content appears.
struct ReportSheet: View {
    /// The person being reported, when there is one. `nil` means a general
    /// "something is wrong here" report.
    let subject: (id: UUID, name: String)?
    var subjectKind: String = "profile"

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String?
    @State private var detail = ""
    @State private var alsoBlock = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    private let reasons = [
        "Harassment or bullying",
        "Inappropriate content",
        "Spam",
        "Impersonation",
        "Something else",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if sent {
                    confirmation
                } else {
                    form
                }
            }
            .background(Color.canvas)
            .navigationTitle(sent ? "Report sent" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            urgentNote

            if let subject {
                VStack(alignment: .leading, spacing: Space.s) {
                    MicroLabel("You're reporting")
                    HStack(spacing: Space.m) {
                        Initials(name: subject.name, size: 40)
                        Text(subject.name)
                            .font(.rowTitle)
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel("What happened")
                Rule()
                ForEach(reasons, id: \.self) { option in
                    Button {
                        reason = option
                    } label: {
                        HStack(spacing: Space.m) {
                            Image(systemName: reason == option ? "checkmark.circle" : "circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(reason == option ? Color.ink : Color.hairlineStrong)
                            Text(option)
                                .font(.body)
                                .foregroundStyle(Color.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rule()
                }
            }

            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel("Anything else we should know", trailing: "optional")
                TextField("", text: $detail, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(3...8)
                    .padding(Space.m)
                    .background(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .stroke(Color.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                Text("Where it happened and roughly when helps us sort it out faster.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subject {
                Button {
                    alsoBlock.toggle()
                } label: {
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(systemName: alsoBlock ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(alsoBlock ? Color.ink : Color.hairlineStrong)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Block \(subject.name) as well")
                                .font(.rowTitle)
                                .foregroundStyle(Color.ink)
                            Text("You won't see each other in the app, and you won't be put on the same team.")
                                .font(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

            Button("Send report") {
                Task { await submit() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: reason != nil && !sending))
            .disabled(reason == nil || sending)
            .overlay {
                if sending { ProgressView().tint(Color.canvas) }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.l)
    }

    private var urgentNote: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Image(systemName: "flag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("Every report is read")
                        .font(.rowTitle)
                        .foregroundStyle(Color.ink)
                }
                Text("A STUHI organiser reviews every single report and decides what to do about it. Your name is not shown to the person you're reporting.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rule().padding(.vertical, Space.xs)

                Text("If someone is in danger right now, or something is happening at the event that can't wait, find a STUHI organiser in person immediately. Don't wait for a reply here.")
                    .font(.caption)
                    .foregroundStyle(Color.live)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Confirmation

    private var confirmation: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.ink)
            Text("Thanks — we've got it")
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
            Text(alsoBlock
                 ? "An organiser will look at this. We've blocked them for you as well."
                 : "An organiser will look at this. If we need anything more from you, we'll email you.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Space.m)
                .frame(maxWidth: 260)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: Submit

    private func submit() async {
        guard let reason else { return }
        guard let me = app.profile?.id else {
            error = StuhiError.notSignedIn.localizedDescription
            return
        }
        sending = true
        error = nil

        var payload: [String: Any] = [
            "reporter_id": me.uuidString.lowercased(),
            "subject_kind": subjectKind,
            "reason": reason,
        ]
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["detail"] = trimmed }

        if let subject {
            if subjectKind == "profile" {
                payload["subject_id"] = subject.id.uuidString.lowercased()
            } else {
                payload["subject_ref"] = subject.id.uuidString.lowercased()
            }
        }

        do {
            try await Supabase.shared.insertRaw("reports", payload)

            if alsoBlock, let subject {
                try await Supabase.shared.insertRaw("blocks", [
                    "blocker_id": me.uuidString.lowercased(),
                    "blocked_id": subject.id.uuidString.lowercased(),
                ])
            }
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }
}

// MARK: - Reusable report button

/// Drop this next to any person shown in the app — team matching, a team
/// roster, a profile card. Guideline 1.2 wants reporting reachable from where
/// the content actually is, not only from a settings screen.
struct ReportButton: View {
    let personId: UUID
    let personName: String
    var subjectKind: String = "profile"

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "flag")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.inkTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report \(personName)")
        .sheet(isPresented: $showing) {
            ReportSheet(
                subject: (id: personId, name: personName),
                subjectKind: subjectKind
            )
        }
    }
}
