import Combine
import SwiftUI

/// The app's landing page.
///
/// It says the same thing, in the same voice and the same palette, as the web landing page
/// (`frontend/src/views/LandingView.vue`): a narrated sample gallery that plays itself, the
/// three steps in order, what else is inside, and the creed. Privacy, Terms and Imprint are
/// linked in the footer and open in an in-app browser.
struct WelcomeView: View {
    @Binding var isLoggedIn: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var elapsed: Double = 0
    @State private var playing = false
    @State private var legalPage: LegalPage?

    private var activeIndex: Int {
        var index = 0
        for (n, stop) in SampleGallery.stops.enumerated() where Double(stop.at) <= elapsed {
            index = n
        }
        return index
    }

    private var active: SampleGallery.Stop {
        SampleGallery.stops[activeIndex]
    }

    private var progress: Double {
        elapsed / SampleGallery.total
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                hero
                plate
                tape
                spine
                more
                creed
                actions
                footer
            }
            // The landing page is a column of prose. Left to run the full width of an iPad it
            // reads as a banner, not a page, so it is capped and centred; on a phone the cap is
            // wider than the screen and changes nothing.
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(LandingStyle.ink.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .sheet(item: $legalPage) { page in
            if let url = page.url {
                LegalPageSheet(url: url).ignoresSafeArea()
            }
        }
        .onAppear {
            if !reduceMotion {
                playing = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                playing = false
            }
        }
        .onReceive(SampleGallery.ticker) { _ in
            guard playing else { return }
            elapsed = (elapsed + SampleGallery.step).truncatingRemainder(dividingBy: SampleGallery.total)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Picz")
                .font(LandingStyle.display(26, weight: .semibold))
                .foregroundStyle(LandingStyle.paper)

            Spacer()

            NavigationLink {
                LoginView(isLoggedIn: $isLoggedIn)
            } label: {
                Text("SIGN IN")
                    .font(LandingStyle.label(11))
                    .tracking(1.8)
                    .foregroundStyle(LandingStyle.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(LandingStyle.line, lineWidth: 1),
                    )
            }
        }
        .padding(.horizontal, LandingStyle.pad)
        .frame(height: 68)
        .overlay(alignment: .bottom) {
            LandingStyle.line.frame(height: 1)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            LandingEyebrow(text: "Private galleries, narrated")
                .padding(.bottom, 18)

            Text("Your trip,\ntold out loud.")
                .font(LandingStyle.display(46, weight: .semibold))
                .foregroundStyle(LandingStyle.paper)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            Text("Upload the photos, talk over them once, and send one link. "
                + "Whoever opens it just watches — your voice, your order, your photos.")
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(LandingStyle.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, LandingStyle.pad)
        .padding(.top, 44)
        .padding(.bottom, 32)
    }

    // MARK: - The plate

    private var plate: some View {
        VStack(alignment: .leading, spacing: 14) {
            CyanotypeScene(name: active.scene, label: "\(active.place), day \(active.day)")
                .equatable()
                .frame(height: 250)
                .clipShape(Rectangle())
                .padding(10)
                .background(LandingStyle.ink2)
                .overlay(Rectangle().strokeBorder(LandingStyle.line, lineWidth: 1))
                .animation(.easeInOut(duration: 0.35), value: activeIndex)

            VStack(alignment: .leading, spacing: 8) {
                Text("“\(active.line)”")
                    .font(LandingStyle.display(17, weight: .regular))
                    .italic()
                    .foregroundStyle(LandingStyle.pale)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(String(format: "%02d", activeIndex + 1)) / \(String(format: "%02d", SampleGallery.stops.count))  ·  \(active.coords)")
                    .font(LandingStyle.label(10))
                    .tracking(1.2)
                    .foregroundStyle(LandingStyle.dim)
            }
        }
        .padding(.horizontal, LandingStyle.pad)
        .padding(.bottom, 34)
    }

    // MARK: - The tape

    private var tape: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(LandingStyle.ink)
                        .frame(width: 34, height: 34)
                        .background(LandingStyle.ember)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .accessibilityLabel(playing ? "Pause the sample" : "Play the sample")

                Text("\(SampleGallery.clock(elapsed)) / \(SampleGallery.clock(SampleGallery.total))")
                    .font(LandingStyle.label(11))
                    .foregroundStyle(LandingStyle.pale)
                    .monospacedDigit()

                Spacer(minLength: 8)

                Text("SAMPLE GALLERY")
                    .font(LandingStyle.label(9))
                    .tracking(1.6)
                    .foregroundStyle(LandingStyle.sand)
            }

            Text("Day \(active.day) · \(active.place)")
                .font(LandingStyle.label(10))
                .tracking(1.2)
                .foregroundStyle(LandingStyle.dim)

            waveform
                .frame(height: 46)

            rail
        }
        .padding(18)
        .background(LandingStyle.ink2)
        .overlay(Rectangle().strokeBorder(LandingStyle.line, lineWidth: 1))
        .padding(.horizontal, LandingStyle.pad)
        .padding(.bottom, 46)
    }

    private var waveform: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let count = SampleGallery.bars.count
            let barWidth = max(1, width / CGFloat(count) - 1)

            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(SampleGallery.bars.enumerated()), id: \.offset) { index, bar in
                        Rectangle()
                            .fill(Double(index) / Double(count) <= progress
                                ? LandingStyle.ember
                                : LandingStyle.line)
                            .frame(width: barWidth, height: max(2, height * bar))
                    }
                }
                .frame(width: width, height: height, alignment: .center)

                Rectangle()
                    .fill(LandingStyle.paper)
                    .frame(width: 1, height: height)
                    .offset(x: width * progress)
            }
        }
        .accessibilityHidden(true)
    }

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(SampleGallery.stops.enumerated()), id: \.element.at) { index, stop in
                    Button {
                        elapsed = Double(stop.at)
                    } label: {
                        VStack(spacing: 0) {
                            CyanotypeScene(name: stop.scene, label: "\(stop.place), day \(stop.day)")
                                .equatable()
                                .frame(width: 92, height: 66)
                                .clipShape(Rectangle())

                            Text(SampleGallery.clock(Double(stop.at)))
                                .font(LandingStyle.label(9))
                                .foregroundStyle(index == activeIndex ? LandingStyle.ink : LandingStyle.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(index == activeIndex ? LandingStyle.ember : LandingStyle.ink)
                        }
                        .overlay(
                            Rectangle().strokeBorder(
                                index == activeIndex ? LandingStyle.ember : LandingStyle.line,
                                lineWidth: 1,
                            ),
                        )
                    }
                    .accessibilityLabel("Jump to \(stop.place), day \(stop.day)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Three things, in order

    private var spine: some View {
        VStack(alignment: .leading, spacing: 28) {
            LandingHeading(text: "Three things,\nin order.")

            ForEach(SampleGallery.spine, id: \.label) { step in
                VStack(alignment: .leading, spacing: 10) {
                    LandingEyebrow(text: step.label)
                    Text(step.title)
                        .font(LandingStyle.display(22, weight: .semibold))
                        .foregroundStyle(LandingStyle.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.body)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(LandingStyle.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                .overlay(alignment: .top) { LandingStyle.line.frame(height: 1) }
            }
        }
        .padding(.horizontal, LandingStyle.pad)
        .padding(.bottom, 56)
    }

    // MARK: - Also inside

    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            LandingHeading(text: "Also inside.")
                .padding(.bottom, 26)

            ForEach(SampleGallery.more, id: \.label) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.label.uppercased())
                        .font(LandingStyle.label(10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(LandingStyle.sand)
                    Text(row.body)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundStyle(LandingStyle.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .overlay(alignment: .top) { LandingStyle.line.frame(height: 1) }
            }
        }
        .padding(.horizontal, LandingStyle.pad)
        .padding(.bottom, 56)
    }

    // MARK: - Creed

    private var creed: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("No feed.\nNo algorithm.\nNo ads.")
                .font(LandingStyle.display(38, weight: .semibold))
                .foregroundStyle(LandingStyle.ember)
                .lineSpacing(-1)

            Text("Picz shows your photos to the people you send the link to, in the order you chose, "
                + "and stops there. Nothing is recommended, ranked, or shown to anyone else.")
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(LandingStyle.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LandingStyle.pad)
        .padding(.vertical, 40)
        .background(LandingStyle.ink2)
        .overlay(alignment: .top) { LandingStyle.line.frame(height: 1) }
        .overlay(alignment: .bottom) { LandingStyle.line.frame(height: 1) }
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            NavigationLink {
                RegisterView()
            } label: {
                LandingSolidButtonLabel(title: "Start a gallery")
            }

            NavigationLink {
                LoginView(isLoggedIn: $isLoggedIn)
            } label: {
                LandingGhostButtonLabel(title: "Sign in")
            }

            Text("Viewers never need an account.")
                .font(LandingStyle.label(10))
                .tracking(1.2)
                .foregroundStyle(LandingStyle.dim)
                .padding(.top, 4)
        }
        .padding(.horizontal, LandingStyle.pad)
        .padding(.bottom, 44)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 22) {
                ForEach(LegalPage.allCases) { page in
                    Button {
                        legalPage = page
                    } label: {
                        Text(page.title.uppercased())
                            .font(LandingStyle.label(10))
                            .tracking(1.6)
                            .foregroundStyle(LandingStyle.sand)
                    }
                }
            }

            Text("© \(SampleGallery.year) Picz")
                .font(LandingStyle.label(10))
                .foregroundStyle(LandingStyle.dim)

            Text("App v\(SampleGallery.appVersion)")
                .font(LandingStyle.label(9))
                .foregroundStyle(LandingStyle.dim.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LandingStyle.pad)
        .padding(.vertical, 30)
        .overlay(alignment: .top) { LandingStyle.line.frame(height: 1) }
    }
}

// MARK: - The sample gallery

//
// Eight stops on one recording — the same shape a real `PlaybackTimelineEntry` has: a point in
// the audio, and the photo that was on screen at that point. Kept in step with the web landing
// page so the two tell the same story.

enum SampleGallery {
    struct Stop {
        /// Seconds into the recording.
        let at: Int
        let day: String
        let place: String
        let coords: String
        let scene: CyanotypeSceneName
        let line: String
    }

    static let stops: [Stop] = [
        Stop(at: 0, day: "1", place: "Lisbon, PT", coords: "38.7075° N, 9.1364° W",
             scene: .harbour, line: "Landed at four. Walked straight down to the water."),
        Stop(at: 52, day: "1", place: "Alfama, PT", coords: "38.7139° N, 9.1300° W",
             scene: .azulejo, line: "Every second wall is tiled. I photographed a wall."),
        Stop(at: 98, day: "2", place: "Bairro Alto, PT", coords: "38.7130° N, 9.1450° W",
             scene: .tram, line: "The 28 is not a tram. The 28 is a fairground ride."),
        Stop(at: 134, day: "3", place: "Sintra, PT", coords: "38.7876° N, 9.3904° W",
             scene: .palace, line: "Fog until eleven, and then the towers came out of it."),
        Stop(at: 185, day: "4", place: "Cabo da Roca, PT", coords: "38.7803° N, 9.4989° W",
             scene: .cliffs, line: "The westmost point of Europe. Hold on to your hat."),
        Stop(at: 238, day: "5", place: "Cascais, PT", coords: "38.6968° N, 9.4215° W",
             scene: .market, line: "Bought figs at the market. Ate all of the figs."),
        Stop(at: 287, day: "5", place: "Cascais, PT", coords: "38.6970° N, 9.4220° W",
             scene: .terrace, line: "Dinner ran on until they switched the lamps on."),
        Stop(at: 341, day: "6", place: "Lisbon, PT", coords: "38.7169° N, 9.1399° W",
             scene: .night, line: "Last night. Rooftops, one moon, nobody wanted to go in."),
    ]

    struct Step {
        let label: String
        let title: String
        let body: String
    }

    static let spine: [Step] = [
        Step(label: "Upload",
             title: "Drop in the whole camera roll.",
             body: "Picz files each photo under the day it was taken, and inside that day under the "
                 + "place it was taken. Nothing to name, nothing to drag into order."),
        Step(label: "Narrate",
             title: "Press record and talk.",
             body: "Your voice is saved against whichever photo was on screen when you said it. "
                 + "Play the recording back and the photos turn themselves."),
        Step(label: "Share",
             title: "Send one link.",
             body: "Whoever opens it watches the gallery as you left it. No account to make, "
                 + "no app to install, nothing to download."),
    ]

    struct Row {
        let label: String
        let body: String
    }

    static let more: [Row] = [
        Row(label: "Tags", body: "Tag a photo once, then pull up every photo that matches it."),
        Row(label: "Map", body: "Every located photo of the trip, on one map."),
        Row(label: "Groups", body: "Put several albums together and present them as a single show."),
        Row(label: "Slideshow", body: "Full-screen playback, with the narration or without it."),
        Row(label: "Video", body: "Videos upload and play in line with the photos."),
    ]

    /// Length of the sample recording, in seconds.
    static let total: Double = 400
    /// How long one pass takes on screen. The sample plays faster than it was recorded.
    static let loopSeconds: Double = 48
    /// Ticks per second, and how far the playhead moves on each one.
    static let tickHz: Double = 15
    static let step: Double = total / loopSeconds / tickHz

    /// `nonisolated(unsafe)`: the publisher is created once and only ever subscribed to, and it
    /// is scheduled `on: .main` — the animation this drives never runs anywhere else.
    nonisolated(unsafe) static let ticker = Timer.publish(every: 1 / tickHz, on: .main, in: .common).autoconnect()

    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    static var year: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: Waveform

    /// Small seeded PRNG, so the waveform is the same shape on every launch — same generator
    /// and same seed as the web page, so both draw the identical recording.
    private static func mulberry32(_ seed: UInt32) -> () -> Double {
        var a = seed
        return {
            a = a &+ 0x6D2B_79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    private static let barCount = 132

    /// A voice, not noise: quiet either side of a photo change (someone taking a breath), long
    /// swells for phrases, and the random term for the syllables inside them.
    static let bars: [CGFloat] = {
        let random = mulberry32(0x280424)
        return (0 ..< barCount).map { index in
            let at = Double(index) / Double(barCount) * total
            let nearest = stops.map { abs(Double($0.at) - at) }.min() ?? 0
            let breath = min(1, 0.05 + pow(nearest / 9, 1.3))
            let phrase = 0.22 + 0.78 * pow(abs(sin(Double(index) / 16.5 + 1.1)), 0.9)
            let syllable = 0.28 + 0.72 * random()
            return CGFloat(max(0.05, min(1, breath * phrase * syllable * 1.45)))
        }
    }()
}

#Preview {
    NavigationStack {
        WelcomeView(isLoggedIn: .constant(false))
    }
}
