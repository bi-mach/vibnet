//
//  ModelCardHelpers.swift
//  Vibro
//
//  Created by lyubcsenko on 01/10/2025.
//

import SwiftUI
import Foundation
import Combine
import UIKit
import SceneKit
import CoreMotion

struct SpiralTextInCircle: View {
    let text: String
    let accent: Color
    let selected: Bool
    let startFontSize: CGFloat

    @State private var textOpacity: CGFloat
    @State private var textScale: CGFloat
    @State private var textBlur: CGFloat
    @State private var lastWasEmpty: Bool
    @State private var hasAppeared = false

    init(text: String, accent: Color, selected: Bool = false,
         startFontSize: CGFloat = UIScreen.main.bounds.width * 0.05) {
        self.text = text
        self.accent = accent
        self.selected = selected
        self.startFontSize = startFontSize

        // IMPORTANT: start hidden ALWAYS, then decide in onAppear/onChange
        _textOpacity = State(initialValue: 0)
        _textScale   = State(initialValue: 0.92)
        _textBlur    = State(initialValue: 6)
        _lastWasEmpty = State(initialValue: text.isEmpty)
    }
    
    let turns: CGFloat = 4
    var charSpacing: CGFloat {
        startFontSize / 1.8
    }
    var inset: CGFloat {
        startFontSize / 1.8
    }
    var minFontSize: CGFloat {
        startFontSize / 3
    }
    
    let fontDecreaseRate: CGFloat = 0.07
    
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            
            ZStack {
                Circle()
                    .fill(selected ? accent.opacity(0.16) : accent.opacity(0.12))
                    .overlay(
                        Circle().stroke(
                            selected ? accent.opacity(0.9) : accent.opacity(0.45),
                            lineWidth: 1.2
                        )
                    )
                
                
                
                
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width/2, y: canvasSize.height/2)
                    let maxR = min(canvasSize.width, canvasSize.height)/2 - inset
                    guard maxR > 0 else { return }
                    
                    let thetaMax: CGFloat = 2 * .pi * turns
                    let b: CGFloat = maxR / thetaMax
                    
                    // ✨ start 45° left of top
                    let startAngle: CGFloat = -(.pi/2) - (.pi/4)   // -3π/4
                    
                    var t: CGFloat = 0
                    let chars = Array(text)
                    var i = 0
                    
                    while t < thetaMax && i < chars.count {
                        let rMin: CGFloat = startFontSize * 0.5
                        let r  = max(rMin, maxR - b*t)
                        
                        let φ  = startAngle + t
                        let pt = CGPoint(x: center.x + r * cos(φ),
                                         y: center.y + r * sin(φ))
                        
                        // step so arc-length ≈ charSpacing
                        let dt  = charSpacing / max(hypot(b, r), 0.001)
                        let r2 = max(rMin, maxR - b * (t + dt))

                        let φ2  = startAngle + (t + dt)
                        let pt2 = CGPoint(x: center.x + r2 * cos(φ2),
                                          y: center.y + r2 * sin(φ2))
                        let tangent = CGPoint(x: pt2.x - pt.x, y: pt2.y - pt.y)
                        let angle = atan2(tangent.y, tangent.x)
                        
                        let decrementEvery = 2
                        
                        // Number of decrements applied so far (0, 1, 2, ...)
                        let decrements = CGFloat(i / decrementEvery)
                        
                        // Apply the stepwise decrease only every 3rd character
                        let fontSize = max(minFontSize, startFontSize - decrements * fontDecreaseRate)
                        let text = Text(String(chars[i]))
                            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        
                        let glyph: GraphicsContext.ResolvedText
                        if #available(iOS 17.0, *) {
                            glyph = context.resolve(text.foregroundStyle(Color.primary.opacity(0.95)))
                        } else {
                            glyph = context.resolve(text.foregroundColor(Color.primary.opacity(0.95)))
                        }
                        
                        context.translateBy(x: pt.x, y: pt.y)
                        context.rotate(by: .radians(Double(angle)))
                        context.draw(glyph, at: .zero, anchor: .center)
                        context.rotate(by: .radians(-Double(angle)))
                        context.translateBy(x: -pt.x, y: -pt.y)
                        
                        i += 1
                        t += dt
                    }
                }
                
                .opacity(textOpacity)
                .scaleEffect(textScale)
                .blur(radius: textBlur)
                .onAppear {
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    
                    // If we appear with non-empty text, animate in (next run loop)
                    if !text.isEmpty {
                        textOpacity = 0
                        textScale = 0.92
                        textBlur = 6
                        
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                textOpacity = 1
                                textScale = 1
                                textBlur = 0
                            }
                        }
                    }
                }
                .onChange(of: text) { newValue in
                    let isEmpty = newValue.isEmpty
                    
                    // empty -> non-empty
                    if lastWasEmpty && !isEmpty {
                        textOpacity = 0
                        textScale = 0.92
                        textBlur = 6
                        
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                textOpacity = 1
                                textScale = 1
                                textBlur = 0
                            }
                        }
                    }
                    
                    // non-empty -> empty (optional)
                    if !lastWasEmpty && isEmpty {
                        withAnimation(.easeOut(duration: 0.18)) {
                            textOpacity = 0
                            textScale = 0.98
                            textBlur = 4
                        }
                    }
                    
                    lastWasEmpty = isEmpty
                }
            }
            .frame(width: side, height: side)
        
        }
        .aspectRatio(1, contentMode: .fit)
    }

}

struct VerticalPager<Data: RandomAccessCollection, Content: View>: UIViewControllerRepresentable
where Data.Element: Identifiable {

    var data: Data
    // NEW: content builder includes an isActive binding
    var content: (Data.Element, Binding<Bool>) -> Content
    var cleanPreviousOnChange: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(data: data, content: content) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let c = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        c.dataSource = context.coordinator
        c.delegate   = context.coordinator

        context.coordinator.cleanPreviousOnChange = cleanPreviousOnChange

        if let first = context.coordinator.controller(at: 0) {
            c.setViewControllers([first], direction: .forward, animated: false)
            context.coordinator.currentIndex = 0
            context.coordinator.setActive(0, true)   // 🔑 start first page active
        }
        return c
    }

    static func dismantleUIViewController(_ pvc: UIPageViewController, coordinator: Coordinator) {
        pvc.dataSource = nil
        pvc.delegate   = nil
        if let shown = pvc.viewControllers?.first {
            DispatchQueue.main.async { [weak pvc] in pvc?.setViewControllers([shown], direction: .forward, animated: false) }
        }
        pvc.view.gestureRecognizers?.forEach {
            $0.isEnabled = false
            pvc.view.removeGestureRecognizer($0)
        }
        pvc.view.isUserInteractionEnabled = false
        coordinator.cache.removeAllObjects()
        coordinator.items.removeAll()
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let co = context.coordinator
        co.cleanPreviousOnChange = cleanPreviousOnChange
        co.update(data: data, content: content)

        // Always keep hooks attached (idempotent)
        if pvc.dataSource == nil { pvc.dataSource = co }
        if pvc.delegate   == nil { pvc.delegate   = co }

        if co.items.isEmpty {
            co.currentIndex = 0
            // Don't nil-out the dataSource; just return and wait for data
            return
        }

        // Ensure we have a current page shown
        if pvc.viewControllers?.isEmpty ?? true {
            if let first = co.controller(at: 0) {
                co.currentIndex = 0
                co.setActive(0, true)
                pvc.setViewControllers([first], direction: .forward, animated: false)
            }
            return
        }

        // Keep current index in range and update if needed
        let targetIndex = min(max(co.currentIndex, 0), co.items.count - 1)

        if let shown = pvc.viewControllers?.first,
           let shownIndex = co.index(of: shown),
           shownIndex == targetIndex {
            return
        }

        if let vc = co.controller(at: targetIndex) {
            let old = co.currentIndex
            co.currentIndex = targetIndex
            co.setActive(old, false)
            co.setActive(targetIndex, true)
            DispatchQueue.main.async { [weak pvc] in
                pvc?.setViewControllers([vc], direction: .forward, animated: false)
            }
        }
    }


    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        fileprivate var items: [Data.Element] = []
        private var makeContent: ((Data.Element, Binding<Bool>) -> Content)!
        let cache = NSCache<NSNumber, UIHostingController<Content>>() // index -> VC
        fileprivate var currentIndex: Int = 0
        var cleanPreviousOnChange: Bool = true
        
        private var pendingIndex: Int?

        private var flags: [Int: ActiveFlag] = [:]

        private func flag(for index: Int) -> ActiveFlag {
            if let f = flags[index] { return f }
            let f = ActiveFlag()
            flags[index] = f
            return f
        }
        // Provide a binding to the published value
        private func binding(for index: Int) -> Binding<Bool> {
            Binding(
                get: { self.flag(for: index).value },
                set: { self.flag(for: index).value = $0 }
            )
        }

        func setActive(_ index: Int, _ isActive: Bool) {
            // Ensure we're on main for UI updates
            if Thread.isMainThread {
                flag(for: index).value = isActive
            } else {
                DispatchQueue.main.async { self.flag(for: index).value = isActive }
            }
        }
        // 🔑 Active flags per index
        private var activeMap: [Int: Bool] = [:]

        init(data: Data, content: @escaping (Data.Element, Binding<Bool>) -> Content) {
            super.init()
            self.makeContent = content
            self.items = Array(data)
            cache.countLimit = 3
        }

        func update(data: Data, content: @escaping (Data.Element, Binding<Bool>) -> Content) {
            self.makeContent = content
            let newItems = Array(data)
            self.items = newItems

            // prune cache beyond ±1
            for key in cacheKeys() where abs(key.intValue - currentIndex) > 1 {
                cache.removeObject(forKey: key)
            }
        }



        func controller(at index: Int) -> UIHostingController<Content>? {
            guard items.indices.contains(index) else { return nil }
            if let vc = cache.object(forKey: NSNumber(value: index)) { return vc }

            // Ensure flag exists before building the view
            _ = flag(for: index)

            let view = makeContent(items[index], binding(for: index))
            let vc = UIHostingController(rootView: view)
            vc.view.tag = index
            cache.setObject(vc, forKey: NSNumber(value: index))
            return vc
        }

        func index(of vc: UIViewController) -> Int? {
            let tag = vc.view.tag
            return items.indices.contains(tag) ? tag : nil
        }

        private func cacheKeys() -> [NSNumber] {
            (0..<items.count).compactMap { i in cache.object(forKey: NSNumber(value: i)) != nil ? NSNumber(value: i) : nil }
        }

        // MARK: DataSource
        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let i = index(of: vc) else { return nil }
            return controller(at: i - 1)
        }
        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let i = index(of: vc) else { return nil }
            return controller(at: i + 1)
        }

        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            guard let pending = pendingViewControllers.first, let i = index(of: pending) else { return }
            pendingIndex = i
            // flip early so the pending page's .onAppear sees isActive == true
            if i != currentIndex {
                setActive(currentIndex, false)
                setActive(i, true)
            }
        }

        // FINALIZE or ROLLBACK after the animation
        func pageViewController(_ pvc: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            defer { pendingIndex = nil }

            guard finished else { return }

            if completed,
               let shown = pvc.viewControllers?.first,
               let newIndex = index(of: shown) {

                let oldIndex = currentIndex
                currentIndex = newIndex

                // We already pre-flipped, but make it idempotent:
                if oldIndex != newIndex {
                    setActive(oldIndex, false)
                    setActive(newIndex, true)
                }

                if cleanPreviousOnChange {
                    if items.indices.contains(oldIndex) {
                        cache.removeObject(forKey: NSNumber(value: oldIndex))
                    }
                    DispatchQueue.main.async { [weak pvc] in
                        guard let pvc = pvc, pvc.viewControllers?.first === shown else { return }
                        pvc.setViewControllers([shown], direction: .forward, animated: false)
                    }
                }

                for key in cacheKeys() where abs(key.intValue - currentIndex) > 1 {
                    cache.removeObject(forKey: key)
                }
            } else {
                // Swipe cancelled → rollback the early flip
                if let pending = pendingIndex {
                    setActive(pending, false)
                    setActive(currentIndex, true)
                }
            }
        }
    }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightKey.self, perform: onChange)
    }
}


extension View {
    func topSheet<Content: View>(
        isPresented: Binding<Bool>,
        bottomInset: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.overlay(alignment: .top) {
            if isPresented.wrappedValue {
                TopSheetInternal(
                    isPresented: isPresented,
                    bottomInset: bottomInset,
                    content: content
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}

private struct TopSheetInternal<Content: View>: View {
    @Binding var isPresented: Bool
    let bottomInset: CGFloat
    @GestureState private var dragY: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height - bottomInset

            VStack(spacing: 0) {
                Capsule()
                    .frame(width: 36, height: 5)
                    .opacity(0.35)
                    .padding(.vertical, 8)

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: geo.size.width, height: height)
            .background(.regularMaterial)
            .offset(y: dragY)
            .gesture(
                DragGesture().updating($dragY) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height < -120 {
                        // swipe up to close
                        withAnimation { isPresented = false }
                    }
                }
            )
            .ignoresSafeArea(edges: .top)
        }
    }
}


struct GameButtonWithDropUp: View {
    @Binding var isOpen: Bool
    var accent: Color
    var onHand: () -> Void
    var onMusic: () -> Void
    
    private var H: CGFloat { UIScreen.main.bounds.height } // real device height
    
    var body: some View {
        // The button itself (fixed-size, proportional to screen height)
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isOpen.toggle()
            }
        } label: {
            Image(systemName: "gamecontroller.fill")
                .resizable()
                .scaledToFit()
                .frame(width: H * 0.035, height: H * 0.035)   // ≈ 3% of screen height
                .foregroundStyle(isOpen ? Color.secondary : accent)
                .padding(H * 0.01)                          // ≈ 1% of screen height
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(isOpen ? Color.secondary : accent, lineWidth: H * 0.001))
        }
        .accessibilityLabel("Game Menu")
        .frame(width: H * 0.045, height: H * 0.045)         // ≈ 4.5% of screen height
        .contentShape(Rectangle())
        
        // Drop-up menu
        .overlay(alignment: .top) {
            if isOpen {
                VStack(spacing: H * 0.01) {
                    Divider().opacity(0)
                    
                    HStack(spacing: H * 0.012) {
                        // Hand → replaced with gesture symbol
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isOpen = false
                            }
                            onHand()
                        } label: {
                            Image("gesture_gesture_symbol") // <- your SVG asset name
                                .resizable()
                                .scaledToFit()
                                .frame(width: H * 0.025, height: H * 0.025)
                                .padding(H * 0.012)
                                .font(.system(.title3, weight: .bold))  // Bold weight
                                .tint(accent)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: H * 0.001))
                        }
                        .accessibilityLabel("Gesture")

                    }
                    .padding(H * 0.012)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: H * 0.018, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: H * 0.018, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: H * 0.001)
                    )
                    .shadow(radius: H * 0.015, y: H * 0.01)
                }
                .offset(y: -H * 0.1)                         // place higher above button (10% of height)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1000)
                .allowsHitTesting(true)
            }
        }
        .zIndex(1000)
    }
}

struct WaveAnimationView: View {
    let waveCenters: [CGPoint]
    let waveValues: [Int]
    let frameSize: CGSize
    var duration: Double = 1.0          // each blup lasts 1s
    var interval: Double = 0.08163265   // spacing between blups
    var trigger: Int = 0                // bump to restart
    var onCompleted: (() -> Void)? = nil
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var animating: Set<Int> = []

    private func color(for index: Int) -> Color {
        switch waveValues[index] {
        case 2: return Color.red.opacity(0.3)
        case 1: return Color.yellow.opacity(0.3)
        default: return Color.blue.opacity(0.3)
        }
    }
    private func center(for index: Int) -> CGPoint {
        guard !waveCenters.isEmpty else { return .zero }
        return waveCenters[index % waveCenters.count]
    }

    var body: some View {
        let count = waveValues.count
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let isOn = animating.contains(index)
                Circle()
                    .fill(selectedAccent.color)
                    .frame(
                        width: isOn ? frameSize.width * 0.3 : 0,
                        height: isOn ? frameSize.width * 0.3 : 0
                    )
                    .position(center(for: index))
                    .opacity(isOn ? 0 : 1)
            }
        }
        .onAppear { animateAll(count: waveValues.count) }
        .onChange(of: trigger) { _ in animateAll(count: waveValues.count) }
        .onChange(of: waveValues.count) { newCount in animateAll(count: newCount) }
    }

    private func animateAll(count: Int) {
        animating.removeAll()
        guard count > 0 else { return }

        // total sequence time = duration + (count-1)*interval
        let totalTime = duration + interval * Double(max(0, count - 1))

        for index in 0..<count {
            let delay = interval * Double(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: duration)) {
                    animating.insert(index)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration) {
                    animating.remove(index)
                }
            }
        }

        // fire completion once, at the end
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            onCompleted?()
        }
    }
}

struct MiniDissolvingLinesWithWave: View {
    @State private var trigger = UUID() // will refresh MiniFirstDissolvingLine
    @Environment(\.dismiss) private var dismiss
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MiniFirstDissolvingLine(accent: accent) { }
                    .id(trigger)
                    .rotationEffect(.degrees(90)) // ✅ rotate 90°

            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                // Repeat every 3 seconds
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    trigger = UUID() // forces MiniFirstDissolvingLine to restart
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}


struct DissolvingLinesWithWave: View {
    @State private var showSecond = false
    @State private var showWave1 = false
    @State private var showWave2 = false
    @State private var showSoon = false
    @State private var waveTrigger1 = 0
    @State private var waveTrigger2 = 0
    @Environment(\.dismiss) private var dismiss    // ← add this
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // --- Content that can have padding ---
                ZStack {
                    if showSecond {
                        SecondDissolvingLine {
                            showWave1 = true
                            waveTrigger1 += 1
                        }
                        .transition(.opacity)
                    } else {
                        FirstDissolvingLine {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSecond = true
                            }
                        }
                    }
                    
                    if showWave1 {
                        WaveAnimationView(
                            waveCenters: Array(repeating: CGPoint(x: geo.size.width * 0.3,
                                                                  y: geo.size.height * 0.3), count: 25),
                            waveValues: Array(repeating: 0, count: 25),
                            frameSize: geo.size,
                            duration: 1.0,
                            interval: 0.025,
                            trigger: waveTrigger1
                        ) {
                            showWave1 = false
                            showWave2 = true
                            waveTrigger2 += 1
                        }
                        .transition(.opacity)
                    }
                    
                    if showWave2 {
                        WaveAnimationView(
                            waveCenters: Array(repeating: CGPoint(x: geo.size.width * 0.6,
                                                                  y: geo.size.height * 0.6), count: 25),
                            waveValues: Array(repeating: 0, count: 25),
                            frameSize: geo.size,
                            duration: 1.0,
                            interval: 0.025,
                            trigger: waveTrigger2
                        ) {
                            showWave2 = false
                            withAnimation(.easeIn(duration: 0.5)) {
                                showSoon = true
                            }
                        }
                        .transition(.opacity)
                    }
                }
                
                // --- Full-frame centered overlay, unaffected by padding ---
                if showSoon {
                    VStack(spacing: 16) {
                        Text("soon".localized())
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Button(action: { dismiss() }) {
                            Text("close".localized())
                                .font(.system(size: 32, weight: .bold))  // 2× smaller than 64
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    .transition(.opacity)
                    .zIndex(100)
                }
            
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.container, edges: .top)

    }
}



// MARK: - Second line (left-top → right-bottom dissolving)
struct SecondDissolvingLine: View {
    var onFinished: () -> Void
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var progress: CGFloat = 0
    @State private var visibleFraction: CGFloat = 1.0
    @State private var fadeOut: CGFloat = 0

    private let totalDuration: Double = 2.0
    private let disappearDelay: Double = 1.0
    private let disappearDuration: Double = 1.0

    private var tailStart: CGFloat { max(0, progress - visibleFraction) }
    private var smoothOpacity: Double { Double(progress * (1 - fadeOut)) }
    private var smoothBlur: CGFloat { (1 - progress + fadeOut) * 6 }

    var body: some View {
        LineLTtoRB()
            .trim(from: tailStart, to: progress)
            .stroke(selectedAccent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .blur(radius: smoothBlur)
            .opacity(smoothOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: totalDuration)) { progress = 1 }
                // start dissolving halfway through
                DispatchQueue.main.asyncAfter(deadline: .now() + disappearDelay) {
                    withAnimation(.easeInOut(duration: disappearDuration)) {
                        visibleFraction = 0
                        fadeOut = 1
                    }
                }
                // call onFinished exactly when the dissolve completes
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                    onFinished()
                }
            }
    }
}

// MARK: - Paths
struct LineLTtoRB: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.05, y: h * 0.05)) // left-top
        p.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.95),     // right-bottom
            control1: CGPoint(x: w * 0.35, y: h * 0.2),
            control2: CGPoint(x: w * 0.65, y: h * 0.8)
        )
        return p
    }
}
struct FirstDissolvingLine: View {
    var onFinished: () -> Void
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var progress: CGFloat = 0          // head (0→1)
    @State private var visibleFraction: CGFloat = 1.0 // trailing length
    @State private var fadeOut: CGFloat = 0           // 0→1 during dissolve

    // timings
    private let totalDuration: Double = 2.0
    private let disappearDelay: Double = 1.0
    private let disappearDuration: Double = 1.0

    private var tailStart: CGFloat { max(0, progress - visibleFraction) }
    private var smoothOpacity: Double { Double(progress * (1 - fadeOut)) }
    private var smoothBlur: CGFloat { (1 - progress + fadeOut) * 6 }

    var body: some View {
        LineTRtoBL()
            .trim(from: tailStart, to: progress)
            .stroke(selectedAccent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .blur(radius: smoothBlur)
            .opacity(smoothOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: totalDuration)) { progress = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + disappearDelay) {
                    withAnimation(.easeInOut(duration: disappearDuration)) {
                        visibleFraction = 0
                        fadeOut = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                    onFinished()
                }
            }
    }
}

struct MiniFirstDissolvingLine: View {
    let accent: Color
    var onFinished: () -> Void
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var progress: CGFloat = 0          // head (0→1)
    @State private var visibleFraction: CGFloat = 1.0 // trailing length
    @State private var fadeOut: CGFloat = 0           // 0→1 during dissolve

    // timings
    private let totalDuration: Double = 2.0
    private let disappearDelay: Double = 1.0
    private let disappearDuration: Double = 1.0

    private var tailStart: CGFloat { max(0, progress - visibleFraction) }
    private var smoothOpacity: Double { Double(progress * (1 - fadeOut)) }
    private var smoothBlur: CGFloat { (1 - progress + fadeOut) * 6 }

    var body: some View {
        MiniLineTRtoBL()
            .trim(from: tailStart, to: progress)
            .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .blur(radius: smoothBlur)
            .opacity(smoothOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: totalDuration)) { progress = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + disappearDelay) {
                    withAnimation(.easeInOut(duration: disappearDuration)) {
                        visibleFraction = 0
                        fadeOut = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                    onFinished()
                }
            }
    }
}

struct MiniLineTRtoBL: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.95)) // start bottom center
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.05),     // end top center
            control1: CGPoint(x: w * 0.8, y: h * 0.7), // rightward bow
            control2: CGPoint(x: w * 0.2, y: h * 0.3)  // leftward near top
        )
        return p
    }
}


struct LineTRtoBL: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.95, y: h * 0.05))
        p.addCurve(
            to: CGPoint(x: w * 0.05, y: h * 0.95),
            control1: CGPoint(x: w * 0.65, y: h * 0.2),
            control2: CGPoint(x: w * 0.35, y: h * 0.8)
        )
        return p
    }
}



struct SpiralTextEditor: View {
    @Binding var text: String
    @Binding var showEditor: Bool
    let accent: Color
    
    var turns: CGFloat = 4


    var startFontSize: CGFloat = UIScreen.main.bounds.width * 0.05

    
    var charSpacing: CGFloat {
        startFontSize / 1.8
    }
    var inset: CGFloat {
        startFontSize / 1.8
    }
    var minFontSize: CGFloat {
        startFontSize / 3
    }

    let fontDecreaseRate: CGFloat = 0.07

    var placeholder: String = ""

    @FocusState private var focused: Bool
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            ZStack {
                // Circle chrome
                Circle()
                    .fill(Color(.systemGray6))

                // Accent blurred glow
                Circle()
                    .fill(accent.opacity(0.16))

                // Accent stroke
                Circle()
                    .stroke(accent.opacity(0.9), lineWidth: 1.2)

                // Animated canvas so the caret blinks
                TimelineView(.animation) { _ in
                    Canvas { context, size in
                        let center = CGPoint(x: size.width/2, y: size.height/2)
                        let maxR = min(size.width, size.height)/2 - inset
                        guard maxR > 0 else { return }

                        let thetaMax: CGFloat = 2 * .pi * turns
                        let b: CGFloat = maxR / thetaMax

                        // 👇 start 45° left of top
                        let startAngle: CGFloat = -(.pi/2) - (.pi/4)   // -3π/4

                        let chars = Array(text.isEmpty ? placeholder : text)
                        let drawingRealText = !text.isEmpty

                        var t: CGFloat = 0
                        var i = 0

                        // caret defaults at the new start position
                        var caretPoint = CGPoint(
                            x: center.x + maxR * cos(startAngle),
                            y: center.y + maxR * sin(startAngle)
                        )
                        var caretAngle: CGFloat = 0
                        var caretFont: CGFloat = startFontSize

                        while t < thetaMax {
                            let r  = maxR - b * t
                            let φ  = startAngle + t                    // 👈 use offset
                            let pt = CGPoint(x: center.x + r * cos(φ),
                                             y: center.y + r * sin(φ))
                            
                            // step so arc-length ≈ charSpacing
                            let dt: CGFloat = charSpacing / max(hypot(b, r), 0.001)
                            let r2  = maxR - b * (t + dt)
                            let φ2  = startAngle + (t + dt)           // 👈 use offset
                            let pt2 = CGPoint(x: center.x + r2 * cos(φ2),
                                              y: center.y + r2 * sin(φ2))
                            let tangent = CGPoint(x: pt2.x - pt.x, y: pt2.y - pt.y)
                            let angle = atan2(tangent.y, tangent.x)
                            
                            if i < chars.count {
                                let decrementEvery = 2

                                // Number of decrements applied so far (0, 1, 2, ...)
                                let decrements = CGFloat(i / decrementEvery)

                                // Apply the stepwise decrease only every 3rd character
                                let fontSize = max(minFontSize, startFontSize - decrements * fontDecreaseRate)
                                
                                let baseText = Text(String(chars[i]))
                                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))

                                let color = (drawingRealText ? Color.primary : Color.secondary).opacity(0.95)

                                let glyph: GraphicsContext.ResolvedText
                                if #available(iOS 17.0, *) {
                                    glyph = context.resolve(baseText.foregroundStyle(color))
                                } else {
                                    glyph = context.resolve(baseText.foregroundColor(color))
                                }

                                context.translateBy(x: pt.x, y: pt.y)
                                context.rotate(by: .radians(Double(angle)))
                                context.draw(glyph, at: .zero, anchor: .center)
                                context.rotate(by: .radians(-Double(angle)))
                                context.translateBy(x: -pt.x, y: -pt.y)
                                
                                i += 1
                                t += dt
                            } else {
                                // caret after last char
                                caretPoint = pt
                                caretAngle = angle
                                caretFont  = max(minFontSize, startFontSize - CGFloat(i) * fontDecreaseRate)
                                break
                            }
                        }

                        // Draw caret (blink)
                        if drawingRealText {
                            let blink = (Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1.0)) < 0.5
                            if blink {
                                var caretPath = Path(CGRect(x: -1, y: -caretFont * 0.6, width: 2, height: caretFont * 1.2))
                                context.translateBy(x: caretPoint.x, y: caretPoint.y)
                                context.rotate(by: .radians(Double(caretAngle)))
                                context.fill(caretPath, with: .color(accent.opacity(0.9)))
                                context.rotate(by: .radians(-Double(caretAngle)))
                                context.translateBy(x: -caretPoint.x, y: -caretPoint.y)
                            }
                        }
                    }
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)   // <— key; iOS 16+
                    .focused($focused)
                    .opacity(0.02)
                    .foregroundColor(.clear)        // ✅ hides text completely
                    .tint(.clear)
                    .background(Color.clear)
                    .clipShape(Circle())
                    .padding(inset)                // match canvas padding
            }
            .frame(width: side, height: side)
            .contentShape(Circle())               // tap anywhere in the circle
            .onTapGesture {
                showEditor = true      // let parent know editor is up
                focused = true         // open keyboard
            }
            .onChange(of: showEditor) { newValue in
                focused = newValue     // keep in sync with binding
            }
            .onChange(of: focused) { isFocused in
                if !isFocused {
                    // keyboard was dismissed by user swipe / return
                    showEditor = false
                }
            }

        }
        .aspectRatio(1, contentMode: .fit)
    }
}
