import SwiftUI

struct WelcomeView: View {
    @Binding var isLoggedIn: Bool
    @State private var heroVisible: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer(minLength: 8)

                PhotoStackHero()
                    .frame(height: 260)
                    .scaleEffect(heroVisible ? 1.0 : 0.92)
                    .opacity(heroVisible ? 1.0 : 0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: heroVisible)

                VStack(spacing: 14) {
                    Text("Picz")
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(BrandStyle.brandGradient)
                        .padding(.top, 4)

                    Text("Your memories,\nbeautifully shared.")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .foregroundStyle(.primary)

                    Text("Private galleries for the people who matter. No social media, no algorithms, no ads.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 16)

                FeaturePillsRow()
                    .padding(.top, 4)

                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    NavigationLink {
                        LoginView(isLoggedIn: $isLoggedIn)
                    } label: {
                        HStack(spacing: 10) {
                            Text("Sign In")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(BrandStyle.brandGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: BrandStyle.shadow, radius: 14, x: 0, y: 8)
                    }

                    NavigationLink {
                        RegisterView()
                    } label: {
                        Text("Create account")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)

                Text("By continuing you agree to our Terms and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 12)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(WelcomeBackground())
        .navigationBarHidden(true)
        .onAppear { heroVisible = true }
    }
}

// MARK: - Hero photo stack

private struct PhotoStackHero: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color.purple.opacity(0.25), .clear],
                center: .center,
                startRadius: 30,
                endRadius: 220,
            )
            .blur(radius: 30)

            PhotoCard(palette: .lisbon, label: "Lisbon Trip", icon: "mountain.2.fill")
                .frame(width: 188, height: 230)
                .rotationEffect(.degrees(-11))
                .offset(x: -78, y: 14)

            PhotoCard(palette: .family, label: "Family", icon: "person.2.fill")
                .frame(width: 188, height: 230)
                .rotationEffect(.degrees(9))
                .offset(x: 78, y: 22)

            PhotoCard(palette: .summer, label: "Summer 2024", icon: "sun.max.fill")
                .frame(width: 200, height: 240)
                .rotationEffect(.degrees(-2))
                .offset(x: 0, y: -10)
        }
    }
}

private struct PhotoCard: View {
    let palette: CardPalette
    let label: String
    let icon: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: palette.meshColors,
            )

            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial.opacity(0.9))
                .clipShape(Capsule())
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1.2),
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

private enum CardPalette {
    case lisbon, family, summer

    var meshColors: [Color] {
        switch self {
        case .lisbon:
            return [
                Color(red: 0.18, green: 0.42, blue: 0.78), Color(red: 0.30, green: 0.56, blue: 0.86), Color(red: 0.42, green: 0.72, blue: 0.92),
                Color(red: 0.27, green: 0.52, blue: 0.82), Color(red: 0.40, green: 0.65, blue: 0.88), Color(red: 0.55, green: 0.80, blue: 0.92),
                Color(red: 0.35, green: 0.62, blue: 0.86), Color(red: 0.48, green: 0.74, blue: 0.90), Color(red: 0.66, green: 0.86, blue: 0.94),
            ]
        case .family:
            return [
                Color(red: 0.94, green: 0.40, blue: 0.55), Color(red: 0.97, green: 0.52, blue: 0.49), Color(red: 0.99, green: 0.66, blue: 0.42),
                Color(red: 0.92, green: 0.46, blue: 0.62), Color(red: 0.96, green: 0.58, blue: 0.55), Color(red: 0.98, green: 0.72, blue: 0.50),
                Color(red: 0.86, green: 0.50, blue: 0.72), Color(red: 0.95, green: 0.65, blue: 0.62), Color(red: 0.98, green: 0.80, blue: 0.58),
            ]
        case .summer:
            return [
                Color(red: 0.45, green: 0.32, blue: 0.82), Color(red: 0.58, green: 0.40, blue: 0.88), Color(red: 0.74, green: 0.50, blue: 0.92),
                Color(red: 0.52, green: 0.38, blue: 0.85), Color(red: 0.65, green: 0.46, blue: 0.90), Color(red: 0.82, green: 0.58, blue: 0.92),
                Color(red: 0.62, green: 0.46, blue: 0.88), Color(red: 0.76, green: 0.56, blue: 0.92), Color(red: 0.90, green: 0.68, blue: 0.92),
            ]
        }
    }
}

// MARK: - Feature pills

private struct FeaturePillsRow: View {
    var body: some View {
        HStack(spacing: 10) {
            FeaturePill(symbol: "lock.shield.fill", text: "Private")
            FeaturePill(symbol: "sparkles", text: "Ad-free")
            FeaturePill(symbol: "person.2.fill", text: "Yours")
        }
    }
}

private struct FeaturePill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5),
        )
    }
}

// MARK: - Background

private struct WelcomeBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            RadialGradient(
                colors: [Color(red: 0.55, green: 0.39, blue: 0.85).opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 460,
            )

            RadialGradient(
                colors: [Color(red: 0.30, green: 0.56, blue: 0.86).opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 420,
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Brand style

private enum BrandStyle {
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.30, green: 0.56, blue: 0.86),
            Color(red: 0.55, green: 0.39, blue: 0.85),
        ],
        startPoint: .leading,
        endPoint: .trailing,
    )

    static let shadow = Color(red: 0.45, green: 0.30, blue: 0.85).opacity(0.35)
}
