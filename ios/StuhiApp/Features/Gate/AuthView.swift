import SwiftUI

struct AuthView: View {
    let intent: AppState.AuthIntent

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    /// Finland's GDPR digital-consent age is 13 (tietosuojalaki 1050/2018 § 5),
    /// and STUHI is used by upper-secondary students, so this is asked rather
    /// than assumed. Both start unticked and both are required.
    @State private var confirmedAge = false
    @State private var acceptedTerms = false
    @FocusState private var focus: Field?

    private enum Mode { case signIn, signUp }
    private enum Field { case name, email, password }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Space.l) {
                    if intent == .monk { monkNote }

                    VStack(spacing: Space.m) {
                        if mode == .signUp {
                            field("Name", text: $fullName, field: .name)
                                .textContentType(.name)
                        }
                        field("Email", text: $email, field: .email)
                            .textContentType(.username)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        secureField("Password")
                    }

                    if let error {
                        message(error, icon: "exclamationmark.triangle", tone: .live)
                    }
                    if let notice {
                        message(notice, icon: "checkmark.circle", tone: .inkSecondary)
                    }

                    if mode == .signUp { consent }

                    Button {
                        Task { await submit() }
                    } label: {
                        // The spinner replaces the label rather than sitting on
                        // top of it, so a tap visibly registers.
                        if busy {
                            ProgressView().tint(.canvas)
                        } else {
                            Text(mode == .signIn ? "Sign in" : "Create account")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                    .disabled(!canSubmit || busy)

                    if mode == .signIn {
                        Button("Forgot your password?") {
                            Task { await reset() }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                    }

                    Rule().padding(.vertical, Space.s)

                    Button {
                        withAnimation {
                            mode = mode == .signIn ? .signUp : .signIn
                            error = nil
                            // Coming back to sign in clears the consent, so the
                            // next trip through sign-up has to tick them again.
                            if mode == .signIn {
                                confirmedAge = false
                                acceptedTerms = false
                            }
                        }
                    } label: {
                        Text(mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }

                    legal
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button {
                app.phase = .gate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("Back")

            Spacer()
            Wordmark(height: 16)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Space.page - 8)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var monkNote: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "key")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.top, 1)
            Text("Monk and core team access is granted by STUHI. Sign in with the account you already use — if you don't see internal updates afterwards, ask a core team member to grant it.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(label)
            TextField("", text: text)
                .font(.system(size: 16))
                .foregroundStyle(Color.ink)
                .focused($focus, equals: field)
                .padding(.vertical, 13)
                .padding(.horizontal, Space.m)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(focus == field ? Color.ink : Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }

    private func secureField(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(label)
            SecureField("", text: $password)
                .font(.system(size: 16))
                .foregroundStyle(Color.ink)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit && !busy { Task { await submit() } } }
                .padding(.vertical, 13)
                .padding(.horizontal, Space.m)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(focus == .password ? Color.ink : Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }

    // MARK: - Consent

    /// Sign-up only. A stock `Toggle` would drag UIKit's switch tint into an
    /// otherwise monochrome screen, so the box is drawn from the design system.
    private var consent: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            checkRow(
                isOn: confirmedAge,
                label: "I am at least 13 years old",
                toggle: { confirmedAge.toggle() }
            ) {
                Text("I am at least 13 years old")
            }

            checkRow(
                isOn: acceptedTerms,
                label: "I agree to STUHI's terms and privacy policy",
                toggle: { acceptedTerms.toggle() }
            ) {
                Text(termsSentence)
                    .tint(Color.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkRow<Label: View>(
        isOn: Bool,
        label: String,
        toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Label
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: toggle) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(isOn ? Color.ink : Color.hairlineStrong)
                    // 44pt of hit area, but the box itself stays flush with the
                    // page inset so the column still lines up.
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)

            content()
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                // Left readable rather than hidden: the terms and privacy
                // links have to stay reachable with VoiceOver.
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The words themselves are the links — a reviewer should not have to hunt
    /// for the documents they are being asked to agree to.
    private var termsSentence: AttributedString {
        var s = AttributedString("I agree to STUHI's terms and privacy policy")
        if let range = s.range(of: "terms") {
            s[range].link = URL(string: "https://stuhi.org/app-terms")
            s[range].underlineStyle = Text.LineStyle.single
        }
        if let range = s.range(of: "privacy policy") {
            s[range].link = URL(string: "https://stuhi.org/app-privacy")
            s[range].underlineStyle = Text.LineStyle.single
        }
        return s
    }

    private func message(_ text: String, icon: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tone)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Guideline 1.2 requires published contact information and terms that
    /// people actually agree to. Linking them at the point of account
    /// creation is where a reviewer looks for it.
    private var legal: some View {
        VStack(spacing: Space.s) {
            Text("By continuing you agree to STUHI's terms and privacy policy.")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.l) {
                Link("Terms", destination: URL(string: "https://stuhi.org/app-terms")!)
                Link("Privacy", destination: URL(string: "https://stuhi.org/app-privacy")!)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.inkSecondary)
        }
        .padding(.top, Space.s)
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        if mode == .signUp {
            guard confirmedAge, acceptedTerms else { return false }
            return !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private func submit() async {
        guard !busy else { return }
        focus = nil
        busy = true; error = nil; notice = nil
        defer { busy = false }
        let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            if mode == .signUp {
                try await Supabase.shared.signUp(
                    email: cleanEmail,
                    password: password,
                    fullName: fullName.trimmingCharacters(in: .whitespaces)
                )
            } else {
                try await Supabase.shared.signIn(email: cleanEmail, password: password)
            }
            try await app.signedIn()
        } catch {
            self.error = Self.readable(error)
        }
    }

    /// GoTrue answers a wrong password with a raw JSON body — turn the common
    /// cases into a sentence someone can act on.
    private static func readable(_ error: Error) -> String {
        if case StuhiError.http(let code, let body) = error {
            if body.contains("invalid_credentials") || body.contains("Invalid login") {
                return "Wrong email or password."
            }
            if body.contains("user_already_exists") || body.contains("already registered") {
                return "That email already has an account. Sign in instead."
            }
            if body.contains("weak_password") { return "Pick a longer password." }
            if code == 429 { return "Too many tries. Wait a minute and try again." }
            if code >= 500 { return "The server had a problem. Try again in a moment." }
        }
        if let url = error as? URLError {
            return url.code == .timedOut
                ? "The server took too long to answer. Check your connection and try again."
                : "Can't reach STUHI. Check your connection."
        }
        return error.localizedDescription
    }

    private func reset() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard cleanEmail.contains("@") else {
            error = "Enter your email first, then tap this again."
            return
        }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Supabase.shared.resetPassword(email: cleanEmail)
            notice = "If that address has an account, a reset link is on its way."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
