import SwiftUI

struct FlowchartView: View {
    let flowchart: Flowchart
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            FlowchartDiagram(flowchart: flowchart, compact: sizeClass == .compact)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
        }
        .background { SketchPaper().ignoresSafeArea() }
    }
}

struct FlowchartDiagram: View {
    let flowchart: Flowchart
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            SketchTitle(text: flowchart.title)
                .padding(.bottom, 28)

            ForEach(Array(flowchart.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    connector(seed: SketchRandom.seed(step.label))
                }
                row(step, index: index)
            }
        }
    }

    @ViewBuilder
    private func row(_ step: Flowchart.Step, index: Int) -> some View {
        let notesOnLeft = !index.isMultiple(of: 2)

        Group {
            if compact {
                VStack(spacing: 8) {
                    node(step, index: index)
                    note(step.detail, pointing: .up, seed: SketchRandom.seed(step.detail))
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    note(notesOnLeft ? step.detail : "", pointing: .right, seed: SketchRandom.seed(step.detail))
                    node(step, index: index)
                    note(notesOnLeft ? "" : step.detail, pointing: .left, seed: SketchRandom.seed(step.detail))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1): \(step.label). \(step.detail)")
    }

    private func node(_ step: Flowchart.Step, index: Int) -> some View {
        let kind = shape(for: step, index: index)
        let seed = SketchRandom.seed(step.label)
        let isEndpoint = kind == .ellipse

        return Text(step.label.uppercased())
            .font(SketchTheme.label)
            .foregroundStyle(SketchTheme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, kind == .diamond ? 44 : 22)
            .padding(.vertical, kind == .diamond ? 30 : 14)
            .frame(minWidth: 150, maxWidth: kind == .diamond ? 300 : 260)
            .sketchHighlight(isEndpoint ? SketchTheme.yellowHighlighter : .clear, kind: kind, seed: seed)
            .overlay { SketchShape(kind: kind, seed: seed).sketchStroke() }
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shape(for step: Flowchart.Step, index: Int) -> Sketch.Kind {
        if index == 0 || index == flowchart.steps.count - 1 { return .ellipse }
        if step.label.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return .diamond }
        return .rectangle
    }

    private enum PointerDirection {
        case left, right, up
    }

    @ViewBuilder
    private func note(_ text: String, pointing direction: PointerDirection, seed: UInt64) -> some View {
        if text.isEmpty {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        } else {
            let label = Text(text)
                .font(SketchTheme.note)
                .foregroundStyle(SketchTheme.ink)

            switch direction {
            case .up:
                label
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            case .left:
                HStack(alignment: .center, spacing: 4) {
                    SketchArrow(start: UnitPoint(x: 1, y: 0.7), end: UnitPoint(x: 0, y: 0.4), bend: 0.3, seed: seed)
                        .sketchStroke(lineWidth: 1.4)
                        .frame(width: 34, height: 22)
                    label.multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .right:
                HStack(alignment: .center, spacing: 4) {
                    label.multilineTextAlignment(.trailing)
                    SketchArrow(start: UnitPoint(x: 0, y: 0.7), end: UnitPoint(x: 1, y: 0.4), bend: -0.3, seed: seed)
                        .sketchStroke(lineWidth: 1.4)
                        .frame(width: 34, height: 22)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func connector(seed: UInt64) -> some View {
        SketchArrow(start: UnitPoint(x: 0.5, y: 0.05), end: UnitPoint(x: 0.5, y: 0.95), bend: 0.12, seed: seed)
            .sketchStroke()
            .frame(width: 40, height: 46)
            .accessibilityHidden(true)
    }
}

struct MindMapView: View {
    let mindMap: MindMap

    @State private var mapSize: CGSize = .zero

    var body: some View {
        GeometryReader { viewport in
            let available = max(viewport.size.width - 48, 1)
            let scale = mapSize.width > available ? available / mapSize.width : 1

            ScrollView {
                VStack(spacing: 24) {
                    SketchTitle(text: "Mind Map")
                    MindMapDiagram(mindMap: mindMap)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: mapSize.width * scale, height: mapSize.height * scale, alignment: .top)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
        }
        .background { SketchPaper().ignoresSafeArea() }
    }
}

struct MindMapDiagram: View {
    let mindMap: MindMap

    private static let borders: [(kind: Sketch.Kind, dashed: Bool)] = [
        (.roundedRectangle, false),
        (.octagon, true),
        (.rectangle, false),
        (.roundedRectangle, true),
    ]
    private static let highlighters = [SketchTheme.blueHighlighter, SketchTheme.pinkHighlighter, SketchTheme.yellowHighlighter]

    var body: some View {
        RadialLayout {
            centerNode
                .anchorPreference(key: NodeBoundsKey.self, value: .bounds) { [0: $0] }
            ForEach(Array(mindMap.branches.enumerated()), id: \.offset) { index, branch in
                branchNode(branch, index: index)
                    .anchorPreference(key: NodeBoundsKey.self, value: .bounds) { [index + 1: $0] }
            }
        }
        .overlayPreferenceValue(NodeBoundsKey.self) { anchors in
            GeometryReader { proxy in
                connectors(anchors: anchors, proxy: proxy)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var centerNode: some View {
        let seed = SketchRandom.seed(mindMap.centralTopic)
        return Text(mindMap.centralTopic.uppercased())
            .font(SketchTheme.title(size: 24))
            .foregroundStyle(SketchTheme.ink)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .frame(width: 220)
            .padding(.horizontal, 34)
            .padding(.vertical, 38)
            .sketchHighlight(SketchTheme.yellowHighlighter, kind: .ellipse, seed: seed)
            .overlay {
                SketchShape(kind: .ellipse, seed: seed, passes: 1).sketchStroke(lineWidth: 2.2)
                SketchShape(kind: .ellipse, seed: seed &+ 3, passes: 1)
                    .sketchStroke(lineWidth: 1.4)
                    .padding(7)
            }
            .accessibilityLabel("Central topic: \(mindMap.centralTopic)")
    }

    private func branchNode(_ branch: MindMap.Branch, index: Int) -> some View {
        let seed = SketchRandom.seed(branch.topic)
        let border = Self.borders[index % Self.borders.count]

        return VStack(alignment: .leading, spacing: 8) {
            Text(branch.topic.uppercased())
                .font(SketchTheme.label)
                .foregroundStyle(SketchTheme.ink)
                .padding(.horizontal, 4)
                .sketchHighlight(Self.highlighters[index % Self.highlighters.count], seed: seed)

            ForEach(Array(branch.ideas.enumerated()), id: \.offset) { _, idea in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("–")
                    Text(idea)
                }
                .font(SketchTheme.note)
                .foregroundStyle(SketchTheme.ink)
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
        .padding(.horizontal, border.kind == .octagon ? 26 : 18)
        .padding(.vertical, border.kind == .octagon ? 22 : 16)
        .overlay {
            SketchShape(kind: border.kind, seed: seed).sketchStroke(dashed: border.dashed)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func connectors(anchors: [Int: Anchor<CGRect>], proxy: GeometryProxy) -> some View {
        Canvas { context, _ in
            guard let centerAnchor = anchors[0] else { return }
            let center = proxy[centerAnchor]
            for index in 1...max(mindMap.branches.count, 1) {
                guard let anchor = anchors[index] else { continue }
                let branch = proxy[anchor]
                var path = Path()
                var rng = SketchRandom(seed: SketchRandom.seed(mindMap.branches[index - 1].topic) &+ 17)
                let (start, end) = Self.endpoints(from: center, to: branch)
                Sketch.arrow(from: start, to: end, bend: index.isMultiple(of: 2) ? 0.18 : -0.18, to: &path, rng: &rng)
                context.stroke(
                    path,
                    with: .color(SketchTheme.ink),
                    style: StrokeStyle(lineWidth: SketchTheme.strokeWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private static func endpoints(from center: CGRect, to branch: CGRect) -> (CGPoint, CGPoint) {
        let from = CGPoint(x: center.midX, y: center.midY)
        let to = CGPoint(x: branch.midX, y: branch.midY)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let unit = CGPoint(x: dx / length, y: dy / length)

        let a = center.width / 2
        let b = center.height / 2
        let ellipseDistance = 1 / ((unit.x / a) * (unit.x / a) + (unit.y / b) * (unit.y / b)).squareRoot()

        let halfWidth = branch.width / 2
        let halfHeight = branch.height / 2
        let boxDistance = min(
            abs(unit.x) > 0.001 ? halfWidth / abs(unit.x) : .infinity,
            abs(unit.y) > 0.001 ? halfHeight / abs(unit.y) : .infinity
        )

        let start = CGPoint(x: from.x + unit.x * (ellipseDistance + 4), y: from.y + unit.y * (ellipseDistance + 4))
        let end = CGPoint(x: to.x - unit.x * (boxDistance + 8), y: to.y - unit.y * (boxDistance + 8))
        return (start, end)
    }
}

#Preview("Flowchart") {
    FlowchartView(flowchart: Flowchart(title: "How a Bill Becomes Law", steps: [
        .init(label: "Bill introduced", detail: "A member of Congress proposes the bill."),
        .init(label: "Committee review", detail: "Experts study it, hold hearings, and may amend it."),
        .init(label: "Passes both houses?", detail: "House and Senate must each approve the same text."),
        .init(label: "President signs", detail: "Or vetoes it, which Congress can override with two-thirds."),
        .init(label: "Becomes law", detail: "It's published and takes effect."),
    ]))
}

#Preview("Mind Map") {
    MindMapView(mindMap: MindMap(centralTopic: "Photosynthesis", branches: [
        .init(topic: "Inputs", ideas: ["Sunlight", "Water", "Carbon dioxide"]),
        .init(topic: "Light reactions", ideas: ["Happen in thylakoids", "Make ATP and NADPH"]),
        .init(topic: "Calvin cycle", ideas: ["Fixes CO₂", "Builds glucose"]),
        .init(topic: "Outputs", ideas: ["Glucose", "Oxygen"]),
        .init(topic: "Why it matters", ideas: ["Base of food chains", "Source of O₂"]),
    ]))
}

private struct NodeBoundsKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct RadialLayout: Layout {
    var gap: CGFloat = 46
    var branchWidth: CGFloat = 260

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews)
        for (index, frame) in arrangement.frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard let centerView = subviews.first else { return (.zero, []) }
        let centerSize = centerView.sizeThatFits(.unspecified)
        let sizes = subviews.dropFirst().map { $0.sizeThatFits(ProposedViewSize(width: branchWidth, height: nil)) }
        let count = sizes.count

        let startAngle = count == 2 ? 0.0 : -Double.pi / 2
        let angles = (0..<count).map { startAngle + 2 * Double.pi * Double($0) / Double(max(count, 1)) }

        var scale: CGFloat = 1
        var frames: [CGRect] = []
        repeat {
            frames = [CGRect(x: -centerSize.width / 2, y: -centerSize.height / 2, width: centerSize.width, height: centerSize.height)]
            for index in 0..<count {
                let direction = CGPoint(x: cos(angles[index]), y: sin(angles[index]))
                let size = sizes[index]
                let clearX = abs(direction.x) > 0.01 ? (centerSize.width / 2 + size.width / 2 + gap) / abs(direction.x) : .infinity
                let clearY = abs(direction.y) > 0.01 ? (centerSize.height / 2 + size.height / 2 + gap) / abs(direction.y) : .infinity
                let stagger: CGFloat = index.isMultiple(of: 2) ? 1 : 1.08
                let distance = min(clearX, clearY) * scale * stagger
                let midpoint = CGPoint(x: direction.x * distance, y: direction.y * distance)
                frames.append(CGRect(x: midpoint.x - size.width / 2, y: midpoint.y - size.height / 2, width: size.width, height: size.height))
            }
            scale += 0.08
        } while hasOverlap(frames) && scale < 4

        let union = frames.reduce(CGRect.null) { $0.union($1) }
        let shifted = frames.map { $0.offsetBy(dx: -union.minX, dy: -union.minY) }
        return (union.size, shifted)
    }

    private func hasOverlap(_ frames: [CGRect]) -> Bool {
        for i in frames.indices {
            for j in frames.indices where j > i {
                if frames[i].insetBy(dx: -gap / 3, dy: -gap / 3).intersects(frames[j]) {
                    return true
                }
            }
        }
        return false
    }
}
