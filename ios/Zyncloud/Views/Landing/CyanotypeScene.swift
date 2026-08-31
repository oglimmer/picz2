import SwiftUI

/// The eight illustrations of the sample gallery, ported from the web landing page's
/// `CyanotypeScene.vue`. Blue ink for everything that is far away, one warm tone for whatever
/// is giving off light — the way a gold-toned cyanotype print actually behaves.
///
/// Drawn in the SVG's original 400×300 user space and scaled to fill the view (the SVG's
/// `preserveAspectRatio="xMidYMid slice"`), so the two platforms stay pixel-comparable.
enum CyanotypeSceneName: String, CaseIterable {
    case harbour, azulejo, tram, palace, cliffs, market, terrace, night

    /// Top and bottom stop of the scene's sky gradient.
    var sky: (Color, Color) {
        switch self {
        case .harbour: (Color(hex: 0x12314A), Color(hex: 0x3A6E92))
        case .azulejo: (Color(hex: 0x173B58), Color(hex: 0x173B58))
        case .tram: (Color(hex: 0x17415F), Color(hex: 0x5C90B2))
        case .cliffs: (Color(hex: 0x2A5B7E), Color(hex: 0xB4D3E5))
        case .palace: (Color(hex: 0x173C5A), Color(hex: 0x6E9BB8))
        case .market: (Color(hex: 0x12314A), Color(hex: 0x12314A))
        case .terrace: (Color(hex: 0x1B4463), Color(hex: 0x3A6E92))
        case .night: (Color(hex: 0x07182A), Color(hex: 0x0F2E48))
        }
    }
}

struct CyanotypeScene: View, Equatable {
    let name: CyanotypeSceneName
    let label: String

    var body: some View {
        Canvas { context, size in
            let plate = Plate(ctx: context, size: size)
            plate.fillSky(name.sky)
            plate.draw(name)
            // A last wash of the sky over everything, as in the SVG — it is what ties the
            // warm highlights back into the blue print.
            plate.fillSkyWash(name.sky, opacity: 0.12)
        }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isImage)
        .drawingGroup()
    }
}

// MARK: - Drawing surface

private struct Plate {
    let ctx: GraphicsContext
    let scale: CGFloat
    let dx: CGFloat
    let dy: CGFloat

    static let ember = Color(hex: 0xE9944F)

    init(ctx: GraphicsContext, size: CGSize) {
        self.ctx = ctx
        // "slice": cover the box and let the overflow clip.
        scale = max(size.width / 400, size.height / 300)
        dx = (size.width - 400 * scale) / 2
        dy = (size.height - 300 * scale) / 2
    }

    // MARK: Coordinate helpers

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: dx + x * scale, y: dy + y * scale)
    }

    func px(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: dx + x * scale, y: dy + y * scale, width: w * scale, height: h * scale)
    }

    // MARK: Primitives

    func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                  _ color: Color, opacity: Double = 1, radius: CGFloat = 0)
    {
        let path = radius > 0
            ? Path(roundedRect: rect(x, y, w, h), cornerRadius: px(radius))
            : Path(rect(x, y, w, h))
        ctx.fill(path, with: .color(color.opacity(opacity)))
    }

    func fillCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color, opacity: Double = 1) {
        ctx.fill(Path(ellipseIn: rect(cx - r, cy - r, r * 2, r * 2)), with: .color(color.opacity(opacity)))
    }

    /// The warm halo the SVG paints behind anything that gives off light.
    func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, opacity: Double = 1) {
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [
                .init(color: Plate.ember.opacity(0.85 * opacity), location: 0),
                .init(color: Plate.ember.opacity(0), location: 1),
            ]),
            center: pt(cx, cy),
            startRadius: 0,
            endRadius: px(r),
        )
        ctx.fill(Path(ellipseIn: rect(cx - r, cy - r, r * 2, r * 2)), with: shading)
    }

    func fillSky(_ sky: (Color, Color)) {
        ctx.fill(
            Path(rect(0, 0, 400, 300)),
            with: .linearGradient(
                Gradient(colors: [sky.0, sky.1]),
                startPoint: pt(0, 0),
                endPoint: pt(0, 300),
            ),
        )
    }

    func fillSkyWash(_ sky: (Color, Color), opacity: Double) {
        ctx.fill(
            Path(rect(0, 0, 400, 300)),
            with: .linearGradient(
                Gradient(colors: [sky.0.opacity(opacity), sky.1.opacity(opacity)]),
                startPoint: pt(0, 0),
                endPoint: pt(0, 300),
            ),
        )
    }

    /// Closed polygon from SVG user-space points.
    func poly(_ points: [(CGFloat, CGFloat)], _ color: Color, opacity: Double = 1) {
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = pt(point.0, point.1)
            if index == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(color.opacity(opacity)))
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
              _ color: Color, width: CGFloat, opacity: Double = 1)
    {
        var path = Path()
        path.move(to: pt(x1, y1))
        path.addLine(to: pt(x2, y2))
        ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: px(width))
    }

    /// One or two chained quadratic curves — the ripples, the bunting and the birds.
    func wave(from start: (CGFloat, CGFloat), segments: [((CGFloat, CGFloat), (CGFloat, CGFloat))],
              _ color: Color, width: CGFloat, opacity: Double = 1, round: Bool = false)
    {
        var path = Path()
        path.move(to: pt(start.0, start.1))
        for segment in segments {
            path.addQuadCurve(to: pt(segment.1.0, segment.1.1), control: pt(segment.0.0, segment.0.1))
        }
        ctx.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: px(width), lineCap: round ? .round : .butt),
        )
    }

    // MARK: Scenes

    func draw(_ name: CyanotypeSceneName) {
        switch name {
        case .harbour: harbour()
        case .azulejo: azulejo()
        case .tram: tram()
        case .palace: palace()
        case .cliffs: cliffs()
        case .market: market()
        case .terrace: terrace()
        case .night: night()
        }
    }

    /// Day 1 — the water at the end of the walk.
    private func harbour() {
        glow(298, 150, 70)
        fillCircle(298, 150, 24, Color(hex: 0xF0B071))
        fillRect(0, 172, 400, 128, Color(hex: 0x0A1C2E))

        // The sun's reflection, broken up by the swell.
        fillRect(286, 182, 24, 4, Plate.ember, opacity: 0.45, radius: 2)
        fillRect(278, 198, 40, 4, Plate.ember, opacity: 0.45, radius: 2)
        fillRect(288, 216, 20, 3, Plate.ember, opacity: 0.45, radius: 1.5)
        fillRect(272, 236, 52, 3, Plate.ember, opacity: 0.45, radius: 1.5)

        line(0, 172, 400, 172, Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.6)

        // A moored boat with a sail.
        poly([(74, 172), (158, 172), (144, 194), (88, 194)], Color(hex: 0x061520))
        fillRect(112, 118, 3, 54, Color(hex: 0x061520))
        poly([(118, 126), (152, 126), (118, 158)], Color(hex: 0x061520))

        wave(from: (20, 214), segments: [((38, 206), (56, 214)), ((74, 222), (92, 214))],
             Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.3)
        wave(from: (40, 246), segments: [((62, 237), (84, 246)), ((106, 255), (128, 246))],
             Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.3)
    }

    /// Day 1 — Alfama, where every wall is tiled.
    private func azulejo() {
        let tileInk = Color(hex: 0x9CC3DC)
        for row in 0 ..< 6 {
            for column in 0 ..< 8 {
                let ox = CGFloat(column) * 50
                let oy = CGFloat(row) * 50
                fillRect(ox, oy, 50, 50, Color(hex: 0x173B58))

                var diamond = Path()
                diamond.move(to: pt(ox + 25, oy + 6))
                diamond.addLine(to: pt(ox + 44, oy + 25))
                diamond.addLine(to: pt(ox + 25, oy + 44))
                diamond.addLine(to: pt(ox + 6, oy + 25))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(tileInk), lineWidth: px(2))

                fillCircle(ox + 25, oy + 25, 5, tileInk, opacity: 0.55)
                for corner in [(ox, oy), (ox + 50, oy), (ox, oy + 50), (ox + 50, oy + 50)] {
                    fillCircle(corner.0, corner.1, 3, tileInk, opacity: 0.4)
                }
            }
        }

        glow(352, 44, 80)
        fillRect(0, 252, 400, 48, Color(hex: 0x0A1C2E))
        fillRect(0, 248, 400, 5, tileInk, opacity: 0.5)
    }

    /// Day 2 — the 28 climbing Bairro Alto.
    private func tram() {
        glow(200, 200, 140, opacity: 0.5)

        // The street closing in on both sides.
        poly([(0, 300), (0, 88), (86, 88), (86, 300)], Color(hex: 0x0A2032))
        poly([(400, 300), (400, 62), (322, 62), (322, 300)], Color(hex: 0x0A2032))
        for window in [(16.0, 112.0), (52.0, 168.0), (336.0, 92.0), (336.0, 152.0)] {
            fillRect(window.0, window.1, 16, 22, Color(hex: 0xF0B071), opacity: 0.7)
        }

        // Overhead lines.
        line(0, 46, 400, 60, Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.4)
        line(0, 70, 400, 84, Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.4)

        poly([(104, 300), (134, 248), (266, 248), (296, 300)], Color(hex: 0x0C2740))
        fillRect(132, 104, 136, 28, Color(hex: 0x071A28), radius: 7)
        fillRect(118, 128, 164, 132, Color(hex: 0x071A28), radius: 12)
        for x in [134.0, 180.0, 226.0] {
            fillRect(x, 150, 40, 44, Color(hex: 0xF5C089), radius: 4)
        }
        fillRect(118, 208, 164, 6, Plate.ember)
        glow(200, 240, 28)
        fillCircle(200, 240, 12, Color(hex: 0xF5C089))
    }

    /// Day 3 — fog all morning, then the towers.
    private func palace() {
        var hill = Path()
        hill.move(to: pt(0, 300))
        hill.addLine(to: pt(0, 216))
        hill.addQuadCurve(to: pt(400, 182), control: pt(120, 158))
        hill.addLine(to: pt(400, 300))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(Color(hex: 0x0B2233)))

        fillRect(140, 128, 56, 112, Plate.ember)
        poly([(118, 96), (140, 54), (162, 96)], Plate.ember)
        fillRect(118, 96, 44, 144, Plate.ember)
        poly([(232, 84), (256, 40), (280, 84)], Plate.ember)
        fillRect(232, 84, 48, 156, Plate.ember)

        fillRect(130, 126, 12, 20, Color(hex: 0x0A1C2E), opacity: 0.75, radius: 6)
        fillRect(246, 116, 14, 22, Color(hex: 0x0A1C2E), opacity: 0.75, radius: 7)
        fillRect(158, 158, 12, 22, Color(hex: 0x0A1C2E), opacity: 0.75, radius: 6)

        fillRect(118, 236, 162, 8, Color(hex: 0xF0B071))

        // Pines on the slope.
        poly([(40, 300), (70, 228), (100, 300)], Color(hex: 0x061520))
        poly([(300, 300), (326, 240), (352, 300)], Color(hex: 0x061520))
        poly([(352, 300), (374, 252), (396, 300)], Color(hex: 0x061520))

        // The last of the fog.
        fillRect(0, 196, 400, 42, Color(hex: 0xCFE4F0), opacity: 0.18)
    }

    /// Day 4 — the end of Europe, very windy.
    private func cliffs() {
        glow(220, 128, 120, opacity: 0.4)
        fillRect(0, 158, 400, 142, Color(hex: 0x16456A))
        line(0, 158, 400, 158, Color(hex: 0xDCEDF6), width: 2, opacity: 0.85)

        wave(from: (180, 196), segments: [((222, 186), (264, 196)), ((306, 206), (348, 196))],
             Color(hex: 0xDCEDF6), width: 1.5, opacity: 0.22)
        wave(from: (210, 226), segments: [((256, 215), (302, 226)), ((348, 237), (394, 226))],
             Color(hex: 0xDCEDF6), width: 1.5, opacity: 0.22)

        poly([(0, 300), (0, 110), (34, 84), (70, 104), (96, 92), (120, 124), (138, 190), (150, 300)],
             Color(hex: 0x061520))
        poly([(120, 190), (138, 256), (150, 300), (92, 300)], Color(hex: 0x0C2B3E))
        poly([(246, 300), (262, 166), (276, 190), (288, 152), (306, 202), (320, 300)],
             Color(hex: 0x071E2C))
        poly([(288, 152), (306, 202), (320, 300), (298, 300)], Color(hex: 0x0C2B3E))

        // Surf breaking against the rock.
        wave(from: (142, 262), segments: [((166, 276), (192, 266))],
             Color(hex: 0xEAF4FA), width: 3.5, opacity: 0.7, round: true)
        wave(from: (226, 286), segments: [((252, 299), (280, 288))],
             Color(hex: 0xEAF4FA), width: 3.5, opacity: 0.7, round: true)
        wave(from: (326, 268), segments: [((348, 280), (372, 270))],
             Color(hex: 0xEAF4FA), width: 3.5, opacity: 0.7, round: true)

        // Gulls.
        wave(from: (186, 52), segments: [((195, 44), (203, 52))],
             Color(hex: 0xEAF4FA), width: 2.5, opacity: 0.85)
        wave(from: (214, 36), segments: [((222, 29), (229, 36))],
             Color(hex: 0xEAF4FA), width: 2.5, opacity: 0.85)
        wave(from: (164, 80), segments: [((171, 74), (177, 80))],
             Color(hex: 0xEAF4FA), width: 2.5, opacity: 0.85)
    }

    /// Day 5 — bought figs, ate all the figs.
    private func market() {
        fillRect(0, 0, 400, 300, Color(hex: 0x12314A))
        fillRect(0, 196, 400, 104, Color(hex: 0x061520))

        for (index, x) in [20.0, 150.0, 280.0].enumerated() {
            let warm = index == 1
            let awning = warm ? Plate.ember : Color(hex: 0xCFE4F0)
            poly([(x, 118), (x + 100, 118), (x + 114, 164), (x - 14, 164)], awning, opacity: 0.9)

            let stripe = warm ? Color(hex: 0x0A1C2E) : Color(hex: 0x12314A)
            for offset in [12.0, 44.0, 76.0] {
                fillRect(x + offset, 118, 12, 46, stripe, opacity: 0.55)
            }

            fillRect(x + 10, 196, 76, 48, Color(hex: 0x0B2233), radius: 4)
            line(x + 10, 216, x + 86, 216, Color(hex: 0x4C86AE), width: 2)

            let fruit = warm ? Plate.ember : Color(hex: 0x6FA3C4)
            for centre in [(x + 26, 206.0), (x + 42, 206.0), (x + 58, 206.0), (x + 34, 197.0), (x + 50, 197.0)] {
                fillCircle(centre.0, centre.1, 5, fruit, opacity: 0.85)
            }
        }

        // Festoon lights on a slack wire.
        for centre in [(86.0, 94.0), (200.0, 86.0), (314.0, 94.0)] {
            fillCircle(centre.0, centre.1, 7, Color(hex: 0xF0B071))
        }
        wave(from: (0, 78), segments: [((100, 106), (200, 98)), ((300, 90), (400, 78))],
             Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.5)
    }

    /// Day 5 — dinner ran until the lamps came on.
    private func terrace() {
        fillRect(0, 0, 400, 300, Color(hex: 0x061520))

        // Three arches, cut out of the sky.
        let sky = CyanotypeSceneName.terrace.sky
        for x in [42.0, 156.0, 270.0] {
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [sky.0, sky.1]),
                startPoint: pt(0, 0),
                endPoint: pt(0, 300),
            )
            ctx.fill(Path(ellipseIn: rect(x, 72, 88, 88)), with: shading)
            ctx.fill(Path(rect(x, 116, 88, 124)), with: shading)
        }
        for x in [42.0, 156.0, 270.0] {
            fillRect(x, 200, 88, 40, Color(hex: 0x0A1C2E), opacity: 0.65)
        }

        // Hanging lamps.
        let lamps: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (86, 84, 30, 8), (200, 100, 34, 9), (314, 78, 30, 8),
        ]
        let flexTops: [(CGFloat, CGFloat)] = [(86, 76), (200, 92), (314, 70)]
        for (index, lamp) in lamps.enumerated() {
            line(lamp.0, 40, flexTops[index].0, flexTops[index].1,
                 Color(hex: 0x9CC3DC), width: 1.5, opacity: 0.5)
            glow(lamp.0, lamp.1, lamp.2)
            fillCircle(lamp.0, lamp.1, lamp.3, Color(hex: 0xF0B071))
        }

        fillRect(0, 256, 400, 8, Color(hex: 0x9CC3DC), opacity: 0.45)
    }

    /// Day 6 — last night, rooftops and one moon.
    private func night() {
        fillCircle(316, 66, 26, Color(hex: 0xCFE4F0), opacity: 0.9)
        fillCircle(304, 58, 24, Color(hex: 0x0B2233))

        let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (70, 52, 2, 0.8), (128, 96, 1.6, 0.6), (196, 44, 2.2, 0.8), (252, 118, 1.6, 0.5),
            (42, 128, 1.8, 0.6), (356, 150, 1.6, 0.5), (160, 150, 1.4, 0.45),
        ]
        for star in stars {
            fillCircle(star.0, star.1, star.2, Color(hex: 0xCFE4F0), opacity: star.3)
        }

        poly([
            (0, 300), (0, 204), (56, 204), (56, 174), (104, 174), (104, 220), (148, 220),
            (148, 158), (208, 158), (208, 220), (260, 220), (260, 182), (316, 182),
            (316, 234), (360, 234), (360, 300),
        ], Color(hex: 0x061520))

        for window in [(18.0, 222.0), (118.0, 200.0), (212.0, 182.0), (230.0, 216.0), (330.0, 204.0)] {
            fillRect(window.0, window.1, 14, 18, Color(hex: 0xF0B071), opacity: 0.85)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(CyanotypeSceneName.allCases, id: \.self) { name in
                CyanotypeScene(name: name, label: name.rawValue)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .padding()
    }
    .background(LandingStyle.ink)
}
