import SwiftUI
import AVFoundation
import UIKit

// Supporting types for the door / meal scanner.
//
// STUHI has no Luma Plus, so there is no Luma API to check anybody against.
// The app issues its own admission QR: a `tickets` row holds an opaque random
// `code` and the QR encodes nothing else. Everything here resolves that code
// server-side, which is why a photograph of somebody's screen is harmless.

// MARK: - meal_claims

/// One row of `meal_claims`. Lives here rather than in Core/Models.swift
/// because both sides of the meal flow need it — the scanner writes it, the
/// attendee's pass reads it back to show what they have already collected.
struct MealClaim: Codable, Identifiable, Equatable {
    let id: UUID
    var scheduleItemId: UUID
    var ticketId: UUID
    var claimedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case scheduleItemId = "schedule_item_id"
        case ticketId = "ticket_id"
        case claimedAt = "claimed_at"
    }
}

// MARK: - Scan mode

/// What the person holding the phone is doing right now: letting people in at
/// the door, or handing out one particular meal.
enum ScanMode: Equatable, Identifiable {
    case admit
    case meal(ScheduleItem)

    var id: String {
        switch self {
        case .admit:          return "admit"
        case .meal(let item): return item.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .admit:          return "Admit"
        case .meal(let item): return item.title
        }
    }

    var isMeal: Bool {
        if case .meal = self { return true }
        return false
    }

    /// The meal's own name, for copy like "Lunch collected".
    var mealTitle: String? {
        if case .meal(let item) = self { return item.title }
        return nil
    }

    /// SF Symbol. Verified names only — a wrong one renders blank and the
    /// compiler never complains.
    var icon: String {
        switch self {
        case .admit: return "person"
        case .meal:  return "fork.knife"
        }
    }
}

// MARK: - Outcome

/// The result of one scan, shaped for a full-screen flood that a volunteer can
/// read at arm's length in a loud corridor.
struct ScanOutcome: Identifiable, Equatable {
    enum Kind {
        /// Let them through / give them food.
        case success
        /// Their pass is real but has already been used for this. Not an
        /// error — the unique index doing exactly its job.
        case duplicate
        /// Do not let them through.
        case refused
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String

    /// Deliberately green-free. The app is monochrome apart from one status
    /// red, so "yes" is the ink flood and "no" is the live flood, and they are
    /// told apart by the symbol and the size of the type, not by hue.
    var tint: Color {
        switch kind {
        case .success:              return .ink
        case .duplicate, .refused:  return .live
        }
    }

    var haptic: UINotificationFeedbackGenerator.FeedbackType {
        switch kind {
        case .success:   return .success
        case .duplicate: return .warning
        case .refused:   return .error
        }
    }

    static func success(_ title: String, _ detail: String, symbol: String = "checkmark") -> ScanOutcome {
        ScanOutcome(kind: .success, title: title, detail: detail, symbol: symbol)
    }

    static func duplicate(_ title: String, _ detail: String) -> ScanOutcome {
        ScanOutcome(kind: .duplicate, title: title, detail: detail, symbol: "exclamationmark.triangle")
    }

    static func refused(_ title: String, _ detail: String, symbol: String = "xmark") -> ScanOutcome {
        ScanOutcome(kind: .refused, title: title, detail: detail, symbol: symbol)
    }
}

// MARK: - Formatting

enum ScanFormat {
    /// Wall-clock time, for "admitted at 18:42".
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// PostgREST has no way to ask the server for `now()` from a PATCH body,
    /// so the client sends a real timestamp. ISO 8601 with the offset is what
    /// timestamptz wants.
    static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Camera permission

enum CameraPermission {
    case unknown
    case authorised
    case denied
}

// MARK: - Camera plumbing

/// Receives the metadata callbacks. Kept off `UIViewController` on purpose:
/// `UIViewController` is `@MainActor`, the delegate callback is not, and
/// conforming a main-actor class to a nonisolated protocol is exactly the
/// crossing that causes trouble. This little relay does the hop instead.
final class ScanRelay: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var handler: (@MainActor (String) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let value = object.stringValue,
            !value.isEmpty
        else { return }

        let handler = self.handler
        // This arrives on the capture queue. Hop before anything touches
        // SwiftUI state.
        Task { @MainActor in handler?(value) }
    }
}

/// The capture session and its preview layer.
final class ScannerCameraController: UIViewController {
    private let session = AVCaptureSession()
    /// Session configuration and `startRunning()` both block. They must never
    /// be on the main thread or the whole scanner stutters as it opens.
    private let sessionQueue = DispatchQueue(label: "org.stuhi.scanner.session")
    private let metadataQueue = DispatchQueue(label: "org.stuhi.scanner.metadata")
    private let relay = ScanRelay()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false

    /// Set to false while a result is on screen, so the camera does not keep
    /// firing the same code at us fifteen times a second.
    var isScanning = true
    var onCode: (@MainActor (String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        relay.handler = { [weak self] code in
            guard let self, self.isScanning else { return }
            self.onCode?(code)
        }
        configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    private func configure() {
        guard !configured else { return }
        configured = true

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        sessionQueue.async { [session, relay, metadataQueue] in
            session.beginConfiguration()
            session.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(relay, queue: metadataQueue)
            output.metadataObjectTypes = [.qr]

            session.commitConfiguration()
            session.startRunning()
        }
    }

    func start() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// SwiftUI wrapper around the controller above.
struct CameraPreview: UIViewControllerRepresentable {
    var isScanning: Bool
    var onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> ScannerCameraController {
        let controller = ScannerCameraController()
        controller.onCode = onCode
        controller.isScanning = isScanning
        return controller
    }

    func updateUIViewController(_ controller: ScannerCameraController, context: Context) {
        controller.onCode = onCode
        controller.isScanning = isScanning
    }

    static func dismantleUIViewController(_ controller: ScannerCameraController, coordinator: Coordinator) {
        // Leaving the camera running behind a dismissed view keeps the orange
        // recording indicator lit and drains the battery all day.
        controller.stop()
    }
}
