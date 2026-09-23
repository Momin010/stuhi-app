import SwiftUI

/// Edit your own matching profile.
///
/// Two database constraints are mirrored in this UI on purpose, because
/// hitting either of them server-side produces an opaque 400 that reads like
/// the app is broken:
///   * `bio_length`   — bio is capped at 280 characters, so the field stops
///                      accepting input at 280 rather than failing on save.
///   * `roles_differ` — the secondary role may not equal the primary, so
///                      picking a primary that matches clears the secondary.
///
/// This screen must NEVER write `account_role` or `suspended_at`. There is a
/// trigger on `profiles` that raises an exception if it sees either change,
/// and that is deliberate: roles are granted by STUHI, never self-claimed.
struct ProfileEditView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private static let bioLimit = 280

    @State private var displayName = ""
    @State private var bio = ""
    @State private var primary: RoleTag?
    @State private var secondary: RoleTag?
    @State private var skillLevel: Int?
    @State private var languages: Set<String> = []
    @State private var lookingForTeam = false

    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    private let skillLabels: [(level: Int, label: String)] = [
        (1, "Just starting"),
        (2, "Some experience"),
        (3, "Confident"),
    ]

    private let languageOptions: [(code: String, label: String)] = [
        ("fi", "Suomi"),
        ("en", "English"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                nameBlock
                bioBlock
                rolesBlock
                skillBlock
                languagesBlock
                lookingBlock

                if let error {
                    noticeRow(error, icon: "exclamationmark.triangle", tint: Color.live)
                }
                if saved {
                    noticeRow("Saved.", icon: "checkmark.circle", tint: Color.inkSecondary)
                }

                Button("Save changes") {
                    Task { await save() }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSave && !saving))
                .disabled(!canSave || saving)
                .overlay {
                    if saving { ProgressView().tint(Color.canvas) }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.l)
        }
        .background(Color.canvas)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { load() }
    }

    // MARK: - Blocks

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("Display name")
            TextField("", text: $displayName)
                .font(.body)
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.words)
                .padding(Space.m)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text("This is the name other people at the event see.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var bioBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("About you", trailing: "\(bio.count) / \(Self.bioLimit)")

            TextField("", text: $bio, axis: .vertical)
                .font(.body)
                .foregroundStyle(Color.ink)
                .lineLimit(3...6)
                .padding(Space.m)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .onChange(of: bio) { _, new in
                    // Hard stop at the database's CHECK constraint. Trimming
                    // here means the save never bounces off the server.
                    if new.count > Self.bioLimit {
                        bio = String(new.prefix(Self.bioLimit))
                    }
                }

            Text("What you're good at, what you want to build, and what you'd like to learn this weekend.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rolesBlock: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel("Main role")
                chipGrid(RoleTag.allCases) { role in
                    Tag(text: role.label, filled: primary == role, icon: role.icon)
                        .onTapGesture { pickPrimary(role) }
                }
                Text("The one thing you'd most like to do on a team.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel("Second role", trailing: "optional")
                chipGrid(RoleTag.allCases) { role in
                    Tag(text: role.label, filled: secondary == role, icon: role.icon)
                        .opacity(role == primary ? 0.3 : 1)
                        .onTapGesture { pickSecondary(role) }
                }
                Text("Something else you can cover if the team needs it. It can't be the same as your main role.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var skillBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("How much have you done before")
            HStack(spacing: Space.s) {
                ForEach(skillLabels, id: \.level) { item in
                    Tag(text: item.label, filled: skillLevel == item.level)
                        .onTapGesture {
                            skillLevel = skillLevel == item.level ? nil : item.level
                        }
                }
                Spacer(minLength: 0)
            }
            Text("Nobody is filtered out for answering honestly — it just helps us mix teams properly.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languagesBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MicroLabel("Languages you're comfortable in")
            HStack(spacing: Space.s) {
                ForEach(languageOptions, id: \.code) { option in
                    Tag(text: option.label, filled: languages.contains(option.code))
                        .onTapGesture {
                            if languages.contains(option.code) {
                                languages.remove(option.code)
                            } else {
                                languages.insert(option.code)
                            }
                        }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var lookingBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Toggle(isOn: $lookingForTeam) {
                Text("Looking for a team")
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)
            }
            .tint(Color.ink)

            Text("Turn this on and your profile shows up for other people at the same event, so they can invite you onto their team. Turn it off and you're hidden again.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noticeRow(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

    // MARK: - Chip layout

    @ViewBuilder
    private func chipGrid<T: Identifiable, Chip: View>(
        _ items: [T],
        @ViewBuilder chip: @escaping (T) -> Chip
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: Space.s, alignment: .leading)],
            alignment: .leading,
            spacing: Space.s
        ) {
            ForEach(items) { item in
                HStack {
                    chip(item)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Selection

    private func pickPrimary(_ role: RoleTag) {
        if primary == role {
            primary = nil
        } else {
            primary = role
            // roles_differ: the secondary can never equal the primary.
            if secondary == role { secondary = nil }
        }
        saved = false
    }

    private func pickSecondary(_ role: RoleTag) {
        guard role != primary else { return }
        secondary = secondary == role ? nil : role
        saved = false
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Load / save

    private func load() {
        guard !loaded, let me = app.profile else { return }
        displayName = me.displayName.isEmpty ? me.fullName : me.displayName
        bio = me.bio ?? ""
        primary = me.primaryRole
        secondary = me.secondaryRole
        skillLevel = me.skillLevel
        languages = Set(me.languages)
        lookingForTeam = me.lookingForTeam
        loaded = true
    }

    private func save() async {
        guard let id = app.profile?.id else {
            error = StuhiError.notSignedIn.localizedDescription
            return
        }
        saving = true
        error = nil
        saved = false

        // Built key by key rather than as one literal so each nullable column
        // can carry a real JSON null without fighting type inference.
        var values: [String: Any] = [
            "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "languages": languages.sorted(),
            "looking_for_team": lookingForTeam,
        ]

        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBio.isEmpty {
            values["bio"] = NSNull()
        } else {
            values["bio"] = String(trimmedBio.prefix(Self.bioLimit))
        }

        if let primary {
            values["primary_role"] = primary.rawValue
        } else {
            values["primary_role"] = NSNull()
        }

        if let secondary, secondary != primary {
            values["secondary_role"] = secondary.rawValue
        } else {
            values["secondary_role"] = NSNull()
        }

        if let skillLevel {
            values["skill_level"] = skillLevel
        } else {
            values["skill_level"] = NSNull()
        }

        do {
            try await Supabase.shared.update(
                "profiles",
                filters: [Supabase.eq("id", id)],
                values: values
            )
            try await app.loadMe()
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
