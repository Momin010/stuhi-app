import SwiftUI
import AVFoundation
import UIKit

/// The door and meal-point scanner. Staff and core team only.
///
/// It reads the app's own admission QR — an opaque `tickets.code` and nothing
/// else — and resolves it against Supabase. Two jobs: admit somebody at the
/// door, or record that they have collected one particular meal.
struct ScannerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var meals: [ScheduleItem] = []
    @State private var mode: ScanMode = .admit
    @State private var permission: CameraPermission = .unknown
    @State private var outcome: ScanOutcome?
    @State private var busy = false
    /// The camera reports the same code many times a second. Remember the last
    /// one so a single pass held up for two seconds is one scan, not thirty.
    @State private var lastCode: String?
    @State private var loadError: String?
    @State private var clearTask: Task<Void, Never>?

    /// Typing a code by hand. A camera cannot scan a pass that is on the same
    /// phone as the scanner, so without this the whole feature is untestable
    /// with one device — and it is also what staff fall back to when a camera
    /// won't focus or somebody's screen is cracked.
    @State private var enteringCode = false
    @State private var typedCode = ""
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            if !app.canScan {
                EmptyStateView(
                    icon: "person",
                    title: "Staff only",
                    message: "The scanner is for STUHI staff on the door. If that should be you, ask the core team to grant it."
                )
            } else {
                switch permission {
                case .unknown:
                    ProgressView().tint(Color.inkSecondary)
                case .denied:
                    deniedView
                case .authorised:
                    scanner
                }
            }

            if let outcome {
                resultOverlay(outcome)
            }
        }
        .animation(.easeOut(duration: 0.12), value: outcome)
        .sheet(isPresented: $enteringCode) { manualEntry }
        .task { await start() }
        .onDisappear {
            clearTask?.cancel()
            clearTask = nil
        }
    }

    // MARK: - Scanner

    private var scanner: some View {
        ZStack(alignment: .top) {
            CameraPreview(isScanning: outcome == nil && !busy, onCode: handle(code:))
                .ignoresSafeArea()

            guide

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(Color.live)
                        .padding(Space.m)
                        .frame(maxWidth: .infinity)
                        .background(Color.canvas)
                }
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                MicroLabel("Scanner", trailing: app.event?.name)
                Button {
                    typedCode = ""
                    enteringCode = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 30)
                }
                .accessibilityLabel("Enter a code by hand")
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 30, alignment: .trailing)
                }
                .accessibilityLabel("Close the scanner")
            }

            // House-style segmented row: one chip for the door, one per meal.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    chip(.admit)
                    ForEach(meals) { meal in
                        chip(.meal(meal))
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
        .background(Color.canvas)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func chip(_ candidate: ScanMode) -> some View {
        Button {
            mode = candidate
            lastCode = nil
        } label: {
            Tag(text: candidate.title, filled: mode == candidate, icon: candidate.icon)
        }
        .buttonStyle(.plain)
    }

    private var guide: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.66
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.canvas.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var deniedView: some View {
        EmptyStateView(
            icon: "camera",
            title: "Camera access is off",
            message: "The scanner needs the camera to read admission codes. Turn it on for STUHI in Settings, then come back.",
            actionTitle: "Open Settings",
            action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }

    // MARK: - Typing a code by hand

    private var trimmedTypedCode: String {
        typedCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            MicroLabel("Enter code", trailing: mode.title)

            TextField("", text: $typedCode)
                .font(.system(size: 17, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .focused($codeFieldFocused)
                .onSubmit { submitTypedCode() }
                .padding(.vertical, 13)
                .padding(.horizontal, Space.m)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(codeFieldFocused ? Color.ink : Color.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            Text("Checks the code the same way the camera does. Use it when a camera won't focus, a screen is cracked, or you're testing on one device.")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.m) {
                Button("Cancel") {
                    codeFieldFocused = false
                    enteringCode = false
                    typedCode = ""
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Check") { submitTypedCode() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !trimmedTypedCode.isEmpty))
                    .disabled(trimmedTypedCode.isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.canvas)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .onAppear { codeFieldFocused = true }
    }

    /// Hands the typed code to exactly the same path the camera uses, so there
    /// is one place where a code becomes an outcome.
    @MainActor
    private func submitTypedCode() {
        let code = trimmedTypedCode
        guard !code.isEmpty else { return }
        codeFieldFocused = false
        enteringCode = false
        typedCode = ""
        // Typing a code is always deliberate, so forget the camera's
        // de-duplication memory: staff must be able to re-check the same pass.
        lastCode = nil
        handle(code: code)
    }

    // MARK: - Result overlay

    private func resultOverlay(_ result: ScanOutcome) -> some View {
        // Floods the whole screen. A volunteer on a door glances at this from
        // arm's length while somebody is already talking to them, so it has to
        // be one colour, one symbol and one name — nothing to read.
        ZStack {
            result.tint.ignoresSafeArea()

            VStack(spacing: Space.l) {
                Image(systemName: result.symbol)
                    .font(.system(size: 76, weight: .semibold))
                Text(result.title)
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(result.detail)
                    .font(.rowTitle)
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.canvas)
            .padding(Space.xl)
        }
        .transition(.opacity)
        .contentShape(Rectangle())
        .onTapGesture { clear() }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Start-up

    @MainActor
    private func start() async {
        permission = await requestCamera()
        await loadMeals()
    }

    @MainActor
    private func requestCamera() async -> CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorised
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .authorised : .denied
        default:
            return .denied
        }
    }

    @MainActor
    private func loadMeals() async {
        guard let event = app.event else { return }
        do {
            meals = try await Supabase.shared.select(
                "schedule_items",
                filters: [Supabase.eq("event_id", event.id), Supabase.eq("kind", "meal")],
                order: "starts_at.asc"
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Scanning

    @MainActor
    private func handle(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy, outcome == nil, trimmed != lastCode else { return }
        lastCode = trimmed
        busy = true
        Task { await resolve(trimmed) }
    }

    /// One server call per scan.
    ///
    /// This used to be three round trips — look up the ticket, look up the
    /// name, then write — which put the door's throughput at the mercy of the
    /// venue wifi and stamped the *phone's* clock into `admitted_at`. It also
    /// had to guess "already collected" from an HTTP status code. The
    /// `admit_ticket` / `claim_meal` functions do the whole thing in one
    /// transaction with server time and return an explicit outcome.
    @MainActor
    private func resolve(_ code: String) async {
        defer { busy = false }

        struct Result: Decodable {
            let outcome: String
            let holder: String?
            let at: Date?
        }

        do {
            let rows: [Result]
            switch mode {
            case .admit:
                rows = try await Supabase.shared.rpc(
                    "admit_ticket", ["ticket_code": code], as: [Result].self
                )
            case .meal(let item):
                rows = try await Supabase.shared.rpc(
                    "claim_meal",
                    ["ticket_code": code, "item": item.id.uuidString.lowercased()],
                    as: [Result].self
                )
            }

            guard let result = rows.first else {
                present(.refused("Couldn't check that pass", "The server didn't answer. Try again."))
                return
            }
            let name = result.holder ?? "Guest"
            let noun = mode.isMeal ? (mode.mealTitle ?? "that meal") : "entry"

            switch result.outcome {
            case "ok":
                present(mode.isMeal
                        ? .success(name, "\(noun) collected", symbol: "fork.knife")
                        : .success(name, "Admitted"))

            case "already":
                // Not a failure. The unique index and the state machine are
                // doing exactly their job: somebody has come round twice, and
                // the person on the door needs the original time so they can
                // tell an honest mistake from a shared screenshot.
                let when = result.at.map { ScanFormat.time.string(from: $0) }
                present(.duplicate(
                    mode.isMeal ? "Already collected" : "Already admitted",
                    when.map { mode.isMeal
                        ? "\(name) collected \(noun) at \($0)."
                        : "\(name) was admitted at \($0). This is a second scan of the same pass." }
                        ?? "\(name) has already been through."
                ))

            case "void":
                present(.refused(
                    mode.isMeal ? "Do not serve" : "Do not admit",
                    "\(name)'s pass has been cancelled. Send them to the STUHI desk."
                ))

            default:
                present(.refused("Not a STUHI pass", "This code isn't one of ours. Send them to the desk."))
            }
        } catch {
            present(.refused("Couldn't check that pass", error.localizedDescription, symbol: "exclamationmark.triangle"))
        }
    }

    // MARK: - Overlay lifetime

    @MainActor
    private func present(_ result: ScanOutcome) {
        outcome = result
        UINotificationFeedbackGenerator().notificationOccurred(result.haptic)

        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            clear()
        }
    }

    @MainActor
    private func clear() {
        clearTask?.cancel()
        clearTask = nil
        outcome = nil
        // Forget the last code so the same person can be scanned again on
        // purpose — a re-entry, or a retry after a network wobble.
        lastCode = nil
    }
}
