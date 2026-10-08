import SwiftUI

nonisolated enum SketchTheme {
    static let paper = Color(red: 0.985, green: 0.975, blue: 0.94)
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let gridDot = Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.25)
    static let yellowHighlighter = Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.55)
    static let blueHighlighter = Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.4)
    static let pinkHighlighter = Color(red: 1.0, green: 0.6, blue: 0.7).opacity(0.4)

    static let strokeWidth: CGFloat = 1.8

    static func title(size: CGFloat = 30) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: .title)
    }

    static let label = Font.custom("Noteworthy-Bold", size: 18, relativeTo: .headline)
    static let note = Font.custom("Noteworthy-Light", size: 16, relativeTo: .subheadline)
    static let body = Font.custom("Noteworthy-Light", size: 19, relativeTo: .body)
    static let bodyBold = Font.custom("Noteworthy-Bold", size: 19, relativeTo: .body)

    static let greenInk = Color(red: 0.1, green: 0.5, blue: 0.25)
    static let redInk = Color(red: 0.8, green: 0.15, blue: 0.15)
    static let card = Color.white
    static let ruledLine = Color(red: 0.55, green: 0.7, blue: 0.9).opacity(0.45)
    static let marginLine = Color(red: 0.9, green: 0.4, blue: 0.45).opacity(0.5)
}

nonisolated struct SketchRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(state >> 11) / Double(UInt64(1) << 53)) * 2 - 1
    }

    static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

nonisolated enum Sketch {
    enum Kind {
        case rectangle
        case roundedRectangle
        case ellipse
        case diamond
        case octagon
    }

    static func add(_ kind: Kind, in rect: CGRect, to path: inout Path, rng: inout SketchRandom) {
        switch kind {
        case .rectangle:
            polygon([
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            ], to: &path, rng: &rng)
        case .roundedRectangle:
            roundedRectangle(rect, radius: min(18, rect.height / 3), to: &path, rng: &rng)
        case .ellipse:
            ellipse(rect, to: &path, rng: &rng)
        case .diamond:
            polygon([
                CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY),
            ], to: &path, rng: &rng)
        case .octagon:
            let inset = min(rect.width, rect.height) * 0.25
            polygon([
                CGPoint(x: rect.minX + inset, y: rect.minY), CGPoint(x: rect.maxX - inset, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + inset), CGPoint(x: rect.maxX, y: rect.maxY - inset),
                CGPoint(x: rect.maxX - inset, y: rect.maxY), CGPoint(x: rect.minX + inset, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - inset), CGPoint(x: rect.minX, y: rect.minY + inset),
            ], to: &path, rng: &rng)
        }
    }

    static func line(from start: CGPoint, to end: CGPoint, to path: inout Path, rng: inout SketchRandom, roughness: CGFloat = 1) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let overshoot = (3 + rng.next() * 2.5) * roughness

        let a = CGPoint(
            x: start.x - unit.x * overshoot + rng.next() * 2.2 * roughness,
            y: start.y - unit.y * overshoot + rng.next() * 2.2 * roughness
        )
        let b = CGPoint(
            x: end.x + unit.x * overshoot + rng.next() * 2.2 * roughness,
            y: end.y + unit.y * overshoot + rng.next() * 2.2 * roughness
        )
        let bow = min(length * 0.05, 5) * rng.next() * roughness
        let t = 0.5 + rng.next() * 0.1
        let control = CGPoint(
            x: a.x + (b.x - a.x) * t + normal.x * bow,
            y: a.y + (b.y - a.y) * t + normal.y * bow
        )
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
    }

    static func polygon(_ points: [CGPoint], to path: inout Path, rng: inout SketchRandom) {
        for index in points.indices {
            line(from: points[index], to: points[(index + 1) % points.count], to: &path, rng: &rng)
        }
    }

    static func ellipse(_ rect: CGRect, to path: inout Path, rng: inout SketchRandom) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = 14
        let startAngle = Double(rng.next()) * .pi
        let sweep = 2 * Double.pi * (1.06 + Double(rng.next()) * 0.03)
        let points: [CGPoint] = (0...count).map { index in
            let angle = startAngle + sweep * Double(index) / Double(count)
            let wobble = 1 + rng.next() * 0.04
            return CGPoint(
                x: center.x + CGFloat(cos(angle)) * rect.width / 2 * wobble,
                y: center.y + CGFloat(sin(angle)) * rect.height / 2 * wobble
            )
        }
        path.move(to: points[0])
        for index in 1..<points.count {
            let midpoint = CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
            path.addQuadCurve(to: midpoint, control: points[index - 1])
        }
        if let last = points.last {
            path.addLine(to: last)
        }
    }

    static func roundedRectangle(_ rect: CGRect, radius: CGFloat, to path: inout Path, rng: inout SketchRandom) {
        let r = radius
        line(from: CGPoint(x: rect.minX + r, y: rect.minY), to: CGPoint(x: rect.maxX - r, y: rect.minY), to: &path, rng: &rng)
        line(from: CGPoint(x: rect.maxX, y: rect.minY + r), to: CGPoint(x: rect.maxX, y: rect.maxY - r), to: &path, rng: &rng)
        line(from: CGPoint(x: rect.maxX - r, y: rect.maxY), to: CGPoint(x: rect.minX + r, y: rect.maxY), to: &path, rng: &rng)
        line(from: CGPoint(x: rect.minX, y: rect.maxY - r), to: CGPoint(x: rect.minX, y: rect.minY + r), to: &path, rng: &rng)

        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.maxX - r, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + r)),
            (CGPoint(x: rect.maxX, y: rect.maxY - r), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX - r, y: rect.maxY)),
            (CGPoint(x: rect.minX + r, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - r)),
            (CGPoint(x: rect.minX, y: rect.minY + r), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + r, y: rect.minY)),
        ]
        for (start, control, end) in corners {
            path.move(to: CGPoint(x: start.x + rng.next(), y: start.y + rng.next()))
            path.addQuadCurve(
                to: CGPoint(x: end.x + rng.next(), y: end.y + rng.next()),
                control: CGPoint(x: control.x + rng.next() * 1.5, y: control.y + rng.next() * 1.5)
            )
        }
    }

    static func arrow(from start: CGPoint, to end: CGPoint, bend: CGFloat, to path: inout Path, rng: inout SketchRandom) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let control = CGPoint(
            x: (start.x + end.x) / 2 + normal.x * length * bend + rng.next() * 2,
            y: (start.y + end.y) / 2 + normal.y * length * bend + rng.next() * 2
        )
        path.move(to: CGPoint(x: start.x + rng.next(), y: start.y + rng.next()))
        path.addQuadCurve(to: end, control: control)

        let angle = atan2(end.y - control.y, end.x - control.x)
        let headLength = min(14, length * 0.35)
        for side in [-1.0, 1.0] {
            let headAngle = angle + .pi - side * (.pi / 7) + rng.next() * 0.08
            let tip = CGPoint(x: end.x + cos(headAngle) * headLength, y: end.y + sin(headAngle) * headLength)
            line(from: end, to: tip, to: &path, rng: &rng, roughness: 0.4)
        }
    }

    static func squiggle(in rect: CGRect, to path: inout Path, rng: inout SketchRandom) {
        let waves = max(2, Int(rect.width / 40))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rng.next()))
        for index in 1...waves {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(waves)
            let controlX = x - rect.width / CGFloat(waves) / 2
            let controlY = rect.midY + (index.isMultiple(of: 2) ? -1 : 1) * rect.height / 2 + rng.next()
            path.addQuadCurve(to: CGPoint(x: x, y: rect.midY + rng.next()), control: CGPoint(x: controlX, y: controlY))
        }
    }
}

nonisolated struct SketchShape: Shape {
    var kind: Sketch.Kind
    var seed: UInt64
    var passes = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inner = rect.insetBy(dx: 2, dy: 2)
        for pass in 0..<passes {
            var rng = SketchRandom(seed: seed &+ UInt64(pass) &* 7_919)
            Sketch.add(kind, in: inner, to: &path, rng: &rng)
        }
        return path
    }
}

nonisolated struct SketchArrow: Shape {
    var start: UnitPoint = .top
    var end: UnitPoint = .bottom
    var bend: CGFloat = 0.15
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var rng = SketchRandom(seed: seed)
        Sketch.arrow(
            from: CGPoint(x: rect.minX + rect.width * start.x, y: rect.minY + rect.height * start.y),
            to: CGPoint(x: rect.minX + rect.width * end.x, y: rect.minY + rect.height * end.y),
            bend: bend,
            to: &path,
            rng: &rng
        )
        return path
    }
}

nonisolated struct SketchSquiggle: Shape {
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var rng = SketchRandom(seed: seed)
        Sketch.squiggle(in: rect, to: &path, rng: &rng)
        return path
    }
}

extension Shape {
    func sketchStroke(
        _ color: Color = SketchTheme.ink,
        dashed: Bool = false,
        lineWidth: CGFloat = SketchTheme.strokeWidth
    ) -> some View {
        stroke(
            color,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dashed ? [7, 6] : [])
        )
    }
}

struct SketchPaper: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SketchTheme.paper))
            let spacing: CGFloat = 24
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(SketchTheme.gridDot))
        }
        .accessibilityHidden(true)
    }
}

struct SketchTitle: View {
    let text: String

    var body: some View {
        VStack(spacing: 2) {
            Text(text)
                .font(SketchTheme.title())
                .foregroundStyle(SketchTheme.ink)
                .multilineTextAlignment(.center)
            SketchSquiggle(seed: SketchRandom.seed(text))
                .sketchStroke(lineWidth: 2.2)
                .frame(width: 180, height: 10)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

nonisolated struct SketchFill: Shape {
    var kind: Sketch.Kind
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var rng = SketchRandom(seed: seed)
        let r = rect.insetBy(dx: 3, dy: 3)
        func jitter(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + rng.next() * 4, y: point.y + rng.next() * 4)
        }

        switch kind {
        case .ellipse:
            let center = CGPoint(x: r.midX, y: r.midY)
            let points = (0..<12).map { index -> CGPoint in
                let angle = Double(index) / 12 * 2 * Double.pi
                let wobble = 1 + rng.next() * 0.04
                return CGPoint(
                    x: center.x + CGFloat(cos(angle)) * r.width / 2 * wobble,
                    y: center.y + CGFloat(sin(angle)) * r.height / 2 * wobble
                )
            }
            var path = Path()
            let first = CGPoint(x: (points[11].x + points[0].x) / 2, y: (points[11].y + points[0].y) / 2)
            path.move(to: first)
            for index in 0..<12 {
                let next = points[(index + 1) % 12]
                path.addQuadCurve(
                    to: CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2),
                    control: points[index]
                )
            }
            path.closeSubpath()
            return path
        case .diamond:
            return Path { path in
                path.addLines([
                    jitter(CGPoint(x: r.midX, y: r.minY)), jitter(CGPoint(x: r.maxX, y: r.midY)),
                    jitter(CGPoint(x: r.midX, y: r.maxY)), jitter(CGPoint(x: r.minX, y: r.midY)),
                ])
                path.closeSubpath()
            }
        case .rectangle, .roundedRectangle, .octagon:
            return Path { path in
                path.addLines([
                    jitter(CGPoint(x: r.minX, y: r.minY)), jitter(CGPoint(x: r.maxX, y: r.minY)),
                    jitter(CGPoint(x: r.maxX, y: r.maxY)), jitter(CGPoint(x: r.minX, y: r.maxY)),
                ])
                path.closeSubpath()
            }
        }
    }
}

extension View {
    func sketchHighlight(_ color: Color, kind: Sketch.Kind = .rectangle, seed: UInt64) -> some View {
        background {
            SketchFill(kind: kind, seed: seed &+ 99)
                .fill(color)
                .offset(x: 4, y: 3)
                .accessibilityHidden(true)
        }
    }
}
