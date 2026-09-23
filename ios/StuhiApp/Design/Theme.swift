import SwiftUI
import UIKit

// STUHI design system.
//
// Direction: the STUHI wordmark is geometric, extended and industrial — it
// reads like technical signage. The app follows: hairline rules instead of
// shadows, uppercase tracked-out micro-labels, heavy numerals, hard edges.
// Strictly monochrome. The only chromatic thing in the entire app is the
// live-status dot, because a red dot means "now" to everybody and inventing
// a monochrome equivalent would be cleverness at the cost of clarity.
//
// Never use emoji as iconography here. SF Symbols only.

// MARK: - Colour

extension Color {
    /// Page background.
    static let ink = Color(light: 0x000000, dark: 0xFFFFFF)
    /// Primary text and icons. Inverts with the scheme.
    static let inkSecondary = Color(light: 0x6B6B6B, dark: 0x9A9A9A)
    static let inkTertiary = Color(light: 0xA3A3A3, dark: 0x6E6E6E)

    static let canvas = Color(light: 0xFFFFFF, dark: 0x000000)
    /// Raised surfaces — cards, sheets, rows.
    static let surface = Color(light: 0xFAFAFA, dark: 0x111111)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1A1A1A)

    /// 1px rules and card borders. Deliberately faint.
    static let hairline = Color(light: 0xE5E5E5, dark: 0x2A2A2A)
    static let hairlineStrong = Color(light: 0xC9C9C9, dark: 0x3D3D3D)

    /// The single non-monochrome colour in the app. Status only, never decor.
    static let live = Color(light: 0xD9002B, dark: 0xFF4D6A)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Spacing

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Standard horizontal page inset.
    static let page: CGFloat = 20
}

enum Radius {
    static let card: CGFloat = 14
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}

// MARK: - Type

extension Font {
    /// Big numerals — countdown, table numbers. Monospaced digits so they
    /// don't jitter as they tick.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default).monospacedDigit()
    }

    /// Screen title. Tight, heavy, sits close to the content beneath it.
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let sectionTitle = Font.system(size: 19, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)

    /// The signage label — uppercase, tracked out, used above every section.
    static let micro = Font.system(size: 11, weight: .semibold)
}

// MARK: - Building blocks

/// Uppercase tracked-out section label. The app's most repeated element.
struct MicroLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.micro)
                .tracking(0.9)
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: Space.s)
            if let trailing {
                Text(trailing.uppercased())
                    .font(.micro)
                    .tracking(0.9)
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Flat bordered container. No shadow anywhere in this app.
struct Card<Content: View>: View {
    var padding: CGFloat = Space.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// 1px rule. `Divider()` picks up system colours we don't want.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Tight screen header. Momin's standing note: no wasted vertical space —
/// the title sits close to the content, never floating in a white band.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.screenTitle)
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Primary action. Solid ink, inverted label.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(enabled ? Color.ink : Color.inkTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Secondary action. Hairline outline, ink label.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Color.hairlineStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Small outlined tag — roles, languages, challenge names.
struct Tag: View {
    let text: String
    var filled: Bool = false
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(filled ? Color.canvas : Color.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(filled ? Color.ink : Color.clear)
        .overlay(
            Capsule().stroke(filled ? Color.clear : Color.hairlineStrong, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

/// Pulsing dot for anything happening right now.
struct LiveDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.live)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}

/// Initials in a bordered circle. We never show emoji avatars.
struct Initials: View {
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Color.surface)
            .overlay(Circle().stroke(Color.hairline, lineWidth: 1))
            .clipShape(Circle())
    }
}

/// Consistent empty state. Used rather than a blank screen anywhere.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.inkTertiary)
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, Space.xs)
                    .frame(maxWidth: 240)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The wordmark

/// STUHI wordmark, drawn as a shape rather than shipped as a bitmap so it
/// stays crisp at every size and inverts with the colour scheme.
struct Wordmark: View {
    var height: CGFloat = 22

    var body: some View {
        Image("Wordmark")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(Color.ink)
            .accessibilityLabel("STUHI")
    }
}
