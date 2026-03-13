//
//  BuildViewHelpers.swift
//  Vibro
//
//  Created by lyubcsenko on 18/09/2025.


import SwiftUI
import CoreHaptics

struct Wave: Identifiable, Equatable {
    let id: UUID
    var center: CGPoint
    var value: Int
}


private struct ChipFrameKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct TapMsgItemRectsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]   // index -> rect
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TapMsg2ItemRectsDrawKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TapMsg2ItemRectsGlobalKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TapMsg2ItemRectsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
struct TapMsg2ViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}





struct ConnectedTapMessageOverlay: View {
    let order: [Int]
    let rects: [Int: CGRect]
    let segments: [TapMessageView.Segment]
    let progresses: [CGFloat]
    let accent: Color
    let showAccent: Bool
    let playingIndex: Int
    let activePart: TapMessageView.PartKind?
    let partProgress: CGFloat
    
    let connectorPortion: CGFloat = 0.12
    @State private var connectorCache: [Int: Path] = [:]
    var body: some View {
        Canvas { context, _ in

            // MARK: Level selection

            func level(for seg: TapMessageView.Segment, i: Int) -> CGFloat {
                if i != playingIndex {
                    if seg.m3 > 0 { return 0.01 }
                    if seg.m2 > 0 { return 0.40 }
                    if seg.m1 > 0 { return 0.70 }
                    return 1.0
                }

                switch activePart {
                case .m3:    return 0.01
                case .m2:    return 0.40
                case .m1:    return 0.70
                case .delay: return 1.0
                default:
                    if seg.m3 > 0 { return 0.01 }
                    if seg.m2 > 0 { return 0.40 }
                    if seg.m1 > 0 { return 0.70 }
                    return 1.0
                }
            }

            // MARK: Math helpers

            func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

            func deformationAmount(_ t: CGFloat) -> CGFloat {
                let x = clamp01(t)
                let eased = pow(x, 2.2)
                return eased * 1.6
            }

            func appendBulged(
                _ path: inout Path,
                start: CGPoint,
                end: CGPoint,
                smoothStart: CGFloat,
                smoothEnd: CGFloat
            ) {
                let dx = end.x - start.x
                let dy = end.y - start.y

                if abs(dx) < 0.5 && abs(dy) < 0.5 {
                    path.addLine(to: end)
                    return
                }

                let signX: CGFloat = (dx >= 0) ? 1 : -1
                let base = min(max(abs(dx) * 0.55, 10), 120)

                let a1 = deformationAmount(smoothStart)
                let a2 = deformationAmount(smoothEnd)

                let c1 = CGPoint(x: start.x + signX * base * a1, y: start.y)
                let c2 = CGPoint(x: end.x   - signX * base * a2, y: end.y)

                path.addCurve(to: end, control1: c1, control2: c2)
            }

            func connectorPath(
                start: CGPoint,
                end: CGPoint,
                smoothStart: CGFloat,
                smoothEnd: CGFloat
            ) -> Path {
                var p = Path()
                p.move(to: start)

                appendBulged(
                    &p,
                    start: start,
                    end: end,
                    smoothStart: smoothStart,
                    smoothEnd: smoothEnd
                )

                return p
            }

            // MARK: Layout helpers

            func yForIndex(_ i: Int) -> CGFloat? {
                guard let r = rects[i] else { return nil }
                return r.minY + r.height * level(for: segments[i], i: i)
            }

            func segmentEndX(i: Int) -> CGFloat {
                guard let r = rects[i] else { return 0 }
                return r.maxX
            }

            func connector(for index: Int) -> Path {
                if let cached = connectorCache[index] {
                    return cached
                }

                let a = items[index]
                let b = items[index + 1]

                let start = CGPoint(x: segmentEndX(i: a.i), y: a.y)
                let end = CGPoint(x: b.r.minX, y: b.y)

                let smoothStart = CGFloat(segments[a.i].smoothEnd)
                let smoothEnd   = CGFloat(segments[b.i].smoothStart)

                let path = connectorPath(
                    start: start,
                    end: end,
                    smoothStart: smoothStart,
                    smoothEnd: smoothEnd
                )

                connectorCache[index] = path
                return path
            }
            
            func segmentProgressX(i: Int) -> CGFloat {
                guard let r = rects[i] else { return 0 }

                let pSeg = (i < progresses.count)
                    ? max(0, min(1, progresses[i]))
                    : 0

                let p: CGFloat

                if i == playingIndex,
                   let part = activePart {

                    let seg = segments[i]
                    let total = seg.m1 + seg.m2 + seg.m3 + seg.delay

                    var elapsed: Double = 0

                    switch part {
                    case .m1:
                        elapsed = seg.m1 * Double(partProgress)

                    case .m2:
                        elapsed = seg.m1 +
                                  seg.m2 * Double(partProgress)

                    case .m3:
                        elapsed = seg.m1 +
                                  seg.m2 +
                                  seg.m3 * Double(partProgress)

                    case .delay:
                        elapsed = seg.m1 +
                                  seg.m2 +
                                  seg.m3 +
                                  seg.delay * Double(partProgress)
                    }

                    p = CGFloat(elapsed / total)

                } else {
                    p = pSeg
                }

                return r.minX + r.width * p
            }

            // MARK: Build visible items

            var items: [(i: Int, r: CGRect, y: CGFloat)] = []

            for i in order {
                guard let r = rects[i],
                      let y = yForIndex(i) else { continue }

                items.append((i: i, r: r, y: y))
            }

            guard !items.isEmpty else { return }

            // MARK: Styles

            let baseW: CGFloat = 3.0 * 0.70
            let topW: CGFloat  = 2.2 * 0.70

            let underlayStyle = StrokeStyle(
                lineWidth: baseW,
                lineCap: .round,
                lineJoin: .round
            )

            let topStyle = StrokeStyle(
                lineWidth: topW,
                lineCap: .round,
                lineJoin: .round
            )

            // MARK: UNDERLAY

            var under = Path()

            let first = items[0]
            under.move(to: CGPoint(x: first.r.minX, y: first.y))

            for idx in items.indices {

                let a = items[idx]

                let aStartX = a.r.minX
                let aEndX   = segmentEndX(i: a.i)

                under.addLine(to: CGPoint(x: aStartX, y: a.y))
                under.addLine(to: CGPoint(x: aEndX,   y: a.y))

                guard idx < items.count - 1 else { continue }

                let b = items[idx + 1]

                let start = CGPoint(x: aEndX, y: a.y)
                let end   = CGPoint(x: b.r.minX, y: b.y)

                let smoothStart = CGFloat(segments[a.i].smoothEnd)
                let smoothEnd   = CGFloat(segments[b.i].smoothStart)

                under.addPath(
                    connectorPath(
                        start: start,
                        end: end,
                        smoothStart: smoothStart,
                        smoothEnd: smoothEnd
                    )
                )
            }

            context.stroke(
                under,
                with: .color(.secondary.opacity(0.6)),
                style: underlayStyle
            )

            // MARK: TOP LAYER

            // First, draw all base lines in primary color
            for idx in items.indices {
                let a = items[idx]
                let aStartX = a.r.minX
                let aEndX = segmentEndX(i: a.i)

                // Base horizontal line
                var baseH = Path()
                baseH.move(to: CGPoint(x: aStartX, y: a.y))
                baseH.addLine(to: CGPoint(x: aEndX, y: a.y))
                context.stroke(baseH, with: .color(.primary), style: topStyle)
            }

            // Draw connectors in primary color
            for idx in items.indices where idx < items.count - 1 {
                let a = items[idx]
                let b = items[idx + 1]
                
                let start = CGPoint(x: segmentEndX(i: a.i), y: a.y)
                let end = CGPoint(x: b.r.minX, y: b.y)
                
                let smoothStart = CGFloat(segments[a.i].smoothEnd)
                let smoothEnd = CGFloat(segments[b.i].smoothStart)
                
                let connector = connector(for: idx)
                context.stroke(connector, with: .color(.primary), style: topStyle)
            }

            // Then draw accent progress
            if showAccent {
                for idx in items.indices {
                    let a = items[idx]
                    let aStartX = a.r.minX
                    let aEndX = segmentEndX(i: a.i)
                    let p = (a.i < progresses.count)
                        ? max(0, min(1, progresses[a.i]))
                        : 0

                    let lineLimit = 1 - connectorPortion

                    let lineProgress = min(p / lineLimit, 1)
                    let connectorProgress = max(0, (p - lineLimit) / connectorPortion)

                    let aProgX = aStartX + (aEndX - aStartX) * lineProgress

                    if p > 0.01 {
                        // Draw segment progress
                        var progH = Path()
                        progH.move(to: CGPoint(x: aStartX, y: a.y))
                        progH.addLine(to: CGPoint(x: aProgX, y: a.y))
                        context.stroke(progH, with: .color(accent), style: topStyle)

                        // Draw connector progress if this segment is fully complete
                        if idx < items.count - 1 && connectorProgress > 0 {
                            let b = items[idx + 1]

                            let start = CGPoint(x: aEndX, y: a.y)
                            let end = CGPoint(x: b.r.minX, y: b.y)

                            let smoothStart = CGFloat(segments[a.i].smoothEnd)
                            let smoothEnd   = CGFloat(segments[b.i].smoothStart)

                            let fullConnector = connectorPath(
                                start: start,
                                end: end,
                                smoothStart: smoothStart,
                                smoothEnd: smoothEnd
                            )

                            // Trim connector based on progress
                            let trimmed = fullConnector.trimmedPath(
                                from: 0,
                                to: connectorProgress
                            )

                            context.stroke(trimmed, with: .color(accent), style: topStyle)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct TapMessageView: View {
    let id: String
    let text: String
    let selectedAccent: Color
    @Binding var activeTapID: String?
    var inCard: Bool = false

    @State private var showProgressBorder = false
    @State private var eraseProgress: CGFloat = 1
    @State private var tappedHighlight = false
    @State private var boostUntilIndex: Int? = nil
    @State private var isErasing = false
    @State private var finishWork: DispatchWorkItem?
    @State private var timeElapsed: Double = 0
    @State private var progresses: [CGFloat] = []
    @State private var animationTask: Task<Void, Never>?
    @State private var speedTarget: Double = 1.0
    private let maxBoost: Double = 3.0

    @State private var pendingScrollTo: (index: Int, anchor: UnitPoint)? = nil

    @State private var startScrollIndex: Int? = nil
    @State private var startScrollAnchor: UnitPoint = .leading
    @State private var tapViewport: CGRect = .zero

    @State private var isUserDragging = false
    @State private var playbackSpeed: Double = 1.0
    @State private var speedResetWork: DispatchWorkItem?
    @State private var skipAheadRemaining: Int = 0
    @State private var speedResetTask: Task<Void, Never>?
    @State private var hapticsResumeTask: Task<Void, Never>?
    @State private var didComplete = false

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var viewportWidth: CGFloat = 0
    @State private var itemWidth: CGFloat = 0
    @State private var lastAutoScrolledTo: Int = -1
    @State private var playingIndex: Int = 0
    @State private var passedThroughIndex: Int = -1

    @State private var hapticsPaused = false
    @State private var hapticsResumeWork: DispatchWorkItem? = nil
    @State private var dragStoppedAtIndex: Int? = nil

    @State private var canAutoScroll = true
    @State private var userScrollCooldownTask: Task<Void, Never>?
    @State private var tapMsgRects: [Int: CGRect] = [:]

    @State private var activePart: PartKind? = nil
    @State private var partProgress: CGFloat = 0

    @State private var resumeSegmentIndex: Int = 0
    @State private var resumePart: PartKind? = nil
    @State private var resumeElapsedInPart: Double = 0
    @State private var resumeRemainingInPart: Double = 0

    @State private var tapMsg2ViewportGlobal: CGRect = .zero

    // local player ownership
    @State private var currentPlayers: [CHHapticAdvancedPatternPlayer] = []

    private struct ProgressMarkerID: Hashable {
        let segment: Int
        let step: Int
    }
    private let markerStepsPerSegment = 40
    struct Segment: Identifiable {
        let id = UUID()
        let primary: Int
        let finger: Int
        let imageName: String
        let duration: Double
        let t: CGFloat
        let start: Double

        let m1: Double
        let m2: Double
        let m3: Double
        let delay: Double

        let smoothStart: Double
        let smoothEnd: Double

        var end: Double { start + duration }
    }

    enum PartKind: Int {
        case m1 = 1
        case m2 = 2
        case m3 = 3
        case delay = 999
    }

    private var glyphSize: CGFloat {
        UIScreen.main.bounds.height * (inCard ? 0.03 : 0.01)
    }

    private var estimatedItemWidth: CGFloat {
        glyphSize + 4 * 2 + 2 + 2
    }

    private var timelineWidth: CGFloat {
        guard !segments.isEmpty else { return 0 }

        let widths = segments.reduce(CGFloat(0)) { acc, seg in
            acc + width(for: seg)
        }

        let spacing = CGFloat(max(0, segments.count - 1)) * 2
        let padding: CGFloat = 12

        return widths + spacing + padding
    }
    private var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    private var contentWidth: CGFloat {
        let sum = segments.reduce(CGFloat(0)) { acc, seg in
            acc + max(2, viewportWidth * seg.t) + 8
        }
        return min(sum + 12, UIScreen.main.bounds.width * 0.6)
    }

    var parsed: [(primary: Int, inner: [Int: Double])] {
        decodeTapMessageStringOrdered(text)
    }

    private var segments: [Segment] {
        var start = 0.0
        var out: [Segment] = []

        for entry in parsed {
            let payload = entry.inner

            let m1 = max(0, payload[1] ?? 0)
            let m2 = max(0, payload[2] ?? 0)
            let m3 = max(0, payload[3] ?? 0)
            let dly = max(0, payload[999] ?? 0)

            let smoothStart = payload[-1] ?? 0.5
            let smoothEnd = payload[-2] ?? 0.5

            let duration = m1 + m2 + m3 + dly
            guard duration > 0 else { continue }

            let finger =
                (m1 > 0 ? 1 :
                 (m2 > 0 ? 2 :
                  (m3 > 0 ? 3 : 999)))

            let imageName =
                [1: "line", 2: "2line", 3: "3line", 999: "delay"][finger] ?? "questionmark"

            let t = CGFloat(max(0.02, duration / 5.0))

            out.append(
                .init(
                    primary: entry.primary,
                    finger: finger,
                    imageName: imageName,
                    duration: duration,
                    t: t,
                    start: start,
                    m1: m1,
                    m2: m2,
                    m3: m3,
                    delay: dly,
                    smoothStart: smoothStart,
                    smoothEnd: smoothEnd
                )
            )

            start += duration
        }

        return out
    }
    @State private var lastAutoScrollMarker: ProgressMarkerID? = nil
    private func width(for seg: Segment) -> CGFloat {
        let minW: CGFloat = max(8, viewportWidth * 0.02)
        let pointsPerSecond: CGFloat = 28   // tune this
        return max(minW, CGFloat(seg.duration) * pointsPerSecond)
    }
    @MainActor
    private func resumePlaybackFromVisiblePosition() {

        let visible = tapMsgRects
            .filter { _, r in r.maxX > tapViewport.minX && r.minX < tapViewport.maxX }

        guard let first = visible.min(by: { $0.value.minX < $1.value.minX }) else {
            return
        }

        let index = first.key

        applyVisualSeek(to: index)
        restartPlayback(from: index)
    }
    
    let lookAhead: CGFloat = 40
   
    var body: some View {
        let horizDrag = DragGesture(minimumDistance: 5)
            .onChanged { _ in

            }
            .onEnded { _ in

            }

        GeometryReader { geo in
            Color.clear
                .onAppear { viewportWidth = geo.size.width }
                .onChange(of: geo.size.width) { viewportWidth = $0 }

            ScrollViewReader { proxy in
                if inCard {
                    EmptyView()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 2) {
                                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                    let minW: CGFloat = max(8, viewportWidth * 0.02)
                                    let w = width(for: seg)
                                    ZStack(alignment: .leading) {
                                        Color.clear
                                            .frame(width: w, height: glyphSize)
                                            .contentShape(Rectangle())
                                            .background(
                                                GeometryReader { g in
                                                    Color.clear.preference(
                                                        key: TapMsgItemRectsKey.self,
                                                        value: [idx: g.frame(in: .named("tapMsgScroll"))]
                                                    )
                                                }
                                            )

                                        ForEach(0...markerStepsPerSegment, id: \.self) { step in
                                            let x = w * CGFloat(step) / CGFloat(markerStepsPerSegment)

                                            Color.clear
                                                .frame(width: 1, height: 1)
                                                .position(x: x, y: glyphSize * 0.5)
                                                .id(ProgressMarkerID(segment: idx, step: step))
                                        }
                                    }
                                    .id(idx)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                                    .background(
                                        (itemWidth == 0)
                                        ? AnyView(
                                            GeometryReader { g in
                                                Color.clear.onAppear { itemWidth = g.size.width + 2 }
                                            }
                                        )
                                        : AnyView(EmptyView())
                                    )
                                }
                            }
                            .padding(.horizontal, 6)
                            .frame(width: timelineWidth, alignment: .leading)

                            ConnectedTapMessageOverlay(
                                order: Array(segments.indices),
                                rects: tapMsgRects,
                                segments: segments,
                                progresses: progresses,
                                accent: selectedAccent,
                                showAccent: (isErasing || didComplete),
                                playingIndex: playingIndex,
                                activePart: activePart,
                                partProgress: partProgress
                            )
                            .frame(width: timelineWidth, alignment: .leading)
                            .clipped()
                        }
                        .frame(width: timelineWidth, alignment: .leading)
                        .clipped()
                    }
                    .coordinateSpace(name: "tapMsgScroll")
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: TapViewportKey.self,
                                value: g.frame(in: .named("tapMsgScroll"))
                            )
                        }
                    )
                    .onPreferenceChange(TapViewportKey.self) { tapViewport = $0 }
                    .simultaneousGesture(horizDrag)
                    .onAppear { scrollProxy = proxy }
                    .onPreferenceChange(TapMsgItemRectsKey.self) { r in
                        tapMsgRects.merge(r) { _, new in new }
                    }
                    .onChange(of: pendingScrollTo?.index) { _ in
                        guard let req = pendingScrollTo else { return }
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            proxy.scrollTo(req.index, anchor: req.anchor)
                        }
                        pendingScrollTo = nil
                    }
                }
            }
            .frame(
                width: !inCard ? geo.size.width : 0,
                height: !inCard ? geo.size.height : 0,
                alignment: .center
            )
        }
        .padding(10)
        .background(
            Group {
                if !inCard {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedAccent.opacity(0.3), lineWidth: 2)
                }
            }
        )
        .overlay {
            if !inCard && showProgressBorder {
                ProgressBorder(progress: eraseProgress, color: selectedAccent)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: UIScreen.main.bounds.height * 0.05,
            maxHeight: UIScreen.main.bounds.height * 0.3,
            alignment: .leading
        )
        .clipped()
        .onTapGesture {
            tappedHighlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tappedHighlight = false }

            if activeTapID != id {
                activeTapID = id
                startErase()
            } else {
                if isErasing {
                    cancelErase(fullStop: true)
                    activeTapID = nil
                } else {
                    startErase()
                }
            }
        }
        .onChange(of: activeTapID) { newValue in
            if newValue != id, isErasing {
                cancelErase()
            }
        }
        .onChange(of: segments.count) { newCount in
            if progresses.count != newCount {
                progresses = Array(repeating: 0, count: newCount)
            }
        }
        .onChange(of: activeTapID) { newValue in
            if newValue != id, isErasing {
                cancelErase()
                return
            }

            if newValue != id, !didComplete {
                progresses = Array(repeating: 0, count: segments.count)
                eraseProgress = 1
                showProgressBorder = false
                isErasing = false
            }
        }
        .onDisappear {
            cancelErase(fullStop: true)
            stopHapticNow()
            if activeTapID == id { activeTapID = nil }
        }
    }
    
    private func currentSegmentProgress() -> CGFloat {
        guard playingIndex < segments.count else { return 0 }

        let seg = segments[playingIndex]
        let total = seg.m1 + seg.m2 + seg.m3 + seg.delay
        guard total > 0 else { return 0 }

        if let part = activePart {
            var elapsed: Double = 0

            switch part {
            case .m1:
                elapsed = seg.m1 * Double(partProgress)
            case .m2:
                elapsed = seg.m1 + seg.m2 * Double(partProgress)
            case .m3:
                elapsed = seg.m1 + seg.m2 + seg.m3 * Double(partProgress)
            case .delay:
                elapsed = seg.m1 + seg.m2 + seg.m3 + seg.delay * Double(partProgress)
            }

            return max(0, min(1, CGFloat(elapsed / total)))
        }

        if playingIndex < progresses.count {
            return max(0, min(1, progresses[playingIndex]))
        }

        return 0
    }
    @MainActor
    private func resumePlaybackFromSavedState() {
        interruptPlayback()

        let index = max(0, min(resumeSegmentIndex, max(0, segments.count - 1)))
        playingIndex = index

        animationTask = Task { @MainActor in
            await play(
                from: index,
                startPart: resumePart,
                remainingInStartPart: resumePart == nil ? nil : resumeRemainingInPart
            )
        }
    }
    private func currentPlaybackX() -> CGFloat? {
        guard let r = tapMsgRects[playingIndex] else { return nil }

        let seg = segments[playingIndex]
        let total = seg.m1 + seg.m2 + seg.m3 + seg.delay

        var p: CGFloat = progresses[playingIndex]

        if playingIndex < progresses.count,
           progresses[playingIndex] < 1,
           let part = activePart {

            var elapsed: Double = 0

            switch part {
            case .m1:
                elapsed = seg.m1 * Double(partProgress)

            case .m2:
                elapsed = seg.m1 + seg.m2 * Double(partProgress)

            case .m3:
                elapsed = seg.m1 + seg.m2 + seg.m3 * Double(partProgress)

            case .delay:
                elapsed = seg.m1 + seg.m2 + seg.m3 + seg.delay * Double(partProgress)
            }

            p = CGFloat(elapsed / total)
        }

        return r.minX + r.width * p
    }
    @MainActor
    private func captureStartScrollPosition() {
        let visible = tapMsgRects
            .filter { _, r in r.maxX > tapViewport.minX && r.minX < tapViewport.maxX }

        if let leftmost = visible.min(by: { $0.value.minX < $1.value.minX })?.key {
            startScrollIndex = leftmost
        } else {
            startScrollIndex = 0
        }
        startScrollAnchor = .leading
    }

    @MainActor
    private func restoreStartScrollPosition() {
        guard !inCard, let idx = startScrollIndex else { return }
        pendingScrollTo = (idx, startScrollAnchor)
    }

    private func stopCurrentPlayer() {
        currentPlayers.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
        currentPlayers.removeAll()
    }

    private func pauseHapticsNow() {
        hapticsResumeWork?.cancel()
        hapticsPaused = true
        stopHapticNow()
    }

    private func stopHapticNow() {
        stopCurrentPlayer()
    }

    private func scheduleSpeedCooldown() {
        speedResetTask?.cancel()
        speedResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            speedTarget = 1.0
            withAnimation(.easeOut(duration: 0.25)) {
                playbackSpeed = 1.0
            }
        }
    }

    private func interruptPlayback() {
        animationTask?.cancel()
        animationTask = nil

        speedResetTask?.cancel()
        hapticsResumeTask?.cancel()
        hapticsResumeWork?.cancel()

        stopHapticNow()

        hapticsPaused = false
        isUserDragging = false

        boostUntilIndex = nil
        skipAheadRemaining = 0

        passedThroughIndex = -1
        playingIndex = 0
    }

    @MainActor
    private func keepPlaybackVisible(duration: Double) {
        guard let proxy = scrollProxy, canAutoScroll, !isUserDragging else { return }
        guard playingIndex < segments.count else { return }
        guard let playbackX = currentPlaybackX() else { return }

        let leftLimit = tapViewport.minX + lookAhead
        let rightLimit = tapViewport.maxX - lookAhead

        if playbackX >= leftLimit && playbackX <= rightLimit {
            return
        }

        let currentStep = max(
            0,
            min(
                markerStepsPerSegment,
                Int(round(currentSegmentProgress() * CGFloat(markerStepsPerSegment)))
            )
        )

        let markerID = ProgressMarkerID(segment: playingIndex, step: currentStep)

        guard markerID != lastAutoScrollMarker else { return }
        lastAutoScrollMarker = markerID

        let anchor: UnitPoint = playbackX > rightLimit ? .trailing : .leading

        withAnimation(.linear(duration: max(0.08, duration))) {
            proxy.scrollTo(markerID, anchor: anchor)
        }
    }
    private func scheduleHapticsResume(after seconds: Double = 0.5) {
        hapticsResumeTask?.cancel()
        let stopIndex = playingIndex
        hapticsResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !isUserDragging, playingIndex == stopIndex {
                hapticsPaused = false
            }
        }
    }

    private func currentPerItemWidth() -> CGFloat {
        (itemWidth > 0 ? itemWidth : estimatedItemWidth)
    }

    @MainActor
    private func waitWhilePaused(poll: UInt64 = 20_000_000) async {
        while hapticsPaused || isUserDragging {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: poll)
        }
    }

    private func adaptiveBoost(forDelta delta: CGFloat) -> Double {
        let screen = (viewportWidth > 0 ? viewportWidth : UIScreen.main.bounds.width * 0.2)
        let norm = max(0.0, min(1.0, Double(abs(delta) / screen)))
        let k = 4.0
        return maxBoost * (1.0 - exp(-k * norm))
    }

    @MainActor
    private func scrollToStart() {
        guard let proxy = scrollProxy else { return }

        let marker = ProgressMarkerID(segment: 0, step: 0)

        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(marker, anchor: .leading)
        }

        lastAutoScrollMarker = nil
    }
    
    @MainActor
    private func runPartInterruptible(
        original: Double,
        i: Int,
        advanceUI: @escaping (_ logicalAdvance: Double, _ actualDuration: Double) -> Void,
        startHaptic: (() -> Void)? = nil,
        stopHaptic: (() -> Void)? = nil
    ) async {
        guard original > 0 else { return }

        var remainingLogical = original
        var hapticStarted = false
        var lastTime = CACurrentMediaTime()

        while remainingLogical > 0 {

            if i <= passedThroughIndex {
                let snapReal = 0.06
                let logical = remainingLogical
                advanceUI(logical, snapReal)
                try? await Task.sleep(nanoseconds: UInt64(snapReal * 1_000_000_000))
                if hapticStarted { stopHaptic?() }
                return
            }

            if hapticsPaused || isUserDragging {
                if hapticStarted {
                    stopHaptic?()
                    hapticStarted = false
                }

                try? await Task.sleep(nanoseconds: 20_000_000)
                lastTime = CACurrentMediaTime()
                continue
            }

            if !hapticStarted {
                startHaptic?()
                hapticStarted = true
            }

            let now = CACurrentMediaTime()
            let realDelta = now - lastTime
            lastTime = now

            let s = (boostUntilIndex != nil && i <= boostUntilIndex!)
                ? max(0.5, min(4.0, playbackSpeed))
                : 1.0

            let logicalDelta = min(remainingLogical, realDelta * s)

            var tx = Transaction()
            if realDelta < 0.035 { tx.disablesAnimations = true }

            withTransaction(tx) {
                advanceUI(logicalDelta, realDelta)
            }

            remainingLogical -= logicalDelta

            try? await Task.sleep(nanoseconds: 16_666_667)   // ~60 fps
        }

        if hapticStarted { stopHaptic?() }
    }

    private func startErase() {
        interruptPlayback()

        guard totalDuration > 0, !segments.isEmpty else { return }

        didComplete = false

        Task { @MainActor in
            captureStartScrollPosition()
        }

        speedResetWork?.cancel()
        withAnimation(.none) { playbackSpeed = 1.0 }
        passedThroughIndex = -1

        finishWork?.cancel()
        animationTask?.cancel()
        stopHapticNow()

        hapticsResumeWork?.cancel()
        hapticsPaused = false
        dragStoppedAtIndex = nil

        resumeSegmentIndex = 0
        resumePart = nil
        resumeElapsedInPart = 0
        resumeRemainingInPart = 0

        isErasing = true
        showProgressBorder = true
        eraseProgress = 1.0
        timeElapsed = 0.0
        
        activePart = nil
        partProgress = 0
        playingIndex = 0
        progresses = Array(repeating: 0, count: segments.count)
        lastAutoScrolledTo = -1
        Task { @MainActor in
            scrollToStart()
        }
        animationTask = Task { @MainActor in
            await play(from: 0, startPart: nil, remainingInStartPart: nil)
        }
    }

    private func advanceBorderAndBar(
        i: Int,
        accBefore: Double,
        segTotalLogical: Double,
        logicalAdvance: Double,
        actualDuration: Double,
        partElapsedBefore: Double,
        partTotal: Double,
        partKind: PartKind
    ) {
        if hapticsPaused || isUserDragging { return }

        let logicalSoFar = accBefore + partElapsedBefore + logicalAdvance
        let targetBar = CGFloat(min(1.0, logicalSoFar / max(0.0001, segTotalLogical)))

        let partSoFar = partElapsedBefore + logicalAdvance
        let targetPart = CGFloat(min(1.0, partSoFar / max(0.0001, partTotal)))

        let rawBorder = 1.0 - CGFloat((timeElapsed + logicalAdvance) / max(0.0001, totalDuration))
        let targetBorder = max(0, rawBorder)
        let clampedBorder = min(eraseProgress, targetBorder)

        var tx = Transaction()
        if actualDuration < 0.035 {
            tx.disablesAnimations = true
        } else {
            tx.animation = .linear(duration: actualDuration)
        }

        withTransaction(tx) {
            self.progresses[i] = targetBar
            self.activePart = partKind
            self.partProgress = targetPart
            self.eraseProgress = clampedBorder
        }

        keepPlaybackVisible(duration: actualDuration)


        

        timeElapsed += logicalAdvance
    }


    @MainActor
    private func play(
        from startIndex: Int,
        startPart: PartKind? = nil,
        remainingInStartPart: Double? = nil
    ) async {
        guard activeTapID == id, !segments.isEmpty else {
            cancelErase()
            return
        }

        for (i, seg) in segments.enumerated() where i >= startIndex {
            guard !Task.isCancelled, activeTapID == id else {
                stopHapticNow()
                return
            }

            playingIndex = i


            var snapThisWholeSegment = false
            if skipAheadRemaining > 0 {
                snapThisWholeSegment = true
                skipAheadRemaining -= 1
            }

            let segTotalLogical = max(0.0001, seg.duration)
            var accLogicalInSeg: Double = 0

            let firstSegment = (i == startIndex)
            let startAtPart = firstSegment ? startPart : nil

            let m1Amount = amountToPlay(for: .m1, in: seg, startAtPart: startAtPart, remaining: remainingInStartPart)
            let m2Amount = amountToPlay(for: .m2, in: seg, startAtPart: startAtPart, remaining: remainingInStartPart)
            let m3Amount = amountToPlay(for: .m3, in: seg, startAtPart: startAtPart, remaining: remainingInStartPart)
            let delayAmount = amountToPlay(for: .delay, in: seg, startAtPart: startAtPart, remaining: remainingInStartPart)

            if shouldMarkPartCompletedBeforePlayback(.m1, startAtPart: startAtPart) {
                accLogicalInSeg += seg.m1
            }
            if shouldMarkPartCompletedBeforePlayback(.m2, startAtPart: startAtPart) {
                accLogicalInSeg += seg.m2
            }
            if shouldMarkPartCompletedBeforePlayback(.m3, startAtPart: startAtPart) {
                accLogicalInSeg += seg.m3
            }
            if shouldMarkPartCompletedBeforePlayback(.delay, startAtPart: startAtPart) {
                accLogicalInSeg += seg.delay
            }

            if m1Amount > 0 {
                await playPart(
                    partKind: .m1,
                    seg: seg,
                    i: i,
                    accLogicalInSeg: &accLogicalInSeg,
                    segTotalLogical: segTotalLogical,
                    amount: m1Amount,
                    snapThisWholeSegment: snapThisWholeSegment
                )
            }

            if m2Amount > 0 {
                await playPart(
                    partKind: .m2,
                    seg: seg,
                    i: i,
                    accLogicalInSeg: &accLogicalInSeg,
                    segTotalLogical: segTotalLogical,
                    amount: m2Amount,
                    snapThisWholeSegment: snapThisWholeSegment
                )
            }

            if m3Amount > 0 {
                await playPart(
                    partKind: .m3,
                    seg: seg,
                    i: i,
                    accLogicalInSeg: &accLogicalInSeg,
                    segTotalLogical: segTotalLogical,
                    amount: m3Amount,
                    snapThisWholeSegment: snapThisWholeSegment
                )
            }

            if delayAmount > 0 {
                await playPart(
                    partKind: .delay,
                    seg: seg,
                    i: i,
                    accLogicalInSeg: &accLogicalInSeg,
                    segTotalLogical: segTotalLogical,
                    amount: delayAmount,
                    snapThisWholeSegment: snapThisWholeSegment
                )
            }

            self.progresses[i] = 1
            resumeSegmentIndex = min(i + 1, max(0, segments.count - 1))
            resumePart = nil
            resumeElapsedInPart = 0
            resumeRemainingInPart = 0

            if let lim = boostUntilIndex, i >= lim {
                boostUntilIndex = nil
                speedResetWork?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    playbackSpeed = 1.0
                }
            }
        }

        stopHapticNow()
        didComplete = true

        isErasing = false
        showProgressBorder = false
        eraseProgress = 1

        speedResetWork?.cancel()
        withAnimation(.none) { playbackSpeed = 1.0 }
        boostUntilIndex = nil
        passedThroughIndex = -1
        playingIndex = 0

        let idx = startScrollIndex ?? 0

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            pendingScrollTo = (idx, .leading)
            startScrollIndex = nil
        }

        activePart = nil
        partProgress = 0

        if activeTapID == id { activeTapID = nil }
    }

    private func shouldMarkPartCompletedBeforePlayback(_ kind: PartKind, startAtPart: PartKind?) -> Bool {
        guard let startAtPart else { return false }
        return partOrder(kind) < partOrder(startAtPart)
    }

    private func amountToPlay(
        for kind: PartKind,
        in seg: Segment,
        startAtPart: PartKind?,
        remaining: Double?
    ) -> Double {
        let full = partDuration(for: kind, in: seg)
        guard full > 0 else { return 0 }

        guard let startAtPart else { return full }

        if partOrder(kind) < partOrder(startAtPart) {
            return 0
        } else if kind == startAtPart {
            return max(0, min(full, remaining ?? full))
        } else {
            return full
        }
    }

    private func partOrder(_ kind: PartKind) -> Int {
        switch kind {
        case .m1: return 0
        case .m2: return 1
        case .m3: return 2
        case .delay: return 3
        }
    }

    private func partDuration(for kind: PartKind, in seg: Segment) -> Double {
        switch kind {
        case .m1: return seg.m1
        case .m2: return seg.m2
        case .m3: return seg.m3
        case .delay: return seg.delay
        }
    }

    private func cancelAutoscrollImmediately() {
        lastAutoScrolledTo = playingIndex
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { }
    }

    private func cancelErase(fullStop: Bool = true) {
        finishWork?.cancel()
        animationTask?.cancel()
        animationTask = nil

        stopHapticNow()

        if fullStop {
            Haptics.shared.hardStopEngine()
        }

        hapticsResumeWork?.cancel()
        hapticsPaused = false
        dragStoppedAtIndex = nil

        withAnimation(.none) {
            isErasing = false

            Task { @MainActor in
                restoreStartScrollPosition()
                startScrollIndex = nil
            }

            showProgressBorder = false
            eraseProgress = 1
            didComplete = false
            progresses = Array(repeating: 0, count: segments.count)
        }
    }


    private func cumulativeDuration(upTo index: Int) -> Double {
        guard index > 0 else { return 0 }
        return segments.prefix(index).reduce(0) { $0 + $1.duration }
    }

    @MainActor
    private func applyVisualSeek(to index: Int) {
        guard !segments.isEmpty else { return }
        let idx = max(0, min(index, segments.count - 1))

        progresses = segments.enumerated().map { i, _ in i < idx ? 1.0 : 0.0 }

        let elapsed = cumulativeDuration(upTo: idx)
        timeElapsed = elapsed
        let ratio = CGFloat(elapsed / max(0.0001, totalDuration))
        eraseProgress = 1.0 - ratio

        playingIndex = idx
        lastAutoScrolledTo = -1

        resumeSegmentIndex = idx
        resumePart = nil
        resumeElapsedInPart = 0
        resumeRemainingInPart = 0
    }

    @MainActor
    private func restartPlayback(from index: Int) {
        interruptPlayback()
        applyVisualSeek(to: index)

        animationTask = Task { @MainActor in
            await play(from: index, startPart: nil, remainingInStartPart: nil)
        }
    }
}


private struct TapViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ProgressBorder: View {
    var progress: CGFloat
    var color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .trim(from: 0, to: progress)
            .stroke(color, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .scaleEffect(x: -1, y: 1)
            // no compositingGroup here
    }
}


 struct ConnectedWaveOverlay: View {
     let order: [Int]
     let rects: [Int: CGRect]
     let entriesByColumnId: [Int: [TapEntry]]
     let colorForColumnId: (Int) -> Color
     let selectedColumnIds: Set<Int>
     let selectedConnectionIds: Set<Double>

     let availableWidth: CGFloat
     let maxValue: CGFloat = 60

     let onToggleColumn: (Int) -> Void
     let onToggleConnection: (Double) -> Void

     @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

     @Binding var hitRanges: [(id: Int, minX: CGFloat, maxX: CGFloat, y: CGFloat)]
     @Binding var connectionHitRanges: [
         (id: Double,
          start: CGPoint,
          end: CGPoint,
          minX: CGFloat, maxX: CGFloat,
          minY: CGFloat, maxY: CGFloat)
     ]


     let accentedColor: Color
     private let minValue: CGFloat = 0.01

     private func normalizedLog(_ v: CGFloat) -> CGFloat {
         let v = max(minValue, min(v, maxValue))
         let a = log(minValue)
         let b = log(maxValue)
         let x = log(v)
         return max(0, min(1, (x - a) / (b - a)))
     }

     let connectorCap: CGFloat = 1


     private func normalized(_ v: CGFloat) -> CGFloat {
         let denom = max(0.000001, maxValue - minValue)
         return max(0, min(1, (v - minValue) / denom))
     }

     private func normalizedLog(_ v: CGFloat) -> CGFloat {
         // clamp to avoid log(0)
         let v = max(minValue, min(v, maxValue))

         // log-space normalize between minValue and maxValue
         let a = log(minValue)
         let b = log(maxValue)
         let x = log(v)
         return max(0, min(1, (x - a) / (b - a)))
     }



     var body: some View {
         ZStack(alignment: .topLeading) {
             // 1) DRAWING: never intercept touches
             Canvas { context, _ in
                 func level(for types: [String]) -> CGFloat {
                     let tset = Set(types.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
                     if tset.contains("m3")    { return 0.1 }
                     if tset.contains("m2")    { return 0.4 }
                     if tset.contains("m1")    { return 0.7 }
                     if tset.contains("servo") { return 0.70 }
                     if tset.contains("delay") { return 0.9 }
                     return 0.50
                 }

                 func yForColumn(id: Int) -> CGFloat? {
                     guard let r = rects[id], let entries = entriesByColumnId[id] else { return nil }
                     return r.minY + r.height * level(for: entries.map(\.entryType))
                 }

                 var cols: [(id: Int, r: CGRect, y: CGFloat)] = []
                 cols.reserveCapacity(order.count)
                 for id in order {
                     guard let r = rects[id], let y = yForColumn(id: id) else { continue }
                     cols.append((id: id, r: r, y: y))
                 }
                 guard !cols.isEmpty else { return }

                 let baseW: CGFloat = 3.0
                 let topW: CGFloat  = 2.2
                 let underlayStyle = StrokeStyle(lineWidth: baseW, lineCap: .round, lineJoin: .round)
                 let topStyle      = StrokeStyle(lineWidth: topW,  lineCap: .round, lineJoin: .round)

                 func capWidth(from aId: Int, to bId: Int) -> CGFloat {
                     min(connectorWidth(for: aId), connectorWidth(for: bId))
                 }


                 func isSelectedEdge(from aId: Int, to bId: Int? = nil) -> Bool {
                     selectedColumnIds.contains(aId) || (bId.map { selectedColumnIds.contains($0) } ?? false)
                 }

                 // IMPORTANT: appends WITHOUT starting a new subpath (no move inside)
                 func appendRoundedConnector(
                     _ path: inout Path,
                     from start: CGPoint,
                     to mid: CGPoint,
                     to end: CGPoint,
                     radius rWanted: CGFloat
                 ) {
                     let ax = start.x
                     let ay = start.y
                     let by = mid.y
                     let ex = end.x

                     let dy = by - ay
                     let dx = ex - ax

                     // Degenerate: sharp
                     guard abs(dy) > 0.001, abs(dx) > 0.001 else {
                         path.addLine(to: mid)
                         path.addLine(to: end)
                         return
                     }

                     let r = min(rWanted, abs(dy) * 0.45, abs(dx) * 0.45)
                     let signY: CGFloat = (dy > 0) ? 1 : -1
                     let signX: CGFloat = (dx > 0) ? 1 : -1

                     let v1Start = CGPoint(x: ax, y: ay + signY * r)
                     let v2End   = CGPoint(x: ax, y: by - signY * r)
                     let h2Start = CGPoint(x: ax + signX * r, y: by)

                     // assume we're already at `start`
                     path.addQuadCurve(to: v1Start, control: CGPoint(x: ax, y: ay))
                     path.addLine(to: v2End)
                     path.addQuadCurve(to: h2Start, control: CGPoint(x: ax, y: by))
                     path.addLine(to: end)
                 }

                 // Helper to keep continuity (avoid move unless necessary)
                 func isSamePoint(_ a: CGPoint?, _ b: CGPoint, eps: CGFloat = 0.01) -> Bool {
                     guard let a else { return false }
                     return abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
                 }

                 
                 var newHitRanges: [(id: Int, minX: CGFloat, maxX: CGFloat, y: CGFloat)] = []
                 newHitRanges.reserveCapacity(cols.count)
                 var under = Path()
                 
                 do {
                     var incoming: [Int: CGFloat] = [:]
                     let first = cols[0]
                     let startX = incoming[first.id] ?? first.r.minX
                     under.move(to: CGPoint(x: startX, y: first.y))
                     for i in cols.indices {
                         let a = cols[i]
                         let aStartX = incoming[a.id] ?? a.r.minX
                         let aEndX   = segmentEndX(id: a.id, rect: a.r)

                         under.addLine(to: CGPoint(x: aStartX, y: a.y))
                         under.addLine(to: CGPoint(x: aEndX,   y: a.y))


                     }
                 }
                 context.stroke(under, with: .color(accentedColor.opacity(0.6)), style: underlayStyle)


                 var incomingStartX: [Int: CGFloat] = [:]
                 var topSelected = Path()
                 var lastSel: CGPoint? = nil
                 var topUnselectedById: [Int: Path] = [:]
                 var lastUnselById: [Int: CGPoint] = [:]
                 topUnselectedById.reserveCapacity(cols.count)
                 lastUnselById.reserveCapacity(cols.count)
                 func addLine(toSelected: Bool, idForUnsel: Int, from: CGPoint, to: CGPoint) {
                     if toSelected {
                         if !isSamePoint(lastSel, from) { topSelected.move(to: from) }
                         topSelected.addLine(to: to)
                         lastSel = to
                     } else {
                         var p = topUnselectedById[idForUnsel] ?? Path()
                         let last = lastUnselById[idForUnsel]
                         if !isSamePoint(last, from) { p.move(to: from) }
                         p.addLine(to: to)
                         topUnselectedById[idForUnsel] = p
                         lastUnselById[idForUnsel] = to
                     }
                 }

                 func addConnector(toSelected: Bool, idForUnsel: Int, start: CGPoint, mid: CGPoint, end: CGPoint) {
                     if toSelected {
                         if !isSamePoint(lastSel, start) { topSelected.move(to: start) }
                         appendRoundedConnector(&topSelected, from: start, to: mid, to: end, radius: 3)
                         lastSel = end
                     } else {
                         var p = topUnselectedById[idForUnsel] ?? Path()
                         let last = lastUnselById[idForUnsel]
                         if !isSamePoint(last, start) { p.move(to: start) }
                         appendRoundedConnector(&p, from: start, to: mid, to: end, radius: 3)
                         topUnselectedById[idForUnsel] = p
                         lastUnselById[idForUnsel] = end
                     }
                 }
                 
                 
                 for i in cols.indices {
                     let a = cols[i]

                     let aStartX = incomingStartX[a.id] ?? a.r.minX
                     let aEndX   = segmentEndX(id: a.id, rect: a.r)

                     // hit range stays based on the visible horizontal
                     newHitRanges.append((id: a.id,
                                          minX: min(aStartX, aEndX),
                                          maxX: max(aStartX, aEndX),
                                          y: a.y))

                     // Horizontal rule: selected if this column is selected
                     let hSel = selectedColumnIds.contains(a.id)
                     addLine(toSelected: hSel,
                             idForUnsel: a.id,
                             from: CGPoint(x: aStartX, y: a.y),
                             to:   CGPoint(x: aEndX,   y: a.y))


                 }
                 for (id, path) in topUnselectedById {
                     context.stroke(path, with: .color(colorForColumnId(id)), style: topStyle)
                 }
                 context.stroke(topSelected, with: .color(.secondary.opacity(0.6)), style: topStyle)
                 
                 // Update hitRanges
                 DispatchQueue.main.async {
                     if self.hitRanges.map(\.id) != newHitRanges.map(\.id)
                         || self.hitRanges.map(\.minX) != newHitRanges.map(\.minX)
                         || self.hitRanges.map(\.maxX) != newHitRanges.map(\.maxX)
                         || self.hitRanges.map(\.y) != newHitRanges.map(\.y) {
                         self.hitRanges = newHitRanges
                     }
                 }
             }
             .allowsHitTesting(false)

         }
     }

     private func easedOut(_ t: CGFloat, power p: CGFloat = 2.0) -> CGFloat {
         let t = max(0, min(1, t))
         return 1 - pow(1 - t, p)
     }

     private func connectorWidth(for id: Int) -> CGFloat {
         let v = drivingValue(for: id)
         let t = normalizedLog(v)
         return availableWidth * t
     }

     private func segmentWidth(for id: Int) -> CGFloat {
         let v = drivingValue(for: id)
         let t = normalizedLog(v)
         let minW: CGFloat = availableWidth * 0.001
         return max(minW, availableWidth * t)
     }


     private func drivingValue(for id: Int) -> CGFloat {
         guard let entries = entriesByColumnId[id] else { return 0 }
         let raw = entries
             .filter { $0.entryType.lowercased() != "servo" }
             .map { CGFloat($0.value) }
             .max() ?? 0
         return max(0, raw)
     }

     private func segmentEndX(id: Int, rect: CGRect) -> CGFloat {
         min(rect.maxX, rect.minX + segmentWidth(for: id))
     }

     private func computedEnds() -> [Int: CGFloat] {
         var ends: [Int: CGFloat] = [:]
         ends.reserveCapacity(order.count)
         for id in order {
             guard let r = rects[id] else { continue }
             ends[id] = segmentEndX(id: id, rect: r)
         }
         return ends
     }
 }

struct ScrollXKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

func previousId(before id: Int, in sortedIds: [Int]) -> Int? {
    guard let i = sortedIds.firstIndex(of: id), i > 0 else { return nil }
    return sortedIds[i - 1]
}

struct ItemEndsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ItemRectsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct ViewportTapKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
struct ViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue() // single rect is fine
    }
}


func hasConsecutives(tapsToModify: [TapEntry]) -> Bool {
    let filtered = tapsToModify.filter { $0.value != 0.0 }
    guard filtered.count >= 2 else { return false }

    func isMotor(_ type: String) -> Bool {
        switch type.lowercased() {
        case "m1", "m2", "m3": return true
        default: return false
        }
    }

    for i in 0..<(filtered.count - 1) {
        let a = filtered[i]
        let b = filtered[i + 1]

        let at = a.entryType.lowercased()
        let bt = b.entryType.lowercased()

        // delay next to delay
        if at == "delay" && bt == "delay" {
            return true
        }

        // motor next to motor (any tier)
        if isMotor(at) && isMotor(bt) {
            return true
        }
    }

    return false
}


/// 3-level waveform: up / mid / down
private enum WaveLevel: CGFloat {
    case up = 0.15
    case mid = 0.50
    case down = 0.85
}

private func level(for entryType: String) -> WaveLevel? {
    switch entryType {
    case "m2":    return .up
    case "m1":    return .mid
    case "delay": return .down
    case "servo": return nil       // ignore servo (or return .mid if you want it flat)
    default:      return .mid
    }
}




private func colorForGroup(cmnd: Int, type: Int, groupId: Int) -> Color? {
    guard groupId != 0 else { return nil }
    var hasher = Hasher()
    hasher.combine(cmnd)
    hasher.combine(type)
    hasher.combine(groupId)
    let hue = Double(abs(hasher.finalize()) % 360) / 360.0
    return Color(hue: hue, saturation: 0.65, brightness: 0.9)
}
func checkTapEntries(
    TapEntries: [TapEntry],
    selectedCMND: Int
) -> (justAppendedVibration: Bool, justAppendedDelays: Bool, LimitReached: Bool) {

    func isMotor(_ type: String) -> Bool {
        switch type.lowercased() {
        case "m1", "m2", "m3": return true
        default: return false
        }
    }

    // Count vibrations (non-zero motors)
    let vibrationCount = TapEntries.reduce(0) { count, e in
        (isMotor(e.entryType) && e.value != 0.0) ? (count + 1) : count
    }
    let limitReached = (vibrationCount >= 100)

    // Find last and previous non-zero entries
    guard let lastIdx = TapEntries.lastIndex(where: { $0.value != 0.0 }) else {
        return (false, false, limitReached)
    }
    let last = TapEntries[lastIdx]
    let prev = TapEntries[..<lastIdx].last(where: { $0.value != 0.0 })

    var justAppendedVibration = false
    var justAppendedDelays = false

    let lastType = last.entryType.lowercased()

    if lastType == "delay" {
        justAppendedDelays = true

    } else if isMotor(last.entryType) {
        if last.groupId > 0 {
            // only treat as vibration if the previous non-zero is also a motor
            if let p = prev, isMotor(p.entryType) {
                justAppendedVibration = true
            } else {
                justAppendedVibration = false // your special case

                // if skipping as vibration, check if previous is a delay
                if let p = prev, p.entryType.lowercased() == "delay" {
                    justAppendedDelays = true
                }
            }
        } else {
            // ungrouped motor
            justAppendedVibration = true
        }
    }

    return (justAppendedVibration, justAppendedDelays, limitReached)
}

struct LongTailArrow: Shape {
    enum Direction { case left, right }
    var direction: Direction

    // +25% head size
    var headLengthRatio: CGFloat = 0.34 * 1.25   // 0.425

    // +25% tail thickness
    var tailThicknessRatio: CGFloat = 0.25 * 1.25 // 0.15

    // corner radius driver for the head corners (NOT bending edges)
    var tipRadiusRatio: CGFloat = 0.3

    // −25% inset → longer tail
    var edgeInsetRatio: CGFloat = 0.2 * 0.75      // 0.15

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let midY = h / 2

        let inset = w * edgeInsetRatio

        let headL = max(1, (w - inset) * headLengthRatio)
        let tailT = max(1, h * tailThicknessRatio)
        let halfT = tailT / 2

        let headXLeft  = inset + headL
        let headXRight = w - inset - headL

        // Desired corner radius for head corners only
        let desiredR = min(
            h * tipRadiusRatio,
            headL * 0.28,   // avoids “flower”
            tailT * 0.90
        )

        // Helper: move from point a toward b by distance d
        func toward(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> CGPoint {
            let vx = b.x - a.x
            let vy = b.y - a.y
            let len = max(0.0001, sqrt(vx*vx + vy*vy))
            return CGPoint(x: a.x + vx / len * d, y: a.y + vy / len * d)
        }

        // Helper: safe radius limited by the two adjacent edges
        func cornerRadius(_ c: CGPoint, _ p: CGPoint, _ n: CGPoint, _ r: CGFloat) -> CGFloat {
            let lp = hypot(c.x - p.x, c.y - p.y)
            let ln = hypot(c.x - n.x, c.y - n.y)
            return min(r, lp * 0.45, ln * 0.45)
        }

        var p = Path()

        switch direction {
        case .left:
            let tip     = CGPoint(x: inset, y: midY)
            let headTop = CGPoint(x: headXLeft, y: 0)
            let headBot = CGPoint(x: headXLeft, y: h)

            let neckTop = CGPoint(x: headXLeft, y: midY - halfT)
            let neckBot = CGPoint(x: headXLeft, y: midY + halfT)

            let tailTopR = CGPoint(x: w - inset, y: midY - halfT)
            let tailBotR = CGPoint(x: w - inset, y: midY + halfT)

            // Radii for the 3 rounded head corners
            let rTip = cornerRadius(tip, headTop, headBot, desiredR)
            let rTop = cornerRadius(headTop, tip, neckTop, desiredR)
            let rBot = cornerRadius(headBot, neckBot, tip, desiredR)

            // Fillet points around each rounded corner
            let tipToTop = toward(tip, headTop, rTip)
            let tipToBot = toward(tip, headBot, rTip)

            let topToTip  = toward(headTop, tip, rTop)
            let topToNeck = toward(headTop, neckTop, rTop)

            let botToNeck = toward(headBot, neckBot, rBot)
            let botToTip  = toward(headBot, tip, rBot)

            // Walk the outline with straight edges + tiny quad curves at corners
            p.move(to: tipToTop)                       // start on edge near tip
            p.addLine(to: topToTip)                    // straight edge
            p.addQuadCurve(to: topToNeck, control: headTop) // rounded headTop corner

            p.addLine(to: neckTop)                     // sharp neck (straight)
            p.addLine(to: tailTopR)
            p.addLine(to: tailBotR)
            p.addLine(to: neckBot)                     // sharp neck

            p.addLine(to: botToNeck)
            p.addQuadCurve(to: botToTip, control: headBot)  // rounded headBot corner

            p.addLine(to: tipToBot)
            p.addQuadCurve(to: tipToTop, control: tip)      // rounded tip corner
            p.closeSubpath()

        case .right:
            let tip     = CGPoint(x: w - inset, y: midY)
            let headTop = CGPoint(x: headXRight, y: 0)
            let headBot = CGPoint(x: headXRight, y: h)

            let neckTop = CGPoint(x: headXRight, y: midY - halfT)
            let neckBot = CGPoint(x: headXRight, y: midY + halfT)

            let tailTopL = CGPoint(x: inset, y: midY - halfT)
            let tailBotL = CGPoint(x: inset, y: midY + halfT)

            let rTip = cornerRadius(tip, headTop, headBot, desiredR)
            let rTop = cornerRadius(headTop, tip, neckTop, desiredR)
            let rBot = cornerRadius(headBot, neckBot, tip, desiredR)

            let tipToTop = toward(tip, headTop, rTip)
            let tipToBot = toward(tip, headBot, rTip)

            let topToTip  = toward(headTop, tip, rTop)
            let topToNeck = toward(headTop, neckTop, rTop)

            let botToNeck = toward(headBot, neckBot, rBot)
            let botToTip  = toward(headBot, tip, rBot)

            p.move(to: tipToTop)
            p.addLine(to: topToTip)
            p.addQuadCurve(to: topToNeck, control: headTop)

            p.addLine(to: neckTop)
            p.addLine(to: tailTopL)
            p.addLine(to: tailBotL)
            p.addLine(to: neckBot)

            p.addLine(to: botToNeck)
            p.addQuadCurve(to: botToTip, control: headBot)

            p.addLine(to: tipToBot)
            p.addQuadCurve(to: tipToTop, control: tip)
            p.closeSubpath()
        }

        return p
    }
}









func buildHapticTimeline(from entries: [TapEntry]) -> [HapticStep] {
    func isMotor(_ type: String) -> Bool {
        switch type.lowercased() {
        case "m1", "m2", "m3": return true
        default: return false
        }
    }

    // Split by group
    let sequential = entries.filter { $0.groupId == 0 }
    let grouped = Dictionary(grouping: entries.filter { $0.groupId > 0 }, by: { $0.groupId })

    // Convert groups into keyed steps (a group can become multiple steps)
    let groupedSteps: [(minKey: Int, step: HapticStep)] = grouped.flatMap { (_, arr) -> [(minKey: Int, step: HapticStep)] in
        let sorted = arr.sorted { $0.key < $1.key }
        guard let firstKey = sorted.first?.key else { return [] }

        // Separate motors vs others (keep others as singles)
        let motors = sorted.filter { isMotor($0.entryType) && $0.value != 0.0 }
        let nonMotors = sorted.filter { !isMotor($0.entryType) && $0.value != 0.0 }

        var out: [(minKey: Int, step: HapticStep)] = []

        // Pair motors into parallel steps in deterministic order
        var i = 0
        while i + 1 < motors.count {
            let a = motors[i]
            let b = motors[i + 1]
            let k = min(a.key, b.key)
            out.append((k, .parallel(a, b)))
            i += 2
        }

        // If odd motor remains, it becomes a single
        if i < motors.count {
            out.append((motors[i].key, .single(motors[i])))
        }

        // Any non-motor entries in the group are played as singles too
        for e in nonMotors {
            out.append((e.key, .single(e)))
        }

        // If group had only zero values, emit nothing
        // (firstKey not used directly; keys of produced steps handle ordering)
        return out
    }

    // Turn sequential into keyed steps too (so we can interleave correctly by key)
    let sequentialSteps: [(minKey: Int, step: HapticStep)] =
        sequential
            .filter { $0.value != 0.0 }
            .map { (minKey: $0.key, step: .single($0)) }

    // Merge and order by key so group blocks occur at their timeline position
    return (sequentialSteps + groupedSteps)
        .sorted { $0.minKey < $1.minKey }
        .map { $0.step }
}



enum HalfSide { case left, right }

enum ThirdSide { case left, middle, right }

@ViewBuilder
func thirdHighlight(side: ThirdSide,
                    width: CGFloat,
                    height: CGFloat,
                    color: Color,
                    active: Bool) -> some View {
    let r = height / 2

    UnevenRoundedRectangle(
        topLeadingRadius:    side == .left  ? r : 0,
        bottomLeadingRadius: side == .left  ? r : 0,
        bottomTrailingRadius:side == .right ? r : 0,
        topTrailingRadius:   side == .right ? r : 0,
        style: .continuous
    )
    .fill(active ? color.opacity(0.30) : .clear)
    .frame(width: width, height: height)
}


@ViewBuilder
func halfHighlight(side: HalfSide, width: CGFloat, height: CGFloat, color: Color, active: Bool) -> some View {
    let r = height / 2
    UnevenRoundedRectangle(
        topLeadingRadius:   side == .left  ? r : 0,
        bottomLeadingRadius:side == .left  ? r : 0,
        bottomTrailingRadius:side == .right ? r : 0,
        topTrailingRadius:  side == .right ? r : 0,
        style: .continuous
    )
    .fill(active ? color.opacity(0.30) : .clear)
    .frame(width: width, height: height)
}
private func powerString(for number: Int) -> String {
    switch number {
    case 1: return "light"
    case 2: return "soft"
    case 3: return "medium"
    case 4: return "rigid"
    case 5: return "heavy"
    default: return "medium"
    }
}

@ViewBuilder
func segmentHighlight(index: Int, count: Int, width: CGFloat, height: CGFloat, color: Color, active: Bool) -> some View {
    let r = height / 2
    UnevenRoundedRectangle(
        topLeadingRadius:    index == 0 ? r : 0,
        bottomLeadingRadius: index == 0 ? r : 0,
        bottomTrailingRadius:index == count - 1 ? r : 0,
        topTrailingRadius:   index == count - 1 ? r : 0,
        style: .continuous
    )
    .fill(active ? color.opacity(0.30) : .clear)
    .frame(width: width, height: height)
}

struct ControlOptions: View {
    @Binding var isPresented: Bool
    let isServo: Bool
    let accent: Color
    @Binding var selectedLayout: Int
    @Binding var selectedSet: Set<Int>
    var onSelectNumber: (_ n: Int) -> Void

    @State private var selectedNumber: Int = 1       // 1...10
    @State private var selectedNumber2: Int = 1
    @State private var shown = false
    @State private var dragOffset: CGFloat = 0     // ← persistent offset (no GestureState)
    private let corner: CGFloat = 22
    @State private var selectedServoPart: Int = 1

    private var sheetHeight: CGFloat { UIScreen.main.bounds.height * 0.4 }
    private let dismissDistance: CGFloat = 120
    private let dismissVelocity: CGFloat = 1200

    private func dismiss(animated: Bool = true) {
        let animate: (()->Void) -> Void = { changes in
            animated ? withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { changes() }
                     : changes()
        }
        // Slide the sheet fully down, fade the backdrop, then remove
        animate {
            shown = false
            dragOffset = sheetHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    @State private var isVibConnected: Bool = false // or pass in as @Binding/param

    var body: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            Color.black.opacity(shown ? 0.35 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // SHEET
            // SHEET
            VStack(spacing: 14) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {

                        // ===== Capsule 1 with title "Type" =====
                        VStack(alignment: .leading, spacing: 4) {
                            Text("power".localized())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            ZStack {
                                GeometryReader { g in
                                    let h = g.size.height
                                    let count = 3
                                    let segW = g.size.width / CGFloat(count)

                                    Capsule().fill(Color.gray.opacity(0.16))

                                    // highlight selected segment
                                    Group {
                                        if selectedLayout == 1 {
                                            thirdHighlight(side: .left, width: segW, height: h, color: accent, active: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .offset(x: 0)
                                        } else if selectedLayout == 2 {
                                            thirdHighlight(side: .middle, width: segW, height: h, color: accent, active: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .offset(x: segW)
                                        } else if selectedLayout == 3 {
                                            thirdHighlight(side: .right, width: segW, height: h, color: accent, active: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .offset(x: segW * 2)
                                        }
                                    }

                                    // dividers
                                    ForEach(1..<count) { i in
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.28))
                                            .frame(width: 1, height: h - 6)
                                            .position(x: segW * CGFloat(i), y: h / 2)
                                    }
                                }
                                .clipShape(Capsule())


                                HStack(spacing: 0) {
                                    Button {
                                        selectedLayout = 1
                                        Haptics.shared.vibrate(duration: 0.1, power: "low", immediate: true) { }
                                    } label: {
                                        iconView("line")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        selectedLayout = 2
                                        Haptics.shared.vibrate(duration: 0.1, power: "medium",immediate: true) { }
                                    } label: {
                                        iconView("2line")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    
                                    Button {
                                        selectedLayout = 3
                                        Haptics.shared.vibrate(duration: 0.1, power: "large",immediate: true) { }
                                    } label: {
                                        iconView("3menu")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                            }
                            .frame(height: 36)
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        }
                        .padding(.horizontal, 16)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedLayout)


                        // =========================
                        // Servo section BELOW (always shown)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("haptics_side".localized())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            VStack(alignment: .center, spacing: 12) {
                                ServoCircle(selected: $selectedSet, accent: accent)
                                    .frame(
                                        width: UIScreen.main.bounds.height * 0.25,
                                        height: UIScreen.main.bounds.height * 0.25
                                    )
                                    .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            .frame(height: sheetHeight, alignment: .top) // <- key change
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(.systemGray5))
                    .ignoresSafeArea(edges: .bottom)
            )
            // Use persistent offset
            .offset(y: max(0, dragOffset))
            // Single drag gesture with onChanged / onEnded
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        // only allow pulling down
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let y = value.translation.height
                        let v = value.predictedEndLocation.y - value.location.y // rough velocity proxy
                        if y > dismissDistance || v > dismissVelocity {
                            dismiss()
                        } else {
                            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .onChange(of: selectedSet) { set in
                selectedServoPart = set.first ?? 0 // or your own rule
            }
            .onChange(of: selectedServoPart) { part in
                selectedSet = part == 0 ? [] : [part]
            }

            .transition(.move(edge: .bottom).combined(with: .opacity))

        }
        .zIndex(1000)
    }

    @ViewBuilder
    func iconView(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .tint(.primary)
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(90))
    }
}

// MARK: - Servo Circle
private struct ServoCircle: View {
    @Binding var selected: Set<Int>
    let accent: Color
    @State private var showRotateFlash = false

    @AppStorage("isServoRotateUp") private var isServoRotateUp: Bool = false

    private func angles(for id: Int) -> (start: Angle, end: Angle) {
        switch id {
        case 1: return (.degrees(30),  .degrees(150))  // Top
        case 2: return (.degrees(150), .degrees(270))  // Left
        default: return (.degrees(270), .degrees(390)) // Right (wraps past 360)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size   = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2

            ZStack {
                // ✅ Servo graphic (this part rotates)
                ZStack {
                    // Base fill + single perimeter stroke
                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))

                    ForEach([1, 2, 3], id: \.self) { id in
                        if selected.contains(id) {
                            let a = angles(for: id)
                            Path { p in
                                p.move(to: center)
                                p.addArc(center: center,
                                         radius: radius,
                                         startAngle: a.start,
                                         endAngle: a.end,
                                         clockwise: false)
                                p.closeSubpath()
                            }
                            .fill(accent.opacity(0.35))
                            .allowsHitTesting(false)
                        }
                    }

                    // Radial separators (one clean line each)
                    ForEach([Angle.degrees(30), .degrees(150), .degrees(270)], id: \.degrees) { ang in
                        Path { p in
                            p.move(to: center)
                            p.addLine(to: CGPoint(
                                x: center.x + radius * CGFloat(cos(ang.radians)),
                                y: center.y + radius * CGFloat(sin(ang.radians))
                            ))
                        }
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }

                    // Invisible hit regions to toggle membership
                    Sector(start: .degrees(30), end: .degrees(150))
                        .fill(Color.clear)
                        .contentShape(Sector(start: .degrees(30), end: .degrees(150)))
                        .onTapGesture { toggle(1) }

                    Sector(start: .degrees(150), end: .degrees(270))
                        .fill(Color.clear)
                        .contentShape(Sector(start: .degrees(150), end: .degrees(270)))
                        .onTapGesture { toggle(2) }

                    Sector(start: .degrees(270), end: .degrees(390))
                        .fill(Color.clear)
                        .contentShape(Sector(start: .degrees(270), end: .degrees(390)))
                        .onTapGesture { toggle(3) }
                }
                .rotationEffect(.degrees(isServoRotateUp ? 180 : 0))  // ✅ rotate servo
                .animation(.spring(response: 0.30, dampingFraction: 0.9), value: isServoRotateUp)

                // ✅ Top-right rotate toggle (does NOT rotate)
                rotateToggleButton(size: size)
                    .position(x: center.x + radius * 0.72,
                              y: center.y - radius * 0.72)
            }
            .contentShape(Circle())
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.9), value: selected)
    }

    @ViewBuilder
    private func rotateToggleButton(size: CGFloat) -> some View {
        let d = max(22, size * 0.18)

        Circle()
            .fill(showRotateFlash ? accent.opacity(0.6) : Color(.systemGray5))
            .overlay(
                Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .overlay(
                Group {
                    let preferred = "arrow.trianglehead.clockwise"
                    let fallback  = "arrow.clockwise"

                    #if canImport(UIKit)
                    let name = (UIImage(systemName: preferred) != nil) ? preferred : fallback
                    Image(systemName: name)
                    #else
                    Image(systemName: fallback)
                    #endif
                }
                .font(.system(size: d * 0.45, weight: .semibold))
                .foregroundStyle(showRotateFlash ? Color.white : Color.secondary)
            )
            .frame(width: d, height: d)
            .animation(.easeInOut(duration: 0.1), value: showRotateFlash)
            .onTapGesture {
                // 1️⃣ Persisted logic
                isServoRotateUp.toggle()

                // 2️⃣ Trigger visual flash
                showRotateFlash = true

                // 3️⃣ Fade it back out after 1s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.20)) {
                        showRotateFlash = false
                    }
                }

                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            }
            .accessibilityLabel("Rotate servo")
            .accessibilityValue(isServoRotateUp ? "On" : "Off")
    }


    private func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
            print("ServoCircle: deselected \(id) — now selected: \(selected.sorted())")
        } else {
            selected.insert(id)
            print("ServoCircle: selected \(id) — now selected: \(selected.sorted())")
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

}


private struct Sector: Shape {
    var start: Angle
    var end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(center: center,
                    radius: radius,
                    startAngle: start,
                    endAngle: end,
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
