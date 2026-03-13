import SwiftUI
import FirebaseStorage
import FirebaseAuth
import CoreHaptics
import AVFoundation
import UIKit

private final class ShakeHostingController: UIViewController {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        onShake?()
    }
}

private struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = ShakeHostingController()
        vc.onShake = onShake
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? ShakeHostingController)?.onShake = onShake
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeDetector(onShake: action))
    }
}

// MARK: - Small, fast-to-type-check ring view
struct BorderRing: View {
    let progress: CGFloat
    let show: Bool
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat
    let id: UUID
    
    var body: some View {
        Circle()                                   // Shape
            .trim(from: progress, to: 1)           // Shape-only
            .stroke(color, lineWidth: lineWidth)   // becomes View
            .rotationEffect(Angle.degrees(-90))
            .scaleEffect(x: -1, y: 1)
            .opacity(show ? 1 : 0)
            .frame(width: size, height: size)
            .id(id)                                // View modifier LAST
    }
}

import QuartzCore

@MainActor
final class ProMotionTicker: NSObject, ObservableObject {
    var onTick: ((CGFloat) -> Void)?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    /// The fps we asked for (60 on most devices, 120 on ProMotion devices that allow it)
    private(set) var targetFPS: Int = 60

    func start() {
        guard link == nil else { return }

        lastTimestamp = nil

        // Device capability (this is what you printed)
        let maxFPS = UIScreen.main.maximumFramesPerSecond
        targetFPS = maxFPS

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))

        if #available(iOS 15.0, *) {
            // Ask up to what the device supports
            let max = Float(maxFPS)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: max, preferred: max)
        } else {
            link.preferredFramesPerSecond = maxFPS
        }

        link.add(to: .main, forMode: .common)
        self.link = link

        print("ProMotionTicker targetFPS:", targetFPS)
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = link.timestamp
        let rawDt = (lastTimestamp == nil) ? (1.0 / Double(targetFPS)) : (t - lastTimestamp!)
        lastTimestamp = t

        var dt = CGFloat(rawDt)
        // clamp protects you from hitches/backgrounding
        dt = min(max(dt, 1.0/240.0), 1.0/20.0)

        onTick?(dt)
    }
}

struct AtomicRingWave: View {
    let selectedAccent: Color
    @Binding var animateBlob: Bool
    let hasSingleTapped: Bool
    private let vertexCount = 512
    @State private var accelRampTime: CGFloat = 0   // seconds since accel started
    @State private var lastMotorTier: Haptics.AmpTier = .m2   // default fallback if you want
    @StateObject private var ticker = ProMotionTicker()


    private struct Vertex {
        var radius: CGFloat
        var velocity: CGFloat
        
        // Extra channel for "pressure wave" that rides on top
        var pressure: CGFloat
        var pressureVelocity: CGFloat
    }
    
    @State private var decelRampTime: CGFloat = 0   // seconds since decel started

    @State private var rotSign: CGFloat = 1.0   // +1 right … -1 left (smoothed)
    @State private var lastIsDelay: Bool = false
    @State private var delayLatchUntil: CFTimeInterval = 0

    @State private var lastAmplitude: CGFloat = 0
    @State private var lastCanvasSize: CGSize = .zero
    @State private var vertices: [Vertex] = []
    @State private var didSetup = false
    @State private var opacity: CGFloat = 1.0
    // NEW: second blob state
    @State private var secondaryVertices: [Vertex] = []
    @State private var secondaryAmplitude: CGFloat = 0
    @State private var secondaryOpacity: CGFloat = 0
    @State private var secondaryFrameToggle: Bool = false   // NEW



    
    @State private var rotation: CGFloat = 0   // radians

    @State private var currentRPM: CGFloat = 30
    
    @State private var prevRPM: CGFloat = 0
    

    private let minRPM: CGFloat = 30
    private let rpmStep: CGFloat = 20
    private let maxRPM_M1: CGFloat = 1796.5
    private let maxRPM_M2: CGFloat = 1796.5
    private let maxRPM_M3: CGFloat = 1796.5
    private let rpmRate_M3: CGFloat = 160
    private let rpmRate_M2: CGFloat = 120
    private let rpmRate_M1: CGFloat = 80
    private let rpmRate_None: CGFloat = 6
    
    private func accelRateForTier() -> CGFloat {
        switch Haptics.shared.ampTier {
        case .m3:  return rpmRate_M3
        case .m2:  return rpmRate_M2
        case .m1:  return rpmRate_M1
        case .none:return rpmRate_None
        }
    }
    
    private func decelRateForTier() -> CGFloat {
        // tweak these if you want slower/faster decay per tier
        switch Haptics.shared.ampTier {
        case .m3:  return 160
        case .m2:  return 120
        case .m1:  return 80
        case .none:return 40
        }
    }
    private func decelRate(for tier: Haptics.AmpTier) -> CGFloat {
        switch tier {
        case .m3:  return 160
        case .m2:  return 120
        case .m1:  return 80
        case .none:return 40
        }
    }

    @State private var delayRPMCeiling: CGFloat = .greatestFiniteMagnitude

    @State private var didTouchTL = false
    @State private var didTouchTR = false
    @State private var didTouchBL = false
    @State private var didTouchBR = false
    private func accelRampFactor(t: CGFloat) -> CGFloat {
        // starts at 0.2 and smoothly approaches 1.0
        // tweak tau to control how fast it ramps (bigger = slower)
        let tau: CGFloat = 1.6
        let x = 1 - exp(-t / tau)          // 0 -> 1
        return 0.2 + 0.8 * x               // 0.2 -> 1.0
    }
    private func accelMultiplierForTier() -> CGFloat {
        switch Haptics.shared.ampTier {
        case .m3:   return 1.0
        case .m2:   return 0.65
        case .m1:   return 0.35
        case .none: return 1.0
        }
    }
    
    @State private var isCoasting = false
    @State private var coastAmp: CGFloat = 0          // 0…1 envelope used during coast
    @State private var lastAnimateBlob = false


    private func detectCornerTouches(containerSize: CGSize) {
        guard vertices.count == vertexCount else { return }

        let w = containerSize.width
        let h = containerSize.height
        let center = CGPoint(x: w * 0.5, y: h * 0.5)

        let angleStep = (2 * .pi) / CGFloat(vertexCount)

        let eps: CGFloat = 100

        var touchTL = false
        var touchTR = false
        var touchBL = false
        var touchBR = false

        let cr = cos(rotation)
        let sr = sin(rotation)

        for i in 0..<vertexCount {
            let v = vertices[i]
            let u = unitCircle[i]

            let dx = u.x * cr - u.y * sr
            let dy = u.x * sr + u.y * cr

            let p = CGPoint(
                x: center.x + dx * v.radius,
                y: center.y + dy * v.radius
                )


            if p.x <= eps && p.y <= eps { touchTL = true }
            if p.x >= w - eps && p.y <= eps { touchTR = true }
            if p.x <= eps && p.y >= h - eps { touchBL = true }
            if p.x >= w - eps && p.y >= h - eps { touchBR = true }

            if touchTL && touchTR && touchBL && touchBR { break }
        }

        // Print on "rising edge" (only when it *becomes* true)
        if touchTL && !didTouchTL { print("Touched TOP-LEFT"); didTouchTL = true }
        if touchTR && !didTouchTR { print("Touched TOP-RIGHT"); didTouchTR = true }
        if touchBL && !didTouchBL { print("Touched BOTTOM-LEFT"); didTouchBL = true }
        if touchBR && !didTouchBR { print("Touched BOTTOM-RIGHT")
            print("Hit wall @ RPM: \(Int(currentRPM.rounded()))")
            ; didTouchBR = true }

        // Reset when it leaves, so it can print again on the next hit
        if !touchTL { didTouchTL = false }
        if !touchTR { didTouchTR = false }
        if !touchBL { didTouchBL = false }
        if !touchBR { didTouchBR = false }
    }

    private func dynamicMaxRPM(rawAmp: CGFloat) -> CGFloat {
        // rawAmp 0...10 -> a 0...1
        var a = min(max(rawAmp / 10.0, 0), 1)

        switch Haptics.shared.ampTier {
        case .m3:
            a = min(1.0, a * 1.5 + 0.15)
            
        case .m2:
            a = min(1.0, a * 1.25 + 0.08)
            
        case .m1:
            // ✅ boost small amplitudes a bit
            a = min(1.0, a * 1.00 + 0.02)   // tweak 1.25 and 0.08

        case .none:
            a = min(a, 0.15)
        }

        let loudnessCeiling = minRPM + (maxRPM_M2 - minRPM) * a

        switch Haptics.shared.ampTier {
        case .m3:  return min(loudnessCeiling, maxRPM_M3)
        case .m2:  return min(loudnessCeiling, maxRPM_M2)
        case .m1:  return min(loudnessCeiling, maxRPM_M1)
        case .none:return min(loudnessCeiling, minRPM + 20)
        }
    }


    @State private var accelAccum: CGFloat = 0   // seconds accumulated for +10
    @State private var decelAccum: CGFloat = 0   // seconds accumulated for -10
    
    private var angularVelocity: CGFloat {       // radians/sec
        (2 * .pi) * (currentRPM / 60.0)
    }

    @State private var accelTickAccum: CGFloat = 0

    private let accelTickInterval_M1: CGFloat = 0.2
    private let accelTickInterval_M2: CGFloat = 0.5
    private let accelTickInterval_M3: CGFloat = 1.0
    private let accelTickInterval_None: CGFloat = 0.25

    private func accelTickIntervalForTier() -> CGFloat {
        switch Haptics.shared.ampTier {
        case .m1:  return accelTickInterval_M1
        case .m2:  return accelTickInterval_M2
        case .m3:  return accelTickInterval_M3
        case .none:return accelTickInterval_None
        }
    }

    private let unitCircle: [CGPoint] = {
        let n = 512
        let step = (2 * CGFloat.pi) / CGFloat(n)
        return (0..<n).map { i in
            let a = step * CGFloat(i)
            return CGPoint(x: cos(a), y: sin(a))
        }
    }()


    var body: some View {
        GeometryReader { geo in
            Canvas { context, canvasSize in
                guard vertices.count == vertexCount, opacity > 0 else { return }
                if lastCanvasSize != canvasSize {
                    lastCanvasSize = canvasSize
                }

                let center = CGPoint(x: canvasSize.width / 2,
                                     y: canvasSize.height / 2)
                
                let angleStep = (2 * .pi) / CGFloat(vertexCount)
                var points = Array(repeating: CGPoint.zero, count: vertexCount)

                let cr = cos(rotation)
                let sr = sin(rotation)

                for i in 0..<vertexCount {
                    let v = vertices[i]
                    let u = unitCircle[i]

                    let dx = u.x * cr - u.y * sr
                    let dy = u.x * sr + u.y * cr

                    points[i] = CGPoint(
                        x: center.x + dx * v.radius,
                        y: center.y + dy * v.radius
                    )
                }

                guard points.count > 2 else { return }

                var basePath = Path()

                func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
                }

                let firstMid = mid(points[0], points[1])
                basePath.move(to: firstMid)

                for i in 1..<points.count {
                    let p = points[i]
                    let next = points[(i + 1) % points.count]
                    let m = mid(p, next)
                    basePath.addQuadCurve(to: m, control: p)
                }
                basePath.closeSubpath()

                context.fill(
                    basePath,
                    with: .color(selectedAccent.opacity(0.9 * opacity))
                )

                // ✅ Darken strictly on the blob, Canvas-correct
                if hasSingleTapped {
                    var dimContext = context           // 👈 copy context
                    dimContext.opacity = 0.25
                    dimContext.blendMode = .multiply   // optional, remove if undesired
                    dimContext.fill(basePath, with: .color(.black))
                }

            }
            .ignoresSafeArea()
            .onChange(of: animateBlob) { newValue in
                // keep your onTick assignment if needed
                ticker.onTick = { dt in
                    stepPhysics(dt: dt, containerSize: lastCanvasSize == .zero ? geo.size : lastCanvasSize)
                }

                if lastAnimateBlob == true && newValue == false {
                    // TRUE -> FALSE : start coasting from the *current* amp
                    isCoasting = true
                    coastAmp = min(max(Haptics.shared.amp / 10.0, 0), 1)  // 0…1
                }

                if newValue == true {
                    // if user re-engages, exit coast immediately
                    isCoasting = false
                }

                lastAnimateBlob = newValue
            }

            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                setupVertices()

                ticker.onTick = { dt in
                    stepPhysics(dt: dt, containerSize: lastCanvasSize == .zero ? geo.size : lastCanvasSize)
                }

                ticker.start()
            }
            .onDisappear {     resetBlobState() }


            
        }
    }
    

    private func resetBlobState() {
        // Stop drawing / simulation
        ticker.stop()

        // Clear geometry/state
        vertices.removeAll()
        secondaryVertices.removeAll()

        // Reset motion + bookkeeping
        rotation = 0
        currentRPM = minRPM
        prevRPM = 0

        lastAmplitude = 0
        accelRampTime = 0
        decelRampTime = 0
        accelAccum = 0
        decelAccum = 0
        accelTickAccum = 0

        // IMPORTANT: allow setup again next time
        didSetup = false

        // Optional: clear latches
        didTouchTL = false
        didTouchTR = false
        didTouchBL = false
        didTouchBR = false
    }

    
    private func simulateBlob(
        vertices vIn: inout [Vertex],
        amp: CGFloat,
        ampDropFactor: CGFloat = 0,
        containerSize: CGSize,
        rotation: CGFloat,
        maxRadiusOverride: ((Int, CGFloat) -> CGFloat)? = nil
    ) -> (hitWall: Bool, snapped: Bool) {
        guard !vIn.isEmpty else { return (false, false) }

        var newVertices = vIn
        let angleStep = (2 * .pi) / CGFloat(vertexCount)
        let minSide = min(containerSize.width, containerSize.height)
        let baseRadius: CGFloat = minSide * 0.1
        let wallRadii: [CGFloat]? = nil


        
        let relaxing = amp < 0.001
        let uniformScale: CGFloat = min(containerSize.width, containerSize.height) * 0.5


        
        // ----------------------------------
        // Base constants
        // ----------------------------------
        let dampingBase: CGFloat = 0.99
        let spread: CGFloat = 0.08

        let wallRestitutionBase: CGFloat = 0.15
        let pushStrengthBase: CGFloat = 0.05
        let springStrengthBase: CGFloat = 0.0065
        let calmExtraDampingBase: CGFloat = 0.93
        let maxSpeedFactorBase: CGFloat = 0.1

        let pressureDampingBase: CGFloat = 0.92
        let pressureSpread: CGFloat = 0.5
        let pressureImpactScaleBase: CGFloat = 0.003
        let globalImpactScaleBase: CGFloat = 0.003

        // ----------------------------------
        // Reactivity to loudness + drops
        // ----------------------------------

        // Map amp (0–1) to loudness
        let ampClamped = min(max(amp, 0), 1)

        // ampDropFactor is 0–1, already normalized in stepPhysics
        let dropClamped = min(max(ampDropFactor, 0), 1)

        // Outward reactivity (loud)
        let loudReactivity = 1.0 + 3.0 * ampClamped   // 1.0 → 4.0

        // Inward “collapse” reactivity when amplitude FALLS
        let collapseReactivity = 1.0 + 4.0 * dropClamped   // 1.0 → 5.0 on big drop

        // Derived parameters
        let damping = dampingBase
            - 0.10 * ampClamped   // less damping when loud
            - 0.08 * dropClamped

        let calmExtraDamping = calmExtraDampingBase
            + 0.005 * (1 - ampClamped) // calmer when quiet & stable

        let wallRestitution = wallRestitutionBase
            + 0.35 * ampClamped       // bouncy when loud
            + 0.20 * dropClamped      // extra kick when amplitude collapses

        let pushStrength = pushStrengthBase * (loudReactivity * 2.2)
        // outward push from loud segments

        // Stronger spring when amplitude is dropping: blob snaps inward
        let springStrength = springStrengthBase * collapseReactivity

        let maxSpeedFactor = maxSpeedFactorBase
            * (1.0 + 3.5 * ampClamped + 2.0 * dropClamped)

        let pressureDamping = pressureDampingBase
            - 0.05 * ampClamped       // ripples last longer when loud
            - 0.04 * dropClamped      // and on sharp drops

        let pressureImpactScale = pressureImpactScaleBase
            * (loudReactivity * 2.0 + collapseReactivity * 1.5)

        let globalImpactScale = globalImpactScaleBase
            * (loudReactivity * 2.0 + collapseReactivity * 1.5)

        // pressure pulses spread dramatically more when loud


        let cr = cos(rotation)
        let sr = sin(rotation)
        var hitAnyWall = false
        for i in newVertices.indices {
            var v = newVertices[i]

            let u = unitCircle[i]


            let dx = u.x * cr - u.y * sr
            let dy = u.x * sr + u.y * cr

            let localMaxRadius = maxRadius(dx: dx, dy: dy, in: containerSize)



            let outwardGate = 1.0 - 0.95 * dropClamped   // almost off on big drops
            if amp > 0.001 {
                v.velocity += amp * pushStrength * outwardGate
            } else {
                let offsetFromBase = v.radius - baseRadius
                v.velocity += -offsetFromBase * springStrength
            }


            // EXTRA: when amplitude just dropped, add an inward “collapse” kick
            if ampDropFactor > 0.01 {
                let collapseImpulse: CGFloat = baseRadius * 0.04 * ampDropFactor
                v.velocity -= collapseImpulse
            }


            let maxSpeed = localMaxRadius * maxSpeedFactor   // keep energy


            v.velocity = max(-maxSpeed, min(maxSpeed, v.velocity))

            v.radius += v.velocity

            if v.radius > localMaxRadius {
                v.radius = localMaxRadius

                if v.velocity > 0 {
                    v.velocity = -v.velocity * wallRestitution
                    hitAnyWall = true

                    let impactR = relaxing ? uniformScale : localMaxRadius
                    v.pressureVelocity -= impactR * pressureImpactScale

                }
            }

            if v.radius < 0 {
                v.radius = 0
                v.velocity = 0
            }

            v.velocity *= damping

            if amp < 0.001 {
                v.velocity *= calmExtraDamping
            }

            v.pressureVelocity *= pressureDamping
            v.pressure += v.pressureVelocity

            newVertices[i] = v
        }

        if hitAnyWall {
            for i in newVertices.indices {

                // If you have an override, keep using it (it expects an angle)
                if let override = maxRadiusOverride {
                    let angle = angleStep * CGFloat(i) // NOTE: unrotated like before
                    let localMaxRadius = override(i, angle)
                    let impactR = relaxing ? uniformScale : localMaxRadius
                    newVertices[i].pressureVelocity -= impactR * globalImpactScale
                    continue
                }

                if let wallRadii {
                    let localMaxRadius = wallRadii[i]
                    let impactR = relaxing ? uniformScale : localMaxRadius
                    newVertices[i].pressureVelocity -= impactR * globalImpactScale
                    continue
                }

                // New fast path: direction vector instead of angle
                let u = unitCircle[i]                 // (cos(baseAngle), sin(baseAngle))
                let dx = u.x * cr - u.y * sr
                let dy = u.x * sr + u.y * cr
                let localMaxRadius = maxRadius(dx: dx, dy: dy, in: containerSize)

                let impactR = relaxing ? uniformScale : localMaxRadius
                newVertices[i].pressureVelocity -= impactR * globalImpactScale
            }
        }

        
        // 2) Neighbor coupling for radius
        var tempVertices = newVertices
        for i in newVertices.indices {
            let leftIndex  = (i - 1 + vertexCount) % vertexCount
            let rightIndex = (i + 1) % vertexCount
            
            let centerR = newVertices[i].radius
            let leftR   = newVertices[leftIndex].radius
            let rightR  = newVertices[rightIndex].radius
            
            let delta = (leftR + rightR - 2 * centerR)
            tempVertices[i].velocity += delta * spread
        }
        
        // 3) Neighbor coupling for pressure
        var pressureVertices = tempVertices
        for i in tempVertices.indices {
            let leftIndex  = (i - 1 + vertexCount) % vertexCount
            let rightIndex = (i + 1) % vertexCount
            
            let centerP = tempVertices[i].pressure
            let leftP   = tempVertices[leftIndex].pressure
            let rightP  = tempVertices[rightIndex].pressure
            
            let deltaP = (leftP + rightP - 2 * centerP)
            pressureVertices[i].pressureVelocity += deltaP * pressureSpread
        }
        
        // 4) Extra smoothing on radius
        let smoothFactor: CGFloat = 0.7
        var smoothedVertices = pressureVertices
        for i in pressureVertices.indices {
            let leftIndex  = (i - 1 + vertexCount) % vertexCount
            let rightIndex = (i + 1) % vertexCount
            
            let r0 = pressureVertices[i].radius
            let rL = pressureVertices[leftIndex].radius
            let rR = pressureVertices[rightIndex].radius
            
            let neighborAvg = (rL + r0 + rR) / 3
            smoothedVertices[i].radius =
                r0 * (1 - smoothFactor) + neighborAvg * smoothFactor
        }
        
        vIn = smoothedVertices




        // Only main (white) blob should snap to rest
        let snapped: Bool
        if maxRadiusOverride == nil {
            snapped = snapToRestIfCalm(containerSize: containerSize,
                                       vertices: &vIn,
                                       amp: amp)
        } else {
            snapped = false
        }

        return (hitAnyWall, snapped)
    }

    private func snapToRestIfCalm(containerSize: CGSize,
                                  vertices v: inout [Vertex],
                                  amp: CGFloat) -> Bool {
        guard amp < 0.001, !v.isEmpty else { return false }

        
        let minSide = min(containerSize.width, containerSize.height)
        let baseRadius: CGFloat = minSide * 0.1
        
        var totalRadiusDeviation: CGFloat = 0
        var totalSpeed: CGFloat = 0
        var totalPressureMagnitude: CGFloat = 0
        
        for vert in v {
            totalRadiusDeviation += abs(vert.radius - baseRadius)
            totalSpeed += abs(vert.velocity)
            totalPressureMagnitude += abs(vert.pressure) + abs(vert.pressureVelocity)
        }
        
        let n = CGFloat(v.count)
        let avgRadiusDeviation = totalRadiusDeviation / n
        let avgSpeed = totalSpeed / n
        let avgPressure = totalPressureMagnitude / n
        
        // Tweak these thresholds to taste
        let radiusThreshold: CGFloat = 0.5
        let speedThreshold: CGFloat = 0.01
        let pressureThreshold: CGFloat = 0.01
        
        // If everything is super calm and close to the "rest" circle,
        // snap to a perfectly clean state so the next expansion
        guard avgRadiusDeviation < radiusThreshold,
              avgSpeed < speedThreshold,
              avgPressure < pressureThreshold else {
            return false
        }

        for i in v.indices {
            v[i].radius = baseRadius
            v[i].velocity = 0
            v[i].pressure = 0
            v[i].pressureVelocity = 0
        }
        accelTickAccum = 0
        accelRampTime = 0


        return true
    }

    // MARK: - Setup
    
    private func setupVertices() {
        vertices = (0..<vertexCount).map { _ in
            Vertex(
                radius: 0,               // start at centre; spring will pull to float radius
                velocity: 0,
                pressure: 0,             // no initial pressure
                pressureVelocity: 0
            )
        }
    }
    
    private func maxRadius(dx: CGFloat, dy: CGFloat, in size: CGSize) -> CGFloat {
        let cx = size.width * 0.5
        let cy = size.height * 0.5

        let eps: CGFloat = 1e-6
        var tMin = CGFloat.greatestFiniteMagnitude

        if abs(dx) > eps {
            if dx > 0 { tMin = min(tMin, (size.width - cx) / dx) }
            else      { tMin = min(tMin, (0 - cx) / dx) }
        }
        if abs(dy) > eps {
            if dy > 0 { tMin = min(tMin, (size.height - cy) / dy) }
            else      { tMin = min(tMin, (0 - cy) / dy) }
        }

        if tMin == .greatestFiniteMagnitude { return 0 }
        return max(0, tMin)
    }



    private func stepPhysics(dt: CGFloat, containerSize: CGSize) {

        // If we're neither animating nor coasting, just gently relax and do nothing else.
        if !animateBlob && !isCoasting {
            let _ = simulateBlob(
                vertices: &vertices,
                amp: 0,
                ampDropFactor: 0,
                containerSize: containerSize,
                rotation: rotation
            )
            return
        }

        // --- Determine amplitude source (0...1) ---
        // When animateBlob is true: use real haptics amp.
        // When coasting: exponentially decay the envelope to 0.
        let amp01: CGFloat = {
            if animateBlob {
                // Haptics amp is 0...10 -> normalize to 0...1
                return min(max(Haptics.shared.amp / 10.0, 0), 1)
            } else {
                // Coast decay (tweak tau for feel)
                let tau: CGFloat = 0.25  // seconds; bigger = longer coast
                let k = exp(-dt / tau)
                coastAmp *= k
                return coastAmp
            }
        }()

        // Convert back to 0...10 for your existing RPM/tiers logic with minimal changes
        let rawAmp10 = amp01 * 10.0

        // If coast has basically finished, stop coasting.
        if isCoasting && amp01 < 0.001 && currentRPM <= minRPM + 0.5 {
            isCoasting = false
        }

        // --- Change tracking (uses 0...10 scale, as before) ---
        let ampChange = rawAmp10 - lastAmplitude
        let ampDrop = max(-ampChange, 0)
        let ampDropFactor = min(ampDrop / 3.0, 1.0) // 0...1
        lastAmplitude = rawAmp10

        // --- RPM logic ---
        // With normalized amp01, pick your "continuous" threshold on 0...1
        let isContinuous = amp01 > 0.02
        let isDecreasing = ampDropFactor > 0.01
        let isDelay = Haptics.shared.isDelay
        let rpmFloor: CGFloat = isDelay ? 0.0 : minRPM

        if !Haptics.shared.isDelay && Haptics.shared.ampTier != .none {
            lastMotorTier = Haptics.shared.ampTier
        }

        let shouldDecelerate =
            (isDecreasing) || (!isContinuous && currentRPM > rpmFloor + 0.01)

        // frameMaxRPM should be based on 0...10 amplitude input, like your original
        let frameMaxRPM = dynamicMaxRPM(rawAmp: rawAmp10)

        if isDelay {
            // Delay mode owns RPM: only decelerate to 0 using last motor tier
            let delayDecelRate: CGFloat = decelRate(for: lastMotorTier)
            currentRPM = max(0.0, currentRPM - delayDecelRate * dt)

            // keep bookkeeping stable
            accelAccum = 0
            decelAccum = 0
            accelRampTime = 0
        } else {
            // Normal mode (your existing logic)
            if isContinuous && !isDecreasing {
                decelAccum = 0
                accelRampTime += dt

                let baseRate = accelRateForTier()
                let ramp = accelRampFactor(t: accelRampTime)
                let tierMul = accelMultiplierForTier()
                let effectiveRate = baseRate * ramp * tierMul

                currentRPM = min(frameMaxRPM, currentRPM + effectiveRate * dt)
            } else {
                decelAccum += dt
                accelAccum = 0
                accelRampTime = 0

                let decelInterval = max(0.12, 0.5 - 0.38 * ampDropFactor)
                if decelAccum >= decelInterval {
                    let effectiveStep = rpmStep * (1.0 + 3.0 * ampDropFactor)
                    currentRPM = max(rpmFloor, currentRPM - effectiveStep)
                    decelAccum -= decelInterval
                }
            }
        }

        // rotation flip: if delay, always rotate left; else depends on decel state
        let targetSign: CGFloat = isDelay ? -1.0 : (shouldDecelerate ? -1.0 : 1.0)
        let flipResponse: CGFloat = 10.0
        let alpha = 1 - exp(-flipResponse * dt)
        rotSign += (targetSign - rotSign) * alpha

        let dTheta = angularVelocity * dt * rotSign
        rotation += dTheta
        rotation = rotation.truncatingRemainder(dividingBy: 2 * .pi)
        if rotation < 0 { rotation += 2 * .pi }

        // ✅ Use normalized amp01 for blob simulation
        // ✅ When delay is active, do NOT feed ampDropFactor into blob physics
        let blobAmpDropFactor: CGFloat = (isDelay ? 0 : ampDropFactor)

        // Lazy init vertices if we’re animating or coasting
        if vertices.isEmpty {
            if amp01 > 0.001 || isCoasting {
                setupVertices()
            } else {
                return
            }
        }

        let _ = simulateBlob(
            vertices: &vertices,
            amp: amp01,
            ampDropFactor: blobAmpDropFactor,
            containerSize: containerSize,
            rotation: rotation
        )

        detectCornerTouches(containerSize: containerSize)

        // --- Optional: settle/cleanup logic (kept from your original intent, but fixed scaling) ---
        let minSide = min(containerSize.width, containerSize.height)
        let baseRadius: CGFloat = minSide * 0.1

        var totalRadius: CGFloat = 0
        for v in vertices { totalRadius += v.radius }
        let avgRadius = totalRadius / CGFloat(vertices.count)

        let deviationFraction = abs(avgRadius - baseRadius) / baseRadius
        let whiteIsWithin10PercentOfRest = deviationFraction < 0.10

        // rawAmp10 is 0...10, so compare against a 0...10 threshold
        if whiteIsWithin10PercentOfRest && rawAmp10 < 0.2 {
            currentRPM = isDelay ? 0.0 : minRPM
            accelAccum = 0
            decelAccum = 0
        }
    }


}

struct OutsideCircleMask: Shape {
    var center: CGPoint
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Full screen rect
        path.addRect(rect)

        // Cut-out circle
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )

        return path
    }
}


struct PlayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sharedData: SharedData
    @EnvironmentObject var tapsFunctions: TapsFunctions
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @Binding var UsersTaps: [Int: String]
    @ObservedObject var model: Model
    let TapData: [Int: [Int: [TapEntry]]]
    let isPreviewingModel: Bool
    let accent: Color
    @State private var TapCircleSize: CGFloat = 0.0
    @State private var selectedImage: UIImage? = nil
    @State private var timer: Timer?
    @State private var pressStartTime: Date?
    @State private var pressDuration: Double = 0.0
    @State private var countdownText: String? = nil
    @State private var countdownTimer: Timer? = nil
    @State private var countdownRemaining: Double = 1.00
    @State private var pressDurations: [(Int, Double)] = []
    @State private var showLoading: Bool = false
    @State private var userEmail: String = ""
    
    @State private var previewInSeconds: Double = 0.0
    @State private var previewSeconds: Double = 0.0
    @State private var isPlayingPreview = false
    @State private var playbackTimer: Timer? = nil
    @State private var playbackIsPlayed: Bool = false
    @State private var currentPlayers: [CHHapticAdvancedPatternPlayer] = []
    @State private var playbackTapEntries: [Double: [Int: [TapEntry]]] = [:]
    @State private var bucketDurations: [Double: Double] = [:]
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    
    @State private var orderedKeys: [Double] = []
    @State private var nextBucketIndex = 0
    private let epsilon: Double = 0.0005
    private var tapImageData: Data? {
        selectedImage?.jpegData(compressionQuality: 1.0)
    }
    @State private var runID = UUID()
    @State private var pendingDelay: DispatchWorkItem? = nil
    
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("lastUsedEntries") private var lastUsedEntriesData: Data = Data()
    @State private var didSetImage: Bool = false
    
    @State private var shakeKey: Int = 0

    
    @State private var playbackTask: Task<Void, Never>? = nil
    @State private var rowPlayGen: UInt64 = 0

    private func bumpRowGen() { rowPlayGen &+= 1 }

    
    @State private var showBorder = false
    @State private var eraseProgress: CGFloat = 0
    @State private var borderAnimID = UUID() // <- optional but helpful
    @State private var currentImageLoadToken = UUID()
    @State private var hasTapped: Bool = false
    @State private var hapticWatchdogs: [UUID: DispatchWorkItem] = [:]
    @AppStorage("useMicrophone") private var useMicrophoneSystem: Bool = false
    @State private var clearPressWork: DispatchWorkItem? = nil
    private let clearDelay: TimeInterval = 0.5
    
    
    
    @State private var useMicrophone: Bool = false
    private let ticker = Timer
        .publish(every: 0.01, on: .main, in: .common)
        .autoconnect()
    
    /// Run a completion even if a haptic player never calls back (e.g. phone call, notification).
    private func armWatchdog(id: UUID, after seconds: Double, _ fire: @escaping () -> Void) {
        let w = DispatchWorkItem { fire() }
        hapticWatchdogs[id]?.cancel()
        hapticWatchdogs[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, seconds), execute: w)
    }
    @State private var notifTokens: [NSObjectProtocol] = []
    
    @State private var heldBlobAmp: CGFloat = 0   // 0...1 visual/physics amp hold
    
    
    private func disarmWatchdog(id: UUID) {
        hapticWatchdogs[id]?.cancel()
        hapticWatchdogs[id] = nil
    }
    
    private func tapImageReference(for user: User) -> StorageReference {
        let ownerId = user.email ?? user.uid
        return Storage.storage().reference()
            .child("Users")
            .child(ownerId)
            .child("TapImage.jpg") // use .jpg if you cache JPEGs
    }
    
    private func loadUserImage() {
        // 0) restore email if available
        if let savedUserEmail = UserDefaults.standard.string(forKey: "GoogleUserEmail") {
            userEmail = savedUserEmail
        }
        
        // 1) token
        let token = UUID()
        currentImageLoadToken = token
        
        // 2) try DISK CACHE first (synchronous)
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            let ref = tapImageReference(for: user)          // ensure this matches upload path!
            let id  = ref.fullPath
            if let cached = ImageDiskCache.shared.load(identifier: id) {
                // Found in cache → show immediately; no fallback flash
                selectedImage = cached            // tip: skip animation to avoid flicker
                return
            }
        }
        
        // 3) no cache → set fallback, then fetch network
        let fallbackName = (selectedAppearance.colorScheme == .dark) ? (useMicrophone ? "TAP_notxt_w" :  "TAP_wb") : (useMicrophone ? "TAP_notxt_b" : "TAP_bw")
        selectedImage = UIImage(named: fallbackName)
        
        fetchUserTapImage { img in
            DispatchQueue.main.async {
                guard self.currentImageLoadToken == token else { return }
                if let img {
                    withAnimation(.easeInOut(duration: 0.2)) { self.selectedImage = img }
                } else {
                    if sharedData.listOfFavModels.contains(model.name) &&
                        !sharedData.personalModelsData.contains(where: { $0.name == model.name }) {
                        saveLastUsedEntry(for: model, listOfFavModels: sharedData.listOfFavModels)
                    }
                }
            }
        }
    }
    
    @StateObject private var speechListener = BackgroundSpeechListener(
        appLocale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    )
    @AppStorage("NoHands") private var NoHands: Bool = false
    @State private var alertMessage: String = ""
    @State private var isRequesting: Bool = false
    @State private var showAlert: Bool = false
    @State private var isPressing = false
    @State private var isHoldingOutsideRing = false
    @State private var beganInsideCircle = false
    @State private var endedInsideCircle = false
    @State private var isHoldingInsideCircle = false
    @State private var startOfTapping = false

    @State private var hasSingleTapped = false
    @State private var tapPlaybackTask: Task<Void, Never>? = nil
    
    private final class HapticOwner {}
    @State private var hOwner = HapticOwner()
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radiusS: CGFloat = UIScreen.main.bounds.width * 0.2
            let radius: CGFloat = UIScreen.main.bounds.width * 0.1
            
            let overlayBackgroundColor: Color = {
                if selectedAppearance == .system {
                    return systemColorScheme == .dark ? .black : .white
                } else {
                    return selectedAppearance == .dark ? .black : .white
                }
            }()
            
            ZStack {
                // Background
                overlayBackgroundColor
                    .ignoresSafeArea()
                
                
                
                // Main content (ring + interactions)
                ZStack {
                    AtomicRingWave(selectedAccent: accent, animateBlob: $isHoldingOutsideRing, hasSingleTapped: hasSingleTapped)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    
                    Color.clear
                        .frame(width: radiusS, height: radiusS)
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
              
                                    if !Haptics.shared.startOfTappingG || !isHoldingOutsideRing{
                                        hasSingleTapped = true
                                    }
                                }
                                .onEnded { _ in
           
                                    handleTap()

                                    if !startOfTapping {
                                        interruptAndStopAll(hideRing: true)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        startOfTapping = true
                                        if !Haptics.shared.startOfTappingG {
                                            Haptics.shared.startOfTappingG = true
                                        }
                                    }
                                    hasSingleTapped = false
                                }
                        )

                
                }
                .modifier(ShakeEffect(shakes: CGFloat(shakeKey)))
                .animation(.linear(duration: 0.4), value: shakeKey)
                
                // Gesture
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if pressStartTime == nil {
                                pressStartTime = Date()
                                
                                let dx = value.location.x - center.x
                                let dy = value.location.y - center.y
                                let distance = sqrt(dx * dx + dy * dy)
                                beganInsideCircle = distance <= radius
                            }
                            
                            isPressing = true
                            

                            
                            let dx = value.location.x - center.x
                            let dy = value.location.y - center.y
                            let distance = sqrt(dx * dx + dy * dy)
                            
                            if NoHands {
                                isHoldingOutsideRing = true
                            } else {
                                isHoldingOutsideRing = distance > radius
                            }
                        }
                        .onEnded { value in
                            isPressing = false
                            
                        
                        
                            if !NoHands {
                                isHoldingOutsideRing = false
                            }
                            let dx = value.location.x - center.x
                            let dy = value.location.y - center.y
                            let distance = sqrt(dx * dx + dy * dy)
                            endedInsideCircle = distance <= radius
                            
                            if let start = pressStartTime, beganInsideCircle && endedInsideCircle {
                                pressDuration = Date().timeIntervalSince(start) * 1000
                                pressDurations.append((1, pressDuration))
                            }
                            
                            pressStartTime = nil
                            beganInsideCircle = false
                            endedInsideCircle = false
                        }
                )
                
                
                VStack {
                    HStack {
                        Spacer()
                        
                        Button {
                            guard isRequesting == false else {
                                useMicrophone = false
                                return
                            }
                            
                            isRequesting = true
                            Task {
                                let outcome = await VoicePermissionRequester.requestAll()
                                switch outcome {
                                case .allGranted:
                                    useMicrophone = true
                                case .micDenied:
                                    useMicrophone = false
                                    alertMessage = "mic_rec_perm_required".localized()
                                    showAlert = true
                                case .speechDenied:
                                    useMicrophone = false
                                    alertMessage = "speech_rec_perm_required".localized()
                                    showAlert = true
                                case .error(let msg):
                                    useMicrophone = false
                                    alertMessage = msg.isEmpty
                                    ? "could_request_voice_permission".localized()
                                    : msg
                                    showAlert = true
                                }
                                isRequesting = false
                            }
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                        // show only when mic is allowed to be enabled
                        .opacity(
                            (!useMicrophone && useMicrophoneSystem && UsersTaps.isEmpty) ? 1.0 : 0.0
                        )
                        .allowsHitTesting(
                            !useMicrophone && useMicrophoneSystem && UsersTaps.isEmpty
                        )
                        
                    }
                    
                    Spacer()
                }
                .alert("permission_required".localized(), isPresented: $showAlert) {
                    Button("ok".localized(), role: .cancel) { }
                } message: {
                    Text(alertMessage)
                }
            }
            .ignoresSafeArea()
        }
        .onReceive(ticker) { now in
            DispatchQueue.main.async {
                tick(now: now)
            }
        }
        .onChange(of: Haptics.shared.startOfTappingG) {newval in
            print("HOLD OUTSIDE : \(newval)")
        }
        
        .onAppear {
            HapticsManager.shared.activate(for: hOwner) 
            isHoldingOutsideRing = false
            Haptics.shared.resetAmpImmediately()
            Task {
                let favouriteIDs = Set(sharedData.publishedFavModels.values.map(\.id))
                guard favouriteIDs.contains(model.id) else { return }
                
                let joinedString = sharedData.publishedFavModels.values.map(\.name).joined(separator: ", ")
                print("aaa")
                do {
                    try await forumFunctionality.sendModelActivityAsync(
                        forumTag: model.name,
                        text: joinedString
                    )
                    print("aaa")
                } catch {
                    print("Failed to log activity: \(error.localizedDescription)")
                }
            }
        
            
            
            let willResign = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                interruptAndStopAll(hideRing: true)
            }
            notifTokens.append(willResign)
            
            let didBecome = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main
            ) { _ in
                Haptics.shared.ensureEngineRunning()
            }
            notifTokens.append(didBecome)
            
            let audioInterruption = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { note in
                guard
                    let info = note.userInfo,
                    let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeVal)
                else { return }
                
                switch type {
                case .began:
                    interruptAndStopAll(hideRing: true)
                case .ended:
                    Haptics.shared.ensureEngineRunning()
                @unknown default:
                    break
                }
            }
            notifTokens.append(audioInterruption)
            Haptics.shared.isDelay = false
            // Engine hooks: don’t capture the view; just call statics.
            Haptics.shared.onEngineStopped = { _ in
                // Post your own notification or just stop immediately:
                NotificationCenter.default.post(name: Notification.Name("HapticsEngineStopped"), object: nil)
            }
            Haptics.shared.onEngineReset = {
                Haptics.shared.ensureEngineRunning()
            }
            
            // Optionally listen to our own "engine stopped" post:
            let engineStoppedToken = NotificationCenter.default.addObserver(
                forName: Notification.Name("HapticsEngineStopped"),
                object: nil, queue: .main
            ) { _ in
                interruptAndStopAll(hideRing: true)
            }
            notifTokens.append(engineStoppedToken)
            
        }
        .onDisappear {
            HapticsManager.shared.deactivate(for: hOwner)
            isHoldingOutsideRing = false
            Haptics.shared.resetMotorExpectationNow()
            Haptics.shared.resetAmpImmediately()
            Haptics.shared.isDelay = false
            interruptAndStopAll(hideRing: true)
            Haptics.shared.hardStopEngine()
            for t in notifTokens { NotificationCenter.default.removeObserver(t) }
            notifTokens.removeAll()
            // Clear engine hooks to avoid retaining closures longer than needed
            Haptics.shared.onEngineStopped = nil
            Haptics.shared.onEngineReset = nil
            
            print("C1")
            if useMicrophone {
                print("C2")
                speechListener.stop()
            }
        }
        .onChange(of: useMicrophone) { valueIn in
            if valueIn {
                speechListener.onCommand = { n in
                    DispatchQueue.main.async {
                        print("n: \(n)")
                        if pressStartTime == nil { pressStartTime = Date() }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if let start = pressStartTime {
                                pressDuration = Date().timeIntervalSince(start) * 1000
                                
                                // ⬇️ Add `n` entries (1 or 2) into pressDurations
                                for _ in 0..<n {
                                    pressDurations.append((1, pressDuration))
                                }
                                
                                pressStartTime = nil
                            }
                            
                            
                            handleTap()
                            if let data = TapData[pressDurations.count], !data.isEmpty {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                }
                
                
                
                if useMicrophone {
                    if VoiceAuth.isAuthorized() {
                        do {
                            try speechListener.start(resetFailures: true)
                            
                            print("[Speech] Listener started.")
                            
                        } catch {
                            print("[Speech] Failed to start: \(error.localizedDescription)")
                        }
                    } else {
                        // Don’t prompt here: just log and remain idle as requested.
                        print("[Speech] Not authorized (mic/speech). Not starting.")
                    }
                }
            }
        }
        .onShake {
            HapticsManager.shared.cancelAll()
            Haptics.shared.startOfTappingG = false
            Haptics.shared.isDelay = false
            Haptics.shared.resetMotorExpectationNow()
            interruptAndStopAll(hideRing: true)
            Haptics.shared.resetAmpImmediately()
            Haptics.shared.hardStopEngine()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            shakeKey += 1
        }
        
        
        
    }
    
    private func interruptAndStopAll(hideRing: Bool = true) {

        // 1) Kill timers
        countdownTimer?.invalidate()
        playbackTimer?.invalidate()
        countdownTimer = nil
        playbackTimer = nil
        
        // 2) Cancel pending work
        pendingDelay?.cancel()
        pendingDelay = nil
        
        clearPressWork?.cancel()
        clearPressWork = nil
        
        // 3) Cancel watchdogs
        hapticWatchdogs.values.forEach { $0.cancel() }
        hapticWatchdogs.removeAll()
        
        // 4) Cancel any async playback task
        tapPlaybackTask?.cancel()
        tapPlaybackTask = nil
        
        // 5) Reset local playback flags
        playbackIsPlayed = false
        runID = UUID()
        
        if hideRing {
            withAnimation(.easeOut(duration: 0.15)) {
                showBorder = false
                eraseProgress = 1
            }
        }
        
        // ✅ Collection #2 way: kill in-flight haptics via manager
        HapticsManager.shared.cancelAll()
        
        // If you keep this UI flag, maintain it
        Haptics.shared.isDelay = false
    }
    
    

    private func seek(to time: Double) {
        pausePlayback()
        previewSeconds = min(max(0, time), previewInSeconds)
        ensureOrderedKeys()
        nextBucketIndex = nextIndexFor(time: previewSeconds)
    }

    private func playHapticBatchSimultaneous(_ entries: [TapEntry]) {
        
        if playbackIsPlayed { stopCurrentHapticsImmediately() }

        let nonDelay = entries.filter { $0.entryType != "delay" && $0.value > 0 }
        guard !nonDelay.isEmpty else {
            
            if let delay = entries.first(where: { $0.entryType == "delay" && $0.value > 0 }) {
                playHapticSequence(for: [delay], startAt: 0, forceRestart: true)
            }
            return
        }

        playbackIsPlayed = true
        currentPlayers.removeAll()

        let group = DispatchGroup()
        for e in nonDelay {
            let power = (e.entryType == "m2") ? "large" : "medium"
            group.enter()


        }

        group.notify(queue: .main) {
            self.stopCurrentHapticsImmediately()
        }
    }

    func playHapticSequence(for entries: [TapEntry], startAt index: Int = 0, forceRestart: Bool = false) {
        if playbackIsPlayed {
            guard forceRestart else { return }
            stopCurrentHapticsImmediately()
        }
        playbackIsPlayed = true

        func runStep(at idx: Int) {
            guard idx < entries.count else {
                playbackIsPlayed = false
                return
            }
            guard playbackIsPlayed else {
                stopCurrentHapticsImmediately()
                return
            }

            let e = entries[idx]
            let next = { runStep(at: idx + 1) }

            switch e.entryType {
            case "m1", "m2":
                guard e.value > 0 else { next(); return }
                let power = (e.entryType == "m2") ? "large" : "medium"



            case "delay":
                let delay = max(0, e.value)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    next()
                }

            default:
                next()
            }
        }

        runStep(at: index)
    }
    
    private func startPlayback() {
        if previewSeconds >= previewInSeconds { previewSeconds = 0 }
        resetBucketSchedule()
        ensureOrderedKeys()
        nextBucketIndex = nextIndexFor(time: previewSeconds)
        
        isPlayingPreview = true
        playbackTimer?.invalidate()
        
        
        fireDueBucketsOnce(at: previewSeconds)
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05 / playbackSpeed, repeats: true) { [self] timer in
            if previewSeconds < previewInSeconds {
                previewSeconds += 0.05 * playbackSpeed
                fireDueBucketsOnce(at: previewSeconds)
            } else {
                timer.invalidate()
                isPlayingPreview = false
                stopCurrentHapticsImmediately()
            }
        }
    

    }
    
    private func fireDueBucketsOnce(at time: Double) {
        while nextBucketIndex < orderedKeys.count,
              orderedKeys[nextBucketIndex] <= time + epsilon {

            let t = orderedKeys[nextBucketIndex]

            if let perList = playbackTapEntries[t] {
                
                for listIndex in perList.keys.sorted() {
                    let entries = perList[listIndex] ?? []
                    guard !entries.isEmpty else { continue }

                    let nonDelayCount = entries.filter { $0.entryType != "delay" && $0.value > 0 }.count
                    if nonDelayCount > 1 {
                        
                        playHapticBatchSimultaneous(entries)
                    } else {
                        
                        playHapticSequence(for: entries, startAt: 0, forceRestart: true)
                    }
                }
            }

            nextBucketIndex += 1
        }
    }

    private func pausePlayback() {
        isPlayingPreview = false
        playbackTimer?.invalidate()
        stopCurrentHapticsImmediately()
    }


    private func buildTapPlayback(from entries: [TapEntry]) {
        // stable ordering
        let entries = entries.sorted { $0.key < $1.key }

        playbackTapEntries = [:]
        bucketDurations = [:]
        orderedKeys = []
        nextBucketIndex = 0

        var cursor: Double = 0
        var total: Double = 0
        let listIndex = 0

        func snap(_ t: Double) -> Double { (t * 1000).rounded() / 1000 } // 1ms snap

        func append(at start: Double, entries: [TapEntry]) {
            var perList = playbackTapEntries[start] ?? [:]
            var arr = perList[listIndex] ?? []
            arr.append(contentsOf: entries)
            perList[listIndex] = arr
            playbackTapEntries[start] = perList

            let d = bucketDuration(for: entries)
            bucketDurations[start] = max(bucketDurations[start] ?? 0, d)
        }

        // groupId != 0 = bucketed groups
        let groups = Dictionary(grouping: entries, by: \.groupId)

        let orderedGIDs = groups.keys.filter { $0 != 0 }.sorted()
        for gid in orderedGIDs {
            let grouped = (groups[gid] ?? []).sorted { $0.key < $1.key }
            let d = bucketDuration(for: grouped)
            let start = snap(cursor)
            append(at: start, entries: grouped)
            cursor = snap(cursor + d)
            total += d
        }

        // singles (groupId == 0) in sequence
        if var singles = groups[0] {
            singles.sort { $0.key < $1.key }
            for e in singles where e.value > 0 {
                let start = snap(cursor)
                append(at: start, entries: [e])
                cursor = snap(cursor + e.value)
                total += e.value
            }
        }

        previewInSeconds = total
        previewSeconds = 0
        orderedKeys = playbackTapEntries.keys.sorted()
    }

    private func startTapPlayback() {
        let token = rowPlayGen

        HapticsManager.shared.prewarm()

        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, token == rowPlayGen, previewSeconds < previewInSeconds {
                try? await Task.sleep(nanoseconds: 50_000_000)
                previewSeconds += 0.05
                fireDueBucketsOnce(at: previewSeconds, token: token)
            }
            HapticsManager.shared.softStop()
        }

        // fire t=0 immediately
        fireDueBucketsOnce(at: 0, token: token)
    }

    private func fireDueBucketsOnce(at time: Double, token: UInt64) {
        guard token == rowPlayGen else { return }
        let epsilon = 1e-6

        while nextBucketIndex < orderedKeys.count,
              orderedKeys[nextBucketIndex] <= time + epsilon {

            let t = orderedKeys[nextBucketIndex]
            if let perList = playbackTapEntries[t] {
                for listIndex in perList.keys.sorted() {
                    let entries = perList[listIndex] ?? []
                    guard !entries.isEmpty else { continue }

                    let nonDelayCount = entries.filter {
                        $0.entryType.lowercased() != "delay" && $0.value > 0
                    }.count

                    if nonDelayCount > 1 {
                        HapticsManager.shared.playBatch(for: hOwner, entries)   // parallel
                    } else {
                        HapticsManager.shared.playSequence(for: hOwner, entries) // serial
                    }
                }
            }

            nextBucketIndex += 1
        }
    }

    private func fireMotorsForCurrentTapCombo() {
        // run your activation
        resetTapCountAfterInterval()

        clearPressWork?.cancel()
        let work = DispatchWorkItem {

            startOfTapping = false
            self.pressDurations.removeAll()
        }
        clearPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay, execute: work)
    }

    


    private func resetTapCountAfterInterval() {
        let mappedString: String
        guard let secondaryKeys = TapData[pressDurations.count] else {
            interruptAndStopAll(hideRing: true)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            shakeKey += 1
            return
        }
        let flattenedEntries = secondaryKeys.values.flatMap { $0 }
        let containsRelevantEntry = flattenedEntries.contains { entry in
            (entry.entryType == "m1" || entry.entryType == "m2" || entry.entryType == "m3" || entry.entryType == "servo") && entry.value != 0.0
        }
        if containsRelevantEntry {
            if secondaryKeys.keys.contains(0) {
                let tapData = "\(pressDurations.count)"
                if let largestKey = UsersTaps.keys.max() {
                    let newKey = largestKey + 1
                    UsersTaps[newKey] = tapData
                } else {
                    UsersTaps[1] = tapData
                }
                let duration = totalDuration(for: tapData, in: TapData)
                startErase(duration: duration)
                processTaps(TapData, tapData: tapData)
            } else {
                
                if pressDurations.allSatisfy({ $0.1 > 100 }) {
                    mappedString = "l" 
                } else {
                    mappedString = "s" 
                }
                let combinedString = "\(pressDurations.count)\(mappedString)"
                if let largestKey = UsersTaps.keys.max() {
                    let newKey = largestKey + 1
                    UsersTaps[newKey] = combinedString
                } else {
                    UsersTaps[1] = combinedString
                }
                let duration = totalDuration(for: combinedString, in: TapData)
                startErase(duration: duration)

                processTaps(TapData, tapData: combinedString)
                 
            }
        } else {
            shakeKey += 1
            interruptAndStopAll(hideRing: true)
            return
        }
    }
    
    
    
}


struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 6      // smaller horizontal movement
    var shakes: CGFloat = 0

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // faster oscillations (×2 compared to your original)
        let translation = amount * sin(shakes * .pi * 10)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}



 final class Haptics {
     static let shared = Haptics()
     private var engine: CHHapticEngine?
     private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

     var onEngineStopped: ((CHHapticEngine.StoppedReason) -> Void)?
     var onEngineReset: (() -> Void)?

     // MARK: - Public amp (0...10)
     // Always read/write on main queue.
     private(set) var amp: CGFloat = 0
     var isDelay: Bool = false // but only touch it on main


     func setIsDelay(_ v: Bool) {
         DispatchQueue.main.async {
             self.isDelay = v
         }
     }
     // MARK: - Amp internals
     private var ampTarget: CGFloat = 0
     private var ampAnimFrom: CGFloat = 0
     private var ampAnimStart: CFTimeInterval = 0
     private var ampAnimDur: CFTimeInterval = 0.5
     private var ampLink: CADisplayLink?

     private var hold3Until: TimeInterval = 0
     private var hold5Until: TimeInterval = 0
     private var hold10Until: TimeInterval = 0
     private let eps: TimeInterval = 1e-6
     
     private let ampRiseDur: CFTimeInterval = 1.0   // <- reach target in 1s
     private let ampFallDur: CFTimeInterval = 1.0  // <- optional: quicker release


     private enum AmpEasing { case easeInOut, easeOut, easeIn, linear }
     private var ampMode: AmpEasing = .easeInOut

     
     // MARK: - Amp helpers

     private func ensureAmpLink() {
         if ampLink == nil {
             ampLink = CADisplayLink(target: self, selector: #selector(stepAmpAnim))
             ampLink?.add(to: .main, forMode: .common)
         }
     }

     private func stopAmpLink() {
         ampLink?.invalidate()
         ampLink = nil
     }
     func resetAmpImmediately() {
         DispatchQueue.main.async {
             self.hold3Until = 0
             self.hold5Until = 0
             self.hold10Until = 0
             self.stopAmpLink()
             self.amp = 0
             self.ampTarget = 0
         }
     }

     @objc
     private func stepAmpAnim() {
         let t = CACurrentMediaTime()
         let elapsed = t - ampAnimStart
         let p = max(0, min(1, elapsed / ampAnimDur))
         let eased = cubicEase(ampMode, CGFloat(p))
         let v = ampAnimFrom + (ampTarget - ampAnimFrom) * eased
         amp = v
         if p >= 1 {
             stopAmpLink()
             amp = ampTarget
         }
     }

     private func cubicEase(_ mode: AmpEasing, _ x: CGFloat) -> CGFloat {
         switch mode {
         case .linear: return x
         case .easeIn: return x * x * x
         case .easeOut:
             let u = 1 - x
             return 1 - u * u * u
         case .easeInOut:
             if x < 0.5 {
                 let u = 2 * x
                 return 0.5 * u * u * u
             } else {
                 let u = 2 * (1 - x)
                 return 1 - 0.5 * u * u * u
             }
         }
     }

     private func animateAmp(to value: CGFloat,
                             duration: CFTimeInterval = 0.5,
                             mode: AmpEasing = .easeInOut) {
         DispatchQueue.main.async {
             self.stopAmpLink()
             self.ampMode = mode
             self.ampAnimFrom = self.amp
             self.ampTarget = value
             self.ampAnimDur = max(0.0, duration)
             self.ampAnimStart = CACurrentMediaTime()
             self.ensureAmpLink()
         }
     }

     private func recomputeAmpTarget() {
         DispatchQueue.main.async {
             let now = CACurrentMediaTime()
             let target: CGFloat =
                 (now < self.hold10Until) ? 10 :
                 (now < self.hold5Until)  ? 6  :
                 (now < self.hold3Until)  ? 3  : 0

             guard target != self.ampTarget else { return }

             let isRising = target > self.amp
             let dur: CFTimeInterval = isRising ? self.ampRiseDur : self.ampFallDur

             self.animateAmp(to: target, duration: dur, mode: .easeInOut)
         }
     }

     private func raiseLevel3(for seconds: Double) {
         guard seconds > 0 else { return }
         let until = CACurrentMediaTime() + seconds
         hold3Until = max(hold3Until, until)

         recomputeAmpTarget()

         DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
             guard let self else { return }
             if CACurrentMediaTime() >= self.hold3Until - self.eps {
                 self.recomputeAmpTarget()
             }
         }
     }

     private func makeContinuousPattern(duration: Double,
                                        intensity: Float,
                                        sharpness: Float = 0.5) throws -> CHHapticPattern {

         let d = duration
         let fadeIn = ampRiseDur
         let fadeOut = ampFallDur

         // Only use fades if the duration can fit both fully
         let useFades = d >= (fadeIn + fadeOut)

         if !useFades {
             // No fades: constant event
             let event = CHHapticEvent(
                 eventType: .hapticContinuous,
                 parameters: [
                     CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                     CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                 ],
                 relativeTime: 0,
                 duration: d
             )
             return try CHHapticPattern(events: [event], parameters: [])
         }

         // Fades: base intensity on, scaled by intensityControl curve
         let baseIntensity: Float = 1.0

         let event = CHHapticEvent(
             eventType: .hapticContinuous,
             parameters: [
                 CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity),
                 CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
             ],
             relativeTime: 0,
             duration: d
         )

         let t0: Double = 0.0
         let tUpEnd: Double = fadeIn
         let tDownStart: Double = d - fadeOut
         let tEnd: Double = d

         let curve = CHHapticParameterCurve(
             parameterID: .hapticIntensityControl,
             controlPoints: [
                 .init(relativeTime: t0,         value: 0.0),
                 .init(relativeTime: tUpEnd,     value: intensity),
                 .init(relativeTime: tDownStart, value: intensity),
                 .init(relativeTime: tEnd,       value: 0.0),
             ],
             relativeTime: 0
         )

         return try CHHapticPattern(events: [event], parameterCurves: [curve])
     }


     private func raiseLevel5(for seconds: Double) {
         guard seconds > 0 else { return }
         let until = CACurrentMediaTime() + seconds
         hold5Until = max(hold5Until, until)

         recomputeAmpTarget()

         DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
             guard let self else { return }
             if CACurrentMediaTime() >= self.hold5Until - self.eps {
                 self.recomputeAmpTarget()
             }
         }
     }

     private func raiseLevel10(for seconds: Double) {
         guard seconds > 0 else { return }
         let until = CACurrentMediaTime() + seconds
         hold10Until = max(hold10Until, until)

         recomputeAmpTarget()

         DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
             guard let self else { return }
             if CACurrentMediaTime() >= self.hold10Until - self.eps {
                 self.recomputeAmpTarget()
             }
         }
     }

     private func bumpAmp(for duration: Double, power: String) {
         switch power.lowercased() {
         case "heavy", "strong", "large":
             raiseLevel10(for: duration)
         case "medium", "med", "mid":
             raiseLevel5(for: duration)
         case "low", "light", "soft":
             raiseLevel3(for: duration)
         default:
             raiseLevel5(for: duration)
         }
     }


     private func bumpAmpTransient(intensity: Float, duration: Double) {
         if intensity >= 0.85 {
             raiseLevel10(for: duration)
         } else if intensity >= 0.5 {
             raiseLevel5(for: duration)
         } else {
             raiseLevel3(for: duration)
         }
     }


     private func dropAmpNow() {
         hold3Until = 0
         hold5Until = 0
         hold10Until = 0
         recomputeAmpTarget()  // animates back to 0
     }

     // MARK: - Haptics engine

     enum HapticsError: Error { case engineUnavailable }

     private init() { prepareEngine() }

     func makeAdvancedPlayer(for pattern: CHHapticPattern) throws -> CHHapticAdvancedPatternPlayer {
         guard supportsHaptics else { throw HapticsError.engineUnavailable }
         if engine == nil { prepareEngine() }
         try engine?.start()
         guard let eng = engine else { throw HapticsError.engineUnavailable }
         return try eng.makeAdvancedPlayer(with: pattern)
     }

     /// One-shot transient helper (returns the player so caller can keep track).
     @discardableResult
     func playTransient(intensity: Float = 0.8,
                        sharpness: Float = 0.6,
                        duration: Float = 0.04) -> CHHapticAdvancedPatternPlayer? {

         // drive amp even if CoreHaptics is unavailable
         bumpAmpTransient(intensity: intensity, duration: Double(duration))

         guard supportsHaptics else {
             let gen = UIImpactFeedbackGenerator(style: .medium)
             gen.prepare()
             gen.impactOccurred()
             return nil
         }

         let ev = CHHapticEvent(eventType: .hapticTransient,
                                parameters: [
                                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                                ],
                                relativeTime: 0)
         do {
             let pattern = try CHHapticPattern(events: [ev], parameters: [])
             let player = try makeAdvancedPlayer(for: pattern)
             try player.start(atTime: CHHapticTimeImmediate)
             return player
         } catch {
             print("playTransient failed: \(error)")
             return nil
         }
     }
     func hardStopEngine() {
         guard supportsHaptics else { return }

         dropAmpNow()

         engine?.stop { error in
             if let error { print("CHHapticEngine stop error: \(error)") }
         }

         // Optional: fully release engine so no handlers retain anything
         engine = nil
     }


     private func prepareEngine() {
         guard supportsHaptics else { return }
         do {
             engine = try CHHapticEngine()
             engine?.isAutoShutdownEnabled = true
             engine?.stoppedHandler = { [weak self] reason in
                 self?.onEngineStopped?(reason)
                 self?.dropAmpNow()
             }
             engine?.resetHandler = { [weak self] in
                 self?.onEngineReset?()
             }
             try engine?.start()
         } catch {
             print("Haptics engine start failed: \(error)")
         }
     }

     // MARK: - Continuous players

     func vibrateWithPlayer(duration: Double,
                            power: String,
                            playerRef: @escaping (CHHapticAdvancedPatternPlayer?) -> Void,
                            completion: @escaping () -> Void) {

         let clampedDuration = max(0.02, min(duration, 1000.0))
         bumpAmp(for: clampedDuration, power: power)

         let p = power.lowercased()

         let intensity: Float = {
             switch p {
             case "heavy", "strong", "large": return 1.0
             case "medium", "med", "mid":     return 0.6
             case "low", "light", "soft":     return 0.3
             default:                         return 0.6
             }
         }()

         let fallbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = {
             switch p {
             case "heavy", "strong", "large": return .heavy
             case "medium", "med", "mid":     return .medium
             case "low", "light", "soft":     return .light
             default:                         return .medium
             }
         }()

         guard supportsHaptics else {
             let gen = UIImpactFeedbackGenerator(style: fallbackStyle)
             gen.prepare()
             gen.impactOccurred()
             DispatchQueue.main.asyncAfter(deadline: .now() + clampedDuration, execute: completion)
             playerRef(nil)
             return
         }

         do {
             if engine == nil { prepareEngine() }
             try engine?.start()

             let pattern = try makeContinuousPattern(duration: clampedDuration,
                                                     intensity: intensity,
                                                     sharpness: 0.5)

             let player = try engine?.makeAdvancedPlayer(with: pattern)
             player?.completionHandler = { (_: Error?) in
                 DispatchQueue.main.async { completion() }
             }

             playerRef(player)
             try player?.start(atTime: CHHapticTimeImmediate)

         } catch {
             print("Core Haptics error: \(error)")
             playerRef(nil)
             completion()
         }
     }


     func ensureEngineRunning() {
         guard supportsHaptics else { return }
         if engine == nil {
             prepareEngine()
             return
         }
         do {
             try engine?.start()
         } catch {
             print("ensureEngineRunning start failed: \(error)")
             engine = nil
             prepareEngine()
         }
     }
     func vibrate(duration: Double, power: String, completion: @escaping () -> Void) {
         let clampedDuration = max(0.02, min(duration, 1000.0))
         bumpAmp(for: clampedDuration, power: power)

         let p = power.lowercased()

         let intensity: Float = {
             switch p {
             case "heavy", "strong", "large": return 1.0
             case "medium", "med", "mid":     return 0.6
             case "low", "light", "soft":     return 0.3
             default:                         return 0.6
             }
         }()

         let fallbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = {
             switch p {
             case "heavy", "strong", "large": return .heavy
             case "medium", "med", "mid":     return .medium
             case "low", "light", "soft":     return .light
             default:                         return .medium
             }
         }()

         guard supportsHaptics else {
             let gen = UIImpactFeedbackGenerator(style: fallbackStyle)
             gen.prepare()
             gen.impactOccurred()
             DispatchQueue.main.asyncAfter(deadline: .now() + clampedDuration, execute: completion)
             return
         }

         do {
             if engine == nil { prepareEngine() }
             try engine?.start()

             let pattern = try makeContinuousPattern(duration: clampedDuration,
                                                     intensity: intensity,
                                                     sharpness: 0.5)

             let player = try engine?.makeAdvancedPlayer(with: pattern)
             player?.completionHandler = { (_: Error?) in
                 DispatchQueue.main.async { completion() }
             }

             try player?.start(atTime: CHHapticTimeImmediate)

         } catch {
             print("Core Haptics error: \(error). Falling back.")
             let gen = UIImpactFeedbackGenerator(style: fallbackStyle)
             gen.prepare()
             gen.impactOccurred()
             DispatchQueue.main.asyncAfter(deadline: .now() + clampedDuration, execute: completion)
         }
     }


 }
 
