import SwiftUI

/// Palette and type for the landing page, ported from the web app's "cyanotype" landing
/// (`frontend/src/style.css`, the `.landing` token block). Deep printing-blue ground, warm
/// paper text, and the app's terracotta kept as the single accent, so opening the app and
/// opening the website feel like the same product.
///
/// These tokens are deliberately scoped to the landing screen. Everything behind the sign-in
/// wall keeps the standard system look.
enum LandingStyle {
    // MARK: Ink and paper

    static let ink = Color(hex: 0x0B1D2E)
    static let ink2 = Color(hex: 0x102B42)
    static let line = Color(hex: 0x23506E)
    static let blue = Color(hex: 0x5E96BC)
    static let pale = Color(hex: 0xCFE4F0)
    static let paper = Color(hex: 0xF1E8D9)
    static let text2 = Color(hex: 0x9DB8CC)
    static let dim = Color(hex: 0x7C9DB6)
    static let sand = Color(hex: 0xC0A883)
    static let ember = Color(hex: 0xEE7A3E)
    static let ember2 = Color(hex: 0xF5A16E)

    // MARK: Type

    //
    // The web page uses Fraunces for display and JetBrains Mono for labels. Rather than bundle
    // two font families for one screen, the iOS page uses the system serif and monospaced
    // designs, which carry the same contrast between "printed" headline and "typewritten" label.

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Horizontal page margin, matching the web page's `--lp-pad` at phone width.
    static let pad: CGFloat = 22
}

extension Color {
    /// 0xRRGGBB literal, so the palette above reads like the CSS it was ported from.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1,
        )
    }
}

// MARK: - Shared pieces

/// Uppercase monospaced eyebrow, the web page's `.lp-eyebrow`.
struct LandingEyebrow: View {
    let text: String
    var color: Color = LandingStyle.ember

    var body: some View {
        Text(text.uppercased())
            .font(LandingStyle.label(11, weight: .medium))
            .tracking(2.4)
            .foregroundStyle(color)
    }
}

/// Section heading, the web page's `.lp-h2`.
struct LandingHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LandingStyle.display(34, weight: .semibold))
            .foregroundStyle(LandingStyle.paper)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Filled ember button, the web page's `.lp-btn--solid`.
struct LandingSolidButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(LandingStyle.label(13, weight: .semibold))
                .tracking(1.6)
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(Color(hex: 0x14212B))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(LandingStyle.ember)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

/// Outlined button, the web page's `.lp-btn--ghost`.
struct LandingGhostButtonLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(LandingStyle.label(13, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(LandingStyle.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(LandingStyle.line, lineWidth: 1),
            )
    }
}
