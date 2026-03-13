//
//  RollView.swift
//  Vibro
//
//  Created by lyubcsenko on 05/09/2025.
//

import SwiftUI
import FirebaseAuth
import CoreHaptics
import FirebaseStorage
import CoreMotion
import Combine
import NaturalLanguage
extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}


final class DeviceMotionManager: ObservableObject {
    static let shared = DeviceMotionManager()
    
    private let manager = CMMotionManager()
    
    @Published var yaw: Double = 0   // radians
    
    private init() {
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        
        guard manager.isDeviceMotionAvailable else { return }
        
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let motion = motion else { return }
            // yaw is rotation around vertical axis: left–right twist
            self?.yaw = motion.attitude.yaw
        }
    }
}

final class HapticsManager {
    static let shared = HapticsManager()
    @MainActor private(set) var amp: CGFloat = 0
    @MainActor private var ampTarget: CGFloat = 0
    @MainActor private var ampAnimFrom: CGFloat = 0
    @MainActor private var ampAnimStart: CFTimeInterval = 0
    @MainActor private var ampAnimDur: CFTimeInterval = 0.5
    @MainActor private var ampLink: CADisplayLink?
    private var hold3Until: TimeInterval = 0
    private var hold5Until: TimeInterval = 0
    private var hold10Until: TimeInterval = 0
    private let eps: TimeInterval = 1e-6
    @MainActor private var ampGen: UInt64 = 0
    @MainActor private func bumpAmpGen() { ampGen &+= 1 }

    @MainActor
    private func recomputeAmpTarget() {
        let now = CACurrentMediaTime()
        let target: CGFloat =
            (now < hold10Until) ? 10 :
            (now < hold5Until)  ? 6  :
            (now < hold3Until)  ? 3  :
            0

        if target != ampTarget {
            animateAmp(to: target, duration: 0.5, mode: .easeInOut)
        }
    }
    enum AmpEasing { case easeInOut, easeOut, easeIn, linear }
    private var ampHoldUntil: TimeInterval = 0
    @MainActor
    private func ensureAmpLink() {
        if ampLink == nil {
            ampLink = CADisplayLink(target: self, selector: #selector(stepAmpAnim))
            ampLink?.add(to: .main, forMode: .common)
        }
    }
    



    @MainActor
    private func stopAmpLink() {
        ampLink?.invalidate()
        ampLink = nil
    }
    @objc
    @MainActor
    private func stepAmpAnim() {
        let t = CACurrentMediaTime()
        let elapsed = t - ampAnimStart
        let p = max(0, min(1, elapsed / ampAnimDur))
        let eased = cubicEase(ampMode, CGFloat(p))
        let v = ampAnimFrom + (ampTarget - ampAnimFrom) * eased
        amp = v
        if p >= 1 { stopAmpLink(); amp = ampTarget }
    }
    @MainActor
    private func cubicEase(_ mode: AmpEasing, _ x: CGFloat) -> CGFloat {
        switch mode {
        case .linear: return x
        case .easeIn: return x * x * x
        case .easeOut:
            let u = 1 - x; return 1 - u * u * u
        case .easeInOut:
            if x < 0.5 {
                let u = 2 * x; return 0.5 * u * u * u
            } else {
                let u = 2 * (1 - x); return 1 - 0.5 * u * u * u
            }
        }
    }

    @MainActor
    private var ampMode: AmpEasing = .easeInOut

    @MainActor
    private func animateAmp(to value: CGFloat, duration: CFTimeInterval = 0.5, mode: AmpEasing = .easeInOut) {
        // start a new tween from current amp → target
        stopAmpLink()
        ampMode = mode
        ampAnimFrom = amp
        ampTarget = value
        ampAnimDur = max(0.0, duration)
        ampAnimStart = CACurrentMediaTime()
        ensureAmpLink()
    }
    private func raiseLevel3(for seconds: Double) {
        raiseHold(level: 3, for: seconds)
    }

    private func raiseLevel5(for seconds: Double) {
        raiseHold(level: 5, for: seconds)
    }

    private func raiseLevel10(for seconds: Double) {
        raiseHold(level: 10, for: seconds)
    }

    private func raiseHold(level: Int, for seconds: Double) {
        guard seconds > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Each "hold request" belongs to the current amp generation
            let token = self.ampGen

            let until = CACurrentMediaTime() + seconds
            switch level {
            case 10: self.hold10Until = max(self.hold10Until, until)
            case 5:  self.hold5Until  = max(self.hold5Until,  until)
            default: self.hold3Until  = max(self.hold3Until,  until)
            }

            self.recomputeAmpTarget()

            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                // ✅ ignore stale scheduled recompute
                guard self.ampGen == token else { return }

                let now = CACurrentMediaTime()
                let holdUntil: TimeInterval = {
                    switch level {
                    case 10: return self.hold10Until
                    case 5:  return self.hold5Until
                    default: return self.hold3Until
                    }
                }()

                if now >= holdUntil - self.eps {
                    self.recomputeAmpTarget()
                }
            }
        }
    }


    private func dropAmpNow() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hold3Until = 0
            self.hold5Until = 0
            self.hold10Until = 0
            self.recomputeAmpTarget() // animates to 0
        }
    }



    
    
    private let q = DispatchQueue(label: "haptics.manager.serial")
    private var players: [CHHapticAdvancedPatternPlayer] = []
    private var playGen: UInt64 = 0
    private var isShuttingDown = false
    private var engineReady = false
    // Activation tokens
    private let maxPreviewPlayers = 8   // tune to taste
    
    private var activators = Set<ObjectIdentifier>()
    private var isActive = false
    
    // NEW: single-session focus (the row that currently owns playback)
    private var currentOwner: ObjectIdentifier?
    
    private init() {
        Haptics.shared.onEngineStopped = { [weak self] _ in
            guard let self else { return }
            self.q.async { self.stopLocked() }
        }
        Haptics.shared.onEngineReset = { [weak self] in
            guard let self else { return }
            self.q.async { self.stopLocked() }
        }
    }
    
    private var keepWarmUntil: TimeInterval = 0
    private var warmTimerScheduled = false
    private let warmSoftStopAfter: TimeInterval = 0.75
    private let warmHardStopAfter: TimeInterval = 2.0    // fully stop engine later
    
    private func pokeWarmth() {
        keepWarmUntil = CACurrentMediaTime() + warmHardStopAfter
        guard !warmTimerScheduled else { return }
        warmTimerScheduled = true
        q.asyncAfter(deadline: .now() + warmHardStopAfter) { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if now >= self.keepWarmUntil {
                // first, soft stop players so the engine stays hot a bit
                self.stopLocked() // players only
                self.q.asyncAfter(deadline: .now() + (self.warmHardStopAfter - self.warmSoftStopAfter)) {
                    let now2 = CACurrentMediaTime()
                    if now2 >= self.keepWarmUntil {
                        Haptics.shared.hardStopEngine()
                    }
                    self.warmTimerScheduled = false
                }
            } else {
                // warmth got extended; reschedule
                self.warmTimerScheduled = false
                self.pokeWarmth()
            }
        }
    }
    
    func activate(for owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        q.async {
            self.activators.insert(key)
            self.updateActiveLocked()
        }
    }
    private func ensureEngineSync(_ done: @escaping () -> Void) {
        Haptics.shared.ensureEngineRunning()
        q.async {
            self.engineReady = true
            done()  // immediate
        }
    }
    private func playTransientLocked(intensity: Float = 0.8,
                                     sharpness: Float = 0.6,
                                     duration: Float = 0.04) {
        guard isActive else { return }
        let ev = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [
                                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                               ],
                               relativeTime: 0)
        let pat = try? CHHapticPattern(events: [ev], parameters: [])
        if let p = Haptics.shared.playTransient(intensity: intensity,
                                                sharpness: sharpness,
                                                duration: duration) {
            players.append(p)
            if players.count > maxPreviewPlayers {
                if let old = players.first { try? old.stop(atTime: CHHapticTimeImmediate) }
                players.removeFirst()
            }
        }
    }
    
    func deactivate(for owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        q.async {
            self.activators.remove(key)
            // If the deactivating owner owns the session, drop it.
            if self.currentOwner == key {
                self.bumpGen()
                self.stopLocked()
                Haptics.shared.hardStopEngine()
                self.currentOwner = nil
            }
            self.updateActiveLocked()
        }
    }
    
    private func updateActiveLocked() {
        let shouldBeActive = !activators.isEmpty && !isShuttingDown
        if shouldBeActive == isActive { return }
        isActive = shouldBeActive
        if !isActive {
            bumpGen()
            stopLocked()
            Haptics.shared.hardStopEngine()
            currentOwner = nil
        }
    }
    


    func stop() {
        q.async {
            self.bumpGen()
            self.stopLocked()
            Haptics.shared.hardStopEngine()
        }
    }
    
    func cancelAll() {
        q.async {
            self.bumpGen()
            self.stopLocked()
            Haptics.shared.hardStopEngine()
            self.currentOwner = nil
        }
    }
    private func beginSessionLocked(for ownerKey: ObjectIdentifier,
                                    invalidatePrevious: Bool = true) -> UInt64? {
        guard isActive, !isShuttingDown else { return nil }
        
        if currentOwner != ownerKey {
            // owner handoff: nuke & restart engine
            bumpGen()
            stopLocked()
            Haptics.shared.hardStopEngine()
            currentOwner = ownerKey
        } else if invalidatePrevious {
            // same owner, new pattern: cancel any queued callbacks from the last run
            bumpGen()
            stopLocked()   // soft
        }
        
        ensureEngine()
        return playGen
    }
    
    
    // MARK: - Owner-aware play
    func playBatch(for owner: AnyObject, _ entries: [TapEntry]) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard let token = self.beginSessionLocked(for: ownerKey) else { return }
            let nonDelay = entries.filter { $0.entryType != "delay" && $0.value > 0 }
            let m1Dur = nonDelay.filter { $0.entryType == "m1" }.map(\.value).max() ?? 0
            let m2Dur = nonDelay.filter { $0.entryType == "m2" }.map(\.value).max() ?? 0
            let m3Dur = nonDelay.filter { $0.entryType == "m3" }.map(\.value).max() ?? 0
            if m1Dur > 0 { self.raiseLevel3(for: m1Dur) }
            if m2Dur > 0 { self.raiseLevel5(for: m2Dur) }
            if m3Dur > 0 { self.raiseLevel10(for: m3Dur) }


            guard !nonDelay.isEmpty else {
                if let d = entries.first(where: { $0.entryType == "delay" && $0.value > 0 })?.value {
                    self.q.asyncAfter(deadline: .now() + d) { [weak self] in
                        guard let self,
                              self.isActive,
                              self.currentOwner == ownerKey,
                              self.playGen == token else { return }
                        self.stopLocked()
                    }
                }
                return
            }
            
            var newPlayers: [CHHapticAdvancedPatternPlayer] = []
            let group = DispatchGroup()
            
            for e in nonDelay {
                group.enter()

                let t = e.entryType.lowercased()
                let power: String = {
                    switch t {
                    case "m1": return "low"
                    case "m2": return "medium"
                    case "m3": return "large"
                    default:   return "medium"
                    }
                }()

                Haptics.shared.vibrateWithPlayer(duration: e.value, power: power, entry: e) { player in
                    if let p = player {
                        self.q.async {
                            if self.isActive, self.currentOwner == ownerKey, self.playGen == token {
                                newPlayers.append(p)
                            }
                        }
                    }
                } completion: {
                    self.q.async { group.leave() }
                }
            }
            
            group.notify(queue: self.q) {
                guard self.isActive, self.currentOwner == ownerKey, self.playGen == token else { return }
                self.players = newPlayers
            }
        }
    }
    
    func playSequence(for owner: AnyObject, _ entries: [TapEntry]) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard let token = self.beginSessionLocked(for: ownerKey) else { return }
            self.runSequenceLocked(ownerKey: ownerKey, entries, index: 0, token: token)
        }
    }
    func softStop() {
        q.async {
            self.bumpGen()       // invalidate any queued runSequenceLocked steps
            self.stopLocked()
            // stop in-flight players, keep engine warm
        }
    }
    /// Ensure engine is up before first play of a new selection.
    func prewarm() {
        q.async {
            guard self.isActive else { return }
            self.ensureEngine()                // starts engine if needed
        }
    }
    func playBatchPreview(for owner: AnyObject,
                          _ entries: [TapEntry],
                          intensity: Float? = nil,
                          sharpness: Float? = nil,
                          duration: Float? = nil) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard self.isActive else { return }
            if self.currentOwner != ownerKey {
                self.bumpGen()
                self.stopLocked()
                Haptics.shared.hardStopEngine()
                self.currentOwner = ownerKey
            }
            self.ensureEngineSync {
                // Always at least a transient tick
                self.playTransientLocked(intensity: intensity ?? 0.8,
                                         sharpness: sharpness ?? 0.6,
                                         duration: duration ?? 0.04)
                // Optionally mirror entries
                for e in entries where e.entryType != "delay" && e.value > 0 {
                    let dur = duration ?? Float(min(e.value, 0.06))
                    let (int, shp): (Float, Float) = {
                        switch e.entryType.lowercased() {
                        case "m3":
                            return (1.0, 0.9)
                        case "m2":
                            return (0.7, 0.6)
                        case "m1":
                            return (0.3, 0.2)
                        default:
                            return (0.7, 0.6)
                        }
                    }()
                    
                    let intensityValue = intensity ?? int
                    let sharpnessValue = sharpness ?? shp
                    
                    self.playTransientLocked(
                        intensity: intensityValue,
                        sharpness: sharpnessValue,
                        duration: dur
                    )
                }
            }
            
        }
    }
    func playSequencePreview(for owner: AnyObject, _ entries: [TapEntry]) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard let token = self.beginSessionLocked(for: ownerKey, invalidatePrevious: false) else { return }

            guard let first = entries.first(where: { $0.entryType.lowercased() != "delay" && $0.value > 0 }) else {
                return
            }

            let type = first.entryType.lowercased()

            // Preview feel (you can keep these or simplify to just power mapping)
            let (baseInt, baseShp): (Float, Float) = {
                switch type {
                case "m3": return (1.0, 0.9)
                case "m2": return (0.7, 0.6)
                case "m1": return (0.3, 0.2)
                default:   return (0.7, 0.6)
                }
            }()

            // keep duration short for preview
            let dur = Float(min(first.value, 0.06))

            // Optional: mirror your amp holds for preview too
            switch type {
            case "m1": self.raiseLevel3(for: Double(dur))
            case "m2": self.raiseLevel5(for: Double(dur))
            case "m3": self.raiseLevel10(for: Double(dur))
            default: break
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // If your wrapper returns a player:
                if let p = Haptics.shared.playTransient(intensity: baseInt, sharpness: baseShp, duration: dur) {
                    self.q.async { [weak self] in
                        guard let self else { return }
                        guard self.isActive, self.currentOwner == ownerKey, self.playGen == token else { return }

                        self.players.append(p)
                        if self.players.count > self.maxPreviewPlayers {
                            if let old = self.players.first {
                                try? old.stop(atTime: CHHapticTimeImmediate)
                            }
                            self.players.removeFirst()
                        }
                    }
                }
            }
        }
    }


    // MARK: - Private (q only)
    private func runSequenceLocked(ownerKey: ObjectIdentifier, _ entries: [TapEntry], index: Int, token: UInt64) {
        guard token == playGen, isActive, currentOwner == ownerKey else { return }
        guard index < entries.count else { stopLocked(); return }

        let e = entries[index]
        if e.entryType == "delay" || e.value <= 0 {
            q.asyncAfter(deadline: .now() + max(0, e.value)) { [weak self] in
                guard let self else { return }
  
                self.runSequenceLocked(ownerKey: ownerKey, entries, index: index + 1, token: token)
            }
            return
        }
        let power: String
        switch e.entryType {
        case "m3":
            power = "large"
        case "m2":
            power = "medium"
        case "m1":
            power = "low"
        default: // m1 or anything else
            power = "low"
        }

        Haptics.shared.vibrateWithPlayer(duration: e.value, power: power, entry: e) { [weak self] player in
            guard let self else { return }
            self.q.async {
                if let p = player,
                   self.isActive,
                   self.currentOwner == ownerKey,
                   self.playGen == token {
                    self.players.append(p)
                }
            }
        } completion: { [weak self] in
            guard let self else { return }
            self.q.async {
                guard token == self.playGen,
                      self.isActive,
                      self.currentOwner == ownerKey else { return }
                self.runSequenceLocked(ownerKey: ownerKey, entries, index: index + 1, token: token)
            }
        }

    }

    private func ensureEngine() { guard isActive else { return }; Haptics.shared.ensureEngineRunning() }
    private func stopLocked() { players.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }; players.removeAll()
        dropAmpNow()
    }
    private func bumpGen() { playGen &+= 1 }

    func beginShutdown() { q.async { self.isShuttingDown = true; self.updateActiveLocked(); self.stopLocked() } }
    func endShutdown()   { q.async { self.isShuttingDown = false; self.updateActiveLocked() } }
}

extension HapticsManager {
    func cutToSilence() {
        q.async {
            self.bumpGen()          // invalidate scheduled q.asyncAfter callbacks
            self.stopLocked()       // stop players now (no hard stop)
            self.pokeWarmth()       // keep engine hot for a short period
        }
    }
    func playExactPreview(for owner: AnyObject, _ entries: [TapEntry]) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard self.isActive else { return }

            if self.currentOwner != ownerKey {
                self.currentOwner = ownerKey
                self.stopLocked()
                self.ensureEngine()
            }

            let slice = entries.filter { $0.entryType != "delay" && $0.value > 0 }
            guard !slice.isEmpty else { return }

            for e in slice {
                let duration = e.value
                guard duration > 0 else { continue }
                let power: String
                switch e.entryType {
                case "m3": power = "large"
                case "m2": power = "medium"
                case "m1": power = "low"
                default:   power = "low"   // m1
                }

                Haptics.shared.vibrateWithPlayer(duration: duration, power: power, entry: e) { [weak self] player in
                    guard let self, let p = player else { return }
                    self.q.async {
                        self.players.append(p)
                        if self.players.count > self.maxPreviewPlayers {
                            if let old = self.players.first {
                                try? old.stop(atTime: CHHapticTimeImmediate)
                            }
                            self.players.removeFirst()
                        }
                    }
                } completion: { }
            }
        }
    }
    func playExactPreview(for owner: AnyObject,
                          previewEntries: [PreviewEntry],
                          intensityScale: Float = 1.0,
                          sharpnessScale: Float = 1.0) {
        let ownerKey = ObjectIdentifier(owner)
        q.async {
            guard self.isActive else { return }

            if self.currentOwner != ownerKey {
                self.currentOwner = ownerKey
                self.stopLocked()
                self.ensureEngine()
            }
            guard !previewEntries.isEmpty else { return }

            let token = self.playGen
            self.pokeWarmth() // optional: extend warm window

            var startOffset: Double = 0.0
            for pe in previewEntries {
                let e = pe.original
                let d = max(0.0, pe.durationOverride)

                if e.entryType == "delay" { startOffset += d; continue }
                guard d > 0 else { continue }

                let power: String
                switch e.entryType {
                case "m3": power = "large"
                case "m2": power = "medium"
                case "m1": power = "low"
                default:   power = "low"   // m1
                }
                let scheduled = startOffset

                self.q.asyncAfter(deadline: .now() + scheduled) { [weak self] in
                    guard let self = self,
                          self.isActive,
                          self.playGen == token,
                          self.currentOwner == ownerKey else { return }

                    Haptics.shared.vibrateWithPlayer(duration: d, power: power, entry: e) { [weak self] player in
                        guard let self, let p = player else { return }
                        self.q.async {
                            self.players.append(p)
                            if self.players.count > self.maxPreviewPlayers {
                                if let old = self.players.first { try? old.stop(atTime: CHHapticTimeImmediate) }
                                self.players.removeFirst()
                            }
                        }
                    } completion: { }
                }
            }
        }
    }
}

struct PulsingRing: InsettableShape {
    var amplitude: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var c = self; c.insetAmount += amount; return c
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let center = CGPoint(x: w/2, y: h/2)
        let baseR = min(w, h)/2 - insetAmount
        let A = max(0, amplitude)                 // clamp so we never invert

        // Match BumpedArc’s ~1° resolution
        let steps = max(2, Int((2 * Float.pi) / (Float.pi / 180))) // 360

        // Outer edge (baseR + A)
        var outer = Path()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let theta = t * 2 * .pi
            let r = baseR + A
            let x = center.x + r * cos(theta)
            let y = center.y + r * sin(theta)
            let pt = CGPoint(x: x, y: y)
            if i == 0 { outer.move(to: pt) } else { outer.addLine(to: pt) }
        }

        // Inner edge (baseR), traced back
        var inner = Path()
        for i in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            let theta = t * 2 * .pi
            let r = baseR
            let x = center.x + r * cos(theta)
            let y = center.y + r * sin(theta)
            let pt = CGPoint(x: x, y: y)
            if i == steps { inner.move(to: pt) } else { inner.addLine(to: pt) }
        }

        var p = Path()
        p.addPath(outer)
        p.addPath(inner)
        p.closeSubpath()
        return p
    }
}




struct PreviewEntry {
    let original: TapEntry
    let durationOverride: Double
}

private struct ScrubSession {
    var anchorT: Double = 0        // where the finger started (logical time)
    var lastT: Double = 0          // last logical time we processed
    var cumulative: Double = 0     // total logical |distance| since anchor
}




struct ModelRow: View {
    @Binding var playbackIsPlayed: Bool
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    // REMOVED: @Binding var currentPlayers: [CHHapticAdvancedPatternPlayer]
    let isScrolldownActive: Bool
    let model: Model
    let overLimit: Bool
    let isStarred: Bool
    @Binding var isActive: Bool
    @Binding var selectedFilter: String
    @Binding var iconURLCache: [String: URL]
    let onTap: () -> Void
    let onFilterSelected: (String) -> Void
    let onCreatorTap: () -> Void
    let onChevronUp: () -> Void
    let onEditNote: () -> Void
    
    // Data
    
    @State private var scrub = ScrubSession()
    
    
    @State private var TapData: [Int: [Int: [TapEntry]]] = [:]
    @State private var commandNames: [Int: [Int: String]] = [:]
    
    @State private var latinLongText: String = ""
    
    @State private var perCommandLatinText: String =
        ""


    
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    // Selection/UI
    @State private var isExpanded = false
    @State private var selectedCMND: Int = 0
    @State private var selectedPart: Int = 0
    @State private var selectedCMNDType: Int = 0
    @State private var selectedEntryIndices: Set<Int> = []
    @State private var showTAPSModificationLine: Bool = false
    @State private var showSetCMNDType = false
    @State private var CMNDType: Int = 1
    
    // Env
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @EnvironmentObject var sharedData: SharedData
    @State private var reportTarget: Model? = nil
    // Like / fav
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("likingModelCooldownUntil") private var likingCooldownUntil: Double = 0
    @AppStorage("likingModelSpamCount")     private var likingSpamCount: Int = 0
    @AppStorage("likingModelLastTap")       private var likingLastTap: Double = 0
    @State private var showLikeCooldownAlert = false
    @State private var likeCooldownMessage   = ""
    @State private var processingIsFavourite = false
    @State private var isFavouriteModel: Bool = false
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    private let likeSpamThreshold  = 10
    private let likeCooldownWindow: TimeInterval = 30*60
    private let likeSpamWindow:    TimeInterval = 60
    // User
    @State private var userID: String = ""
    @State private var userName: String = ""
    @AppStorage("ScrollsAutoplay") private var ScrollsAutoplay: Bool = true
    // UI state
    @State private var uiHidden = false
    @State private var showReportMenu = false
    @State private var loadingWorkItem: DispatchWorkItem?
    @State private var showLoading: Bool = false
    
    // Playback timeline
    @State private var previewInSeconds: Double = 0.0
    @State private var previewSeconds: Double = 0.0
    @State private var isPlayingPreview = false
    @State private var playbackTapEntries: [Double: [Int: [TapEntry]]] = [:]
    @State private var bucketDurations: [Double: Double] = [:]
    @State private var orderedKeys: [Double] = []
    @State private var nextBucketIndex = 0
    @State private var playbackSpeed: Double = 1.0
    @State private var selectedPrimary: Int? = nil
    @State private var isPaused = false
    @State private var wasPlayingBeforeHold = false
    
    // New: cancellable playback task + throttling + async generation
    @State private var playbackTask: Task<Void, Never>?
    @State private var lastSpeedToggle: Date = .distantPast
    @State private var loadGen: Int = 0
    private final class HapticOwner {}
    @State private var hOwner = HapticOwner()
    @State private var displayedText: String = ""

    // Constants
    private let epsilon: Double = 0.0005
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @inline(__always)
    private func clamped(_ val: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, val))
    }
    private var H: CGFloat { UIScreen.main.bounds.height } // real device height
    // Reporting
    var onReport: () -> Void
    @State private var isSpeedHeld: Bool = false
    
    @State private var rowPlayGen: UInt64 = 0
    @inline(__always) private func bumpRowGen() { rowPlayGen &+= 1 }
    @State private var lastScrubEvent: (t: TimeInterval, logical: Double)? = nil
    @State private var scrubPreviewCooldownUntil: TimeInterval = 0
    
    private let scrubPreviewRateMax: Double = .infinity
    private let scrubPreviewMinGap: TimeInterval = 0.0
    
    private let minHapticPreview: Double = 0.06   // 60ms feelable
    private let hapticScale: Double      = 0.10   // 10% of real dur for mid buckets
    private let hapticMax: Double        = 0.15   // cap for mid buckets
    private let lastHapticMax: Double    = 1.00   // allow up to 1s on the bucket you stop on
    
    private let minDelayPreview: Double  = 0.02
    private let delayScale: Double       = 0.20   // 20% of real delay
    private let delayMax: Double         = 1.00   // never wait more than 1s in preview
    
    @inline(__always)
    private func compressedDuration(for e: TapEntry, isLastBucket: Bool, scale: Double) -> Double {
        // base constants (same as yours)
        let minHapticPreview: Double = 0.06
        let hapticScale: Double      = 0.10
        let hapticMax: Double        = 0.15
        let lastHapticMax: Double    = 1.00
        
        let minDelayPreview: Double  = 0.02
        let delayScale: Double       = 0.20
        let delayMax: Double         = 1.00
        
        if e.entryType == "delay" {
            // delays compress but also expand with scale (feel more “real” as you drag more)
            let dur = max(minDelayPreview * scale, e.value * (delayScale * scale))
            return min(delayMax, dur)
        } else {
            if isLastBucket {
                // final bucket: allow much closer to real; still cap to protect UX
                let dur = max(minHapticPreview * scale, e.value * scale)
                return min(lastHapticMax, dur)
            } else {
                // along the path: start tiny, grow with scale; cap
                let base = max(minHapticPreview * scale, e.value * (hapticScale * scale))
                return min(hapticMax * scale, base)
            }
        }
    }
    
    @StateObject private var deviceMotion = DeviceMotionManager.shared

    @State private var spiralTotalRotation: Angle = .zero
    @State private var spiralDragRotation: Angle = .zero
    @State private var spiralDragStartAngle: Angle? = nil
    @State private var activeSpiralKey: Int?                  // the key currently in full-screen
    @State private var deviceBaseYaw: Double? = nil
    @State private var deviceYawRotation: Angle = .zero
    @Environment(\.colorScheme) private var colorScheme

    
    @inline(__always)
    private func previewScale(for cumulative: Double, total: Double) -> Double {
        guard total > 0 else { return 0.1 }
        let target = 0.25 * total
        let norm = min(1.0, cumulative / max(0.001, target))
        // 10% at start → 100% at long drags
        return 0.10 + 0.90 * norm
    }
    
    @inline(__always)
    private func intensityScale(for cumulative: Double, total: Double) -> Float {
        guard total > 0 else { return 0.5 }
        let norm = min(1.0, cumulative / (0.25 * total))
        // starts subtle, ends “full”
        return Float(0.4 + 0.6 * pow(norm, 0.7))
    }
    
    @inline(__always)
    private func sharpnessScale(for cumulative: Double, total: Double) -> Float {
        guard total > 0 else { return 0.5 }
        let norm = min(1.0, cumulative / (0.25 * total))
        return Float(0.5 + 0.5 * pow(norm, 0.8))
    }
    
    @inline(__always)
    private func fireCompressedPreviewAcross(oldT: Double, newT: Double, scale: Double) {
        guard previewInSeconds > 0 else { return }
        ensureOrderedKeys()
        
        let lo = min(oldT, newT) + epsilon
        let hi = max(oldT, newT) + epsilon
        
        var i0 = max(0, indexAfter(time: lo) - 1)
        var i1 = max(0, indexAfter(time: hi) - 1)
        if i0 > i1 { swap(&i0, &i1) }
        guard !orderedKeys.isEmpty, i0 <= i1, i1 < orderedKeys.count else { return }
        
        // last bucket with content
        var lastContentIdx: Int? = nil
        for i in i0...i1 {
            if let perList = playbackTapEntries[orderedKeys[i]],
               perList.values.contains(where: { list in
                   list.contains(where: { $0.entryType != "delay" && $0.value > 0 })
               }) {
                lastContentIdx = i
            }
        }
        guard let lastIdx = lastContentIdx else {
            HapticsManager.shared.cutToSilence()
            return
        }
        
        var stitched: [PreviewEntry] = []
        for i in i0...i1 {
            guard let perList = playbackTapEntries[orderedKeys[i]] else { continue }
            let isLast = (i == lastIdx)
            for listIndex in perList.keys.sorted() {
                if let entries = perList[listIndex], !entries.isEmpty {
                    for e in entries where e.entryType != "delay" && e.value > 0 {
                        stitched.append(PreviewEntry(
                            original: e,
                            durationOverride: compressedDuration(for: e, isLastBucket: isLast, scale: scale)
                        ))
                    }
                }
            }
        }
        
        if stitched.isEmpty {
            HapticsManager.shared.cutToSilence()
            return
        }
        
        // Scale “feel” as well. Add the overload below in HapticsManager (next section).
        let iScale = intensityScale(for: scrub.cumulative, total: previewInSeconds)
        let sScale = sharpnessScale(for: scrub.cumulative, total: previewInSeconds)
        HapticsManager.shared.playExactPreview(for: hOwner, previewEntries: stitched, intensityScale: iScale, sharpnessScale: sScale)
    }
    
    
    @inline(__always)
    private func fireScrubbedBuckets(from oldT: Double,
                                     to newT: Double,
                                     previewIntensity: Float,
                                     previewSharpness: Float) {
        guard previewInSeconds > 0 else { return }
        ensureOrderedKeys()
        
        var fired = false
        func kick(_ entries: [TapEntry]) {
            let nonDelay = entries.filter { $0.entryType != "delay" && $0.value > 0 }
            guard !nonDelay.isEmpty else { return }   // delays are silence
            HapticsManager.shared.playExactPreview(for: hOwner, nonDelay)
            fired = true
        }
        
        if newT > oldT {
            var idx = indexAfter(time: oldT)
            while idx < orderedKeys.count, orderedKeys[idx] <= newT + epsilon {
                if let perList = playbackTapEntries[orderedKeys[idx]] {
                    for listIndex in perList.keys.sorted() {
                        let entries = perList[listIndex] ?? []
                        guard !entries.isEmpty else { continue }
                        kick(entries)
                    }
                }
                idx += 1
            }
        } else if newT < oldT {
            var idx = max(0, indexAfter(time: newT) - 1)
            while idx >= 0, orderedKeys[idx] >= newT - epsilon, orderedKeys[idx] > oldT - epsilon {
                if let perList = playbackTapEntries[orderedKeys[idx]] {
                    for listIndex in perList.keys.sorted() {
                        let entries = perList[listIndex] ?? []
                        guard !entries.isEmpty else { continue }
                        kick(entries)
                    }
                }
                idx -= 1
            }
        }
        if !fired {
            HapticsManager.shared.cutToSilence()
        }
        
    }
    
    
    private func setAccent(from image: UIImage) {
        let picked: UIColor? = image.vibrantAverageColor ?? image.averageColor
        if let picked {
            DispatchQueue.main.async {
                sharedData.publishedAccentColors[model.name] = Color(picked)
            }
        }
    }
    private func storageRefForCurrentUserModelImage(_ name: String) -> StorageReference? {
        guard let email = Auth.auth().currentUser?.email else { return nil }
        return Storage.storage().reference()
            .child("PublishedModels")
            .child("\(sharedData.appLanguage)")
            .child(name)
            .child("ModelImage.jpg")
    }
    
    private func ensurePublishedAccentIfNeeded() {
        // If we already have an accent, we're done.
        if sharedData.publishedAccentColors[model.name] != nil { return }
        
        // Try disk cache (same identifier you use elsewhere)
        let id = "PublishedModels/\(sharedData.appLanguage)/\(model.name)/ModelImage.jpg"
        if let img = ImageDiskCache.shared.load(identifier: id) {
            setAccent(from: img)
        }
    }
    
    
    private func ensurePublishedAccentIfPreviewing() {
        let modelName = model.name
        if sharedData.publishedAccentColors[model.name] != nil { return }
        
        let id = "PublishedModels/\(sharedData.appLanguage)/\(modelName)/ModelImage.jpg"
        
        // 1) Try disk cache first
        if let img = ImageDiskCache.shared.load(identifier: id) {
            setAccent(from: img)
            return
        }
        
        let ref = Storage.storage().reference()
            .child("PublishedModels")
            .child("\(sharedData.appLanguage)")
            .child(modelName)
            .child("ModelImage.jpg")
        
        ref.downloadURL { url, error in
            if let error = error as NSError? {
                // Ignore missing files; log others if you want
                if error.domain == StorageErrorDomain,
                   StorageErrorCode(rawValue: error.code) == .objectNotFound {
                    return
                } else {
                    print("Image lookup error for \(modelName):", error.localizedDescription)
                    return
                }
            }
            guard let url else { return }
            
            DispatchQueue.main.async {
                sharedData.publishedModelImageURLs[modelName] = url
            }
            
            // ✅ Now actually fetch the image so we can setAccent(from:)
            URLSession.shared.dataTask(with: url) { data, _, err in
                if let err { print("Image download error:", err.localizedDescription); return }
                guard let data, let uiImage = UIImage(data: data) else { return }
                
                // Optional: cache it to disk so next time you hit your fast path
                ImageDiskCache.shared.save(uiImage, identifier: "PublishedModels/\(sharedData.appLanguage)/\(modelName)/ModelImage.jpg")
                
                DispatchQueue.main.async {
                    setAccent(from: uiImage)
                }
            }.resume()
        
        }
    }
    private func fetchModelImageIfExists(for modelName: String, email: String) {
        let ref = Storage.storage().reference()
            .child("PublishedModels")
            .child("\(sharedData.appLanguage)")
            .child(modelName)
            .child("ModelImage.jpg")
        
        ref.downloadURL { url, error in
            if let error = error as NSError? {
                // Ignore missing files; log others if you want
                if error.domain == StorageErrorDomain,
                   StorageErrorCode(rawValue: error.code) == .objectNotFound {
                    return
                } else {
                    print("Image lookup error for \(modelName):", error.localizedDescription)
                    return
                }
            }
            if let url = url {
                DispatchQueue.main.async {
                    print("FETCEHD")
                    sharedData.publishedModelImageURLs[modelName] = url
                }
            }
        }
    }
    private func ensureModelImageCached() {
        // Only the URL part; don't short-circuit on accent color here
        if sharedData.publishedModelImageURLs[model.name] == nil,
           let email = Auth.auth().currentUser?.email {
            fetchModelImageIfExists(for: model.name, email: email)
        }
    }
    
    private struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    private func hardResetOnLoseFocus() {
        // invalidate any scheduled playback immediately
        bumpRowGen()
        playbackTask?.cancel()
        playbackTask = nil
        
        // kill any pending loads or spinners
        loadGen &+= 1
        loadingWorkItem?.cancel()
        showLoading = false
        
        // clear timeline/selection so nothing can "resume"
        isPlayingPreview = false
        isPaused = false
        playbackIsPlayed = false
        playbackSpeed = 1.0
        previewSeconds = 0
        previewInSeconds = 0
        orderedKeys.removeAll()
        nextBucketIndex = 0
        playbackTapEntries.removeAll()
        bucketDurations.removeAll()
        selectedCMND = 0
        selectedPart = 0
        selectedCMNDType = 0
        selectedEntryIndices.removeAll()
        
        // slam the engine + queued callbacks
        HapticsManager.shared.cancelAll()
    }
    
    @State private var contentHeight: CGFloat = 0
    @State private var speedBoostActive = false
    @State private var didLongPress = false
    @State private var showingFullScreenButton: Int? = nil
    @State private var modelID: Int = 0
    
    @State private var animateHalo: Bool = false
    @State private var startedAt = Date()

    // Tunables
    let delay: TimeInterval = 0.5           // wait before movement
    let cycleDuration: TimeInterval = 1.2   // time for one pass left→right
    let threshold: CGFloat = 0.4
    let bw: CGFloat = .pi / 16

    @State private var spiralBaseRotation: [Int: Angle] = [:]
    @State private var speedPressStart: Date?
    @State private var speedLatched = false
    @State private var speedLatchWorkItem: DispatchWorkItem?
    @State private var speedAutoOffWorkItem: DispatchWorkItem?

    private let latchThreshold: TimeInterval = 1.0

    @GestureState private var speedPressing = false
    @State private var speedWasPressing = false


    @State private var speedLongHold = false     // ✅ NEW: true once threshold is reached
    @State private var speedThresholdWorkItem: DispatchWorkItem?

    private let maxAutoOff: TimeInterval = 3.0       // optional cap (prevents super long)
    @MainActor private func enable2x() {
        speedBoostActive = true
        isSpeedHeld = true
        setSpeedBoost(active: true)
    }

    @MainActor private func disable2x() {
        speedBoostActive = false
        isSpeedHeld = false
        speedLatched = false
        setSpeedBoost(active: false)
    }



    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    var body: some View {
        GeometryReader { geometry in
            let progress = max(0, min(1, (previewInSeconds > 0) ? (previewSeconds / previewInSeconds) : 0))
            let accent = sharedData.publishedAccentColors[model.name] ?? selectedAccent.color
            
            
            ZStack {
                if isPaused {
                    Color.clear
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                
                // Tap / Hold overlay controlling pause / resume
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height) * 0.5
                    
                    let tap = TapGesture()
                        .onEnded {
                            if !isPaused {
                                isPaused = true
                                pausePlayback()
                            } else {
                                isPaused = false
                                let current = previewSeconds
                                isPlayingPreview = true
                                seek(to: current)
                                startPlayback()
                            }
                        }
                    
                    let hold = LongPressGesture(minimumDuration: 0.5, maximumDistance: 20)
                        .onChanged { _ in
                            if !isPaused {
                                wasPlayingBeforeHold = true
                                isPaused = true
                                pausePlayback()
                            } else {
                                wasPlayingBeforeHold = false
                            }
                        }
                        .onEnded { success in
                            guard success else { return }
                            if wasPlayingBeforeHold {
                                wasPlayingBeforeHold = false
                                isPaused = false
                                let current = previewSeconds
                                isPlayingPreview = true
                                seek(to: current)
                                startPlayback()
                            }
                        }
                    
                    Color.clear
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                        .position(x: g.size.width/2, y: g.size.height/2)
                        .zIndex(999)
                        .simultaneousGesture((ExclusiveGesture(tap, hold)))
                }
                
                
                Group {
                    ZStack(alignment: .bottomLeading) {
                        VStack {
                            
                            // Main content grid (unchanged, except haptics hooks)
                            ZStack {
                                let diameter: CGFloat   = geometry.size.width * 0.20
                                let badgeLift: CGFloat  = diameter/2 + 6
                                let baseRowGap: CGFloat = geometry.size.width * 0.04
                                let columns = Array(repeating: GridItem(.flexible(), spacing: geometry.size.width * 0.04), count: 3)
                                let rowSpacing: CGFloat = baseRowGap + badgeLift
                                
                                LazyVGrid(columns: columns, spacing: rowSpacing) {
                                    ForEach(Array(TapData.keys.sorted().prefix(9)), id: \.self) { key in
                                        let cmndType = TapData[key]?.keys.first ?? 0
                                        let secondaryKeys = TapData[key]?.keys.sorted() ?? []
                                        let diameter: CGFloat = geometry.size.width * 0.2
                                        let overlap: CGFloat = geometry.size.width * 0.03
                                        
                                        if cmndType != 0 && secondaryKeys.count == 2 {
                                            ZStack {
                                                HStack(spacing: -overlap) {
                                                    ForEach(secondaryKeys, id: \.self) { secondaryKey in
                                                        Button(action: {
                                                            if selectedCMND == key && selectedPart == secondaryKey {
                                                                resetSelectionAndStop()
                                                            } else {
                                                                selectedCMND     = key
                                                                selectedCMNDType = cmndType
                                                                selectedPart     = secondaryKey
                                                                switchSelection(to: key, secondary: secondaryKey)
                                                            }
                                                        }) {
                                                            ZStack {
                                                                Circle()
                                                                    .fill((selectedCMND == key && selectedPart == secondaryKey)
                                                                          ? accent.opacity(0.16)
                                                                          : Color.secondary.opacity(0.12))
                                                                    .overlay(
                                                                        Circle().stroke(
                                                                            accent.opacity(selectedCMND == key ? 0.9 : 0.45),
                                                                            lineWidth: 1.2
                                                                        )
                                                                    )
                                                                Text("")
                                                                    .font(.headline.monospacedDigit())
                                                                    .foregroundStyle(.primary)
                                                                    .padding(.horizontal, 10)
                                                            }
                                                            .frame(width: diameter, height: diameter)
                                                            .contentShape(Circle())
                                                            .zIndex((selectedCMND == key && selectedPart == secondaryKey) ? 1 : 0)
                                                        }
                                                    }
                                                }
                                                
                                                Text("#\(key)")
                                                    .font(.caption2).bold()
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.primary.opacity(0.35))
                                                    .foregroundStyle(Color.primary)
                                                    .clipShape(Capsule())
                                                    .offset(y: -diameter/2 - 6)
                                                    .allowsHitTesting(false)
                                            }
                                        } else if cmndType == 0 {
                                            let isSelected = (selectedCMND == key)
                                            
                                            let circleView: some View = Group {
                                                let baseRotation = spiralBaseRotation[key] ?? .zero
                                                if isSelected && showingFullScreenButton == nil {
                                                    TimelineView(.animation) { timeline in
                                                        ZStack {
                                                            SpiralTextInCircle(
                                                                text: commandNames[key]?[0] ?? "",
                                                                accent: accent,
                                                                selected: isSelected,
                                                                startFontSize: UIScreen.main.bounds.width * 0.02
                                                            )
                                                            .rotationEffect(baseRotation)

                                                            if isSelected && showingFullScreenButton == nil {
                                                                TimelineView(.animation) { timeline in
                                                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                                                    let flickerHz: Double = 2.0
                                                                    let phase01 = CGFloat((sin(2 * .pi * flickerHz * t) + 1) * 0.5)
                                                                    let scale = 1.1 + 0.05 * phase01
                                                                    let shownAmp: CGFloat = (Haptics.shared.amp > 0) ? Haptics.shared.amp * scale : 0

                                                                    if shownAmp > 0 {
                                                                        PulsingRing(amplitude: shownAmp)
                                                                            .fill(accent.opacity(0.25), style: FillStyle(eoFill: true))
                                                                    }
                                                                }
                                                                .allowsHitTesting(false)
                                                            }
                                                        }
                                                        .frame(width: diameter, height: diameter)
                                                        .contentShape(Circle())
                                                        .zIndex(isSelected ? 1 : 0)

                                                    }
                                                } else {
                                                    // non-selected: no TimelineView, no ring
                                                    ZStack {
                                                        SpiralTextInCircle(
                                                            text: commandNames[key]?[0] ?? "",
                                                            accent: accent,
                                                            selected: false,
                                                            startFontSize: UIScreen.main.bounds.width * 0.02
                                                        )
                                                        .rotationEffect(baseRotation)
                                                    }
                                                    .frame(width: diameter, height: diameter)
                                                    .contentShape(Circle())
                                                }
                                            }
                                                .zIndex(isSelected ? 1 : 0)
                                            Button {
                                                if selectedCMND == key {
                                                    if !didLongPress {
                                                        selectedCMND = 0
                                                        selectedPart = 0
                                                        selectedCMNDType = 0
                                                        playbackIsPlayed = false
                                                        isPlayingPreview = false
                                                        playbackSpeed = 1.0
                                                        previewInSeconds = 0.0
                                                        previewSeconds = 0.0
                                                        resetSelectionAndStop()
                                                        
                                                    }
                                                } else {
                                                    selectedCMND = key
                                                    selectedCMNDType = 0
                                                    selectedPart = 0
                                                    playbackSpeed = 1.0
                                                    switchSelection(to: key, secondary: 0)
                                                }
                                                
                                                didLongPress = false // reset after tap
                                            } label: {
                                                circleView
                                            }
                                            .buttonStyle(PlainButtonStyle()) // avoid default blue highlight
                                            .simultaneousGesture(
                                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                                    didLongPress = true
                                                    showingFullScreenButton = key
                                                    activeSpiralKey = key

                                                }
                                            )
                                        }
                                        
                                    }
                                }
                            }
                            .offset(y: 60)
                            Spacer()
                        }
                        
                        // Right column with like/report etc. (unchanged, logic preserved)
                        HStack {
                            Spacer()
                            
                            VStack(spacing: 10) {
                                VStack(spacing: 2) {   // ← decrease this number
                                    Button(action: handleLikeTap) {
                                        Group {
                                            if #available(iOS 17.0, *) {
                                                Image(systemName: !isFavouriteModel ? "plus.circle.fill" : "minus.circle.fill")
                                                    .contentTransition(.symbolEffect(.replace))
                                            } else {
                                                ZStack {
                                                    Image(systemName: "plus.circle.fill")
                                                        .opacity(isFavouriteModel ? 0 : 1)
                                                        .scaleEffect(isFavouriteModel ? 0.85 : 1)

                                                    Image(systemName: "minus.circle.fill")
                                                        .opacity(isFavouriteModel ? 1 : 0)
                                                        .scaleEffect(isFavouriteModel ? 1 : 0.85)
                                                }
                                            }
                                        }
                                        .font(.system(size: 45 * 0.6))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(accent)
                                        .frame(width: 45, height: 45)
                                        .clipShape(Circle())
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFavouriteModel)


                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(.isButton)
                                    .disabled(
                                        overLimit ||
                                        Auth.auth().currentUser == nil ||
                                        Auth.auth().currentUser?.isAnonymous == true
                                    )


                                    Text("\(model.rate)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }

                                
                                VStack(spacing: 5) {
                                    Button(action: {
                                        preNavigateStopHapticsThen(onCreatorTap)
                                    }) {
                                        modelIconView(for: model.creator, size: 36)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                
                                Button { reportTarget = model } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 45 * 0.6))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(Color.primary)
                                        .frame(width: 45, height: 45)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.bottom, 35)
                        }
                    }
                }

                
                // Progress bar overlay
                VStack {
                    Spacer()
                    GeometryReader { barGeo in
                        let barWidth = barGeo.size.width
                        let barHeight: CGFloat = 6
                        let thumbSize: CGFloat = 14
                        let xPos = CGFloat(progress) * barWidth
                        
                        let scrubDrag = DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isScrubbing {
                                    isScrubbing = true
                                    wasPlayingBeforeScrub = isPlayingPreview && !isPaused
                                    pausePlayback()
                                    HapticsManager.shared.prewarm()
                                    HapticsManager.shared.playBatchPreview(for: hOwner, [],
                                                                           intensity: 0.7, sharpness: 0.6, duration: 0.03)
                                    
                                    lastScrubEvent = nil
                                    scrubPreviewCooldownUntil = 0
                                    
                                    // start a fresh session
                                    scrub.anchorT = previewSeconds
                                    scrub.lastT   = previewSeconds
                                    scrub.cumulative = 0
                                }
                                
                                let w = max(1, barWidth)
                                let x = clamped(value.location.x, min: 0, max: w)
                                let newTime = Double(x / w) * previewInSeconds
                                
                                let now = value.time.timeIntervalSince1970
                                if let last = lastScrubEvent {
                                    let dt = max(1e-3, now - last.t)
                                    let dLogical = abs(newTime - last.logical)
                                    let rate = dLogical / dt
                                    
                                    // update session cumulative distance from anchor
                                    scrub.cumulative += abs(newTime - scrub.lastT)
                                    scrub.lastT = newTime
                                    
                                    // distance-proportional scale
                                    let pScale = previewScale(for: scrub.cumulative, total: previewInSeconds)
                                    
                                    
                                    fireCompressedPreviewAcross(oldT: last.logical, newT: newTime, scale: pScale)
                                    
                                    
                                    
                                } else {
                                    scrub.lastT = newTime
                                }
                                
                                // always move visual playhead
                                seek(to: newTime, silent: true)
                                
                                lastScrubEvent = (t: now, logical: newTime)
                            }
                            .onEnded { value in
                                let w = max(1, barWidth)
                                let x = clamped(value.location.x, min: 0, max: w)
                                let newTime = Double(x / w) * previewInSeconds
                                
                                // final silent seek
                                seek(to: newTime, silent: true)
                                
                                // Give a decisive “landing” with high scale on the last bucket for satisfaction
                                let pScale = max(0.75, previewScale(for: scrub.cumulative, total: previewInSeconds))
                                fireCompressedPreviewAcross(oldT: scrub.lastT, newT: newTime, scale: pScale)
                                fireScrubbedBucketNearest(oldT: scrub.lastT, newT: newTime) // your nice thunk-on-stop
                                
                                if wasPlayingBeforeScrub && !isPaused {
                                    isPlayingPreview = true
                                    startPlayback()
                                }
                                
                                isScrubbing = false
                                wasPlayingBeforeScrub = false
                                lastScrubEvent = nil
                                scrubPreviewCooldownUntil = 0
                            }
                        
                        
                        ZStack(alignment: .leading) {
                            // Track
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: barHeight)
                            
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: xPos, height: barHeight)
                                .animation(.linear(duration: 0.1), value: previewSeconds)
                            // Thumb
                            Circle()
                                .fill(Color.primary)
                                .frame(width: thumbSize, height: thumbSize)
                                .shadow(radius: 1, y: 1)
                                .offset(x: clamped(xPos - thumbSize/2, min: 0, max: barWidth - thumbSize),
                                        y: -(thumbSize - barHeight)/2)
                                .opacity(isScrubbing ? 1.0 : 0.0)
                        }
                        .contentShape(Rectangle()) // make whole bar draggable
                        .frame(height: max(44, thumbSize)) // finger-friendly hit area
                        .highPriorityGesture(scrubDrag) // <- wins over parent ScrollView
                        .accessibilityLabel(Text("Playback position"))
                        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
                    }
                    .frame(height: 44) // reserve space for the GeometryReader
                }
                
                if isSpeedHeld {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Text("2×")
                                .font(.footnote.weight(.semibold))
                            
                            Image(systemName: "chevron.forward.2")
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                        )
                        .padding(.bottom, 16)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                
            }
            .blur(radius: showingFullScreenButton == nil ? 0 : 8)   // 👈 gentle blur
            .opacity(showingFullScreenButton == nil ? 1.0 : 0.5)   // 👈 fade behind
            .allowsHitTesting(showingFullScreenButton == nil)
            .onChange(of: sharedData.publishedFavModels) { newValues in
                isFavouriteModel = sharedData.publishedFavModels.keys.contains(model.name)
            }
            .onChange(of: isActive) { active in
                if active {
                    onAppearSetup()           // or beginLoadingForCurrentModel()
                    HapticsManager.shared.activate(for: hOwner)
                } else {
                    hardResetOnLoseFocus()
                    HapticsManager.shared.deactivate(for: hOwner)
                }
            }

            .overlay(alignment: .bottom) {
                if let target = reportTarget {
                    RollActionSheet(
                        model: target,
                        modelID: modelID,
                        accent: selectedAccent.color,
                        isInModelCard: false,
                        onReportModel: {
                            onReport()
                            reportTarget = nil
                        },
                        onCancel: {
                            reportTarget = nil
                        },
                        onModelOpen: {
                            preNavigateStopHapticsThen(onTap)
                            reportTarget = nil
                        }
                    )
                    .zIndex(100)
                }
            }
            .overlay(
                ZStack {
                    // TOP-RIGHT
                    speedPressOverlay(
                        alignment: .topTrailing,
                        trailing: 8,
                        top: 8
                    )

                    speedPressOverlay(
                        alignment: .bottomLeading,
                        leading: 8,
                        bottom: 8,
                        yOffset: -40    // 👈 lift by ~40pts (tweak as needed)
                    )

                    if showLoading {
                        ZStack {
                            
                            VStack(spacing: 12) {
                                if selectedDisplayMethod == .sphere {
                                    RotatingSphereView()
                                        .frame(
                                            width: UIScreen.main.bounds.width * 0.8,
                                            height: UIScreen.main.bounds.width * 0.8
                                        )
                                } else {
                                    PlainGridAnimationView()
                                        .frame(
                                            width: UIScreen.main.bounds.width * 0.8,
                                            height: UIScreen.main.bounds.width * 0.8
                                        )
                                }
                            }
                            .padding(24)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 10)
                        }
                        .allowsHitTesting(true)
                    }
                    if isPaused {
                        Button {
                            isPaused = false
                            let t = previewSeconds
                            isPlayingPreview = true
                            seek(to: t)
                            startPlayback()
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(.primary)
                                .shadow(radius: 10)
                                .padding(24)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .zIndex(1000)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel(Text("Resume"))
                    }
                }
            )

            .safeAreaInset(edge: .top) {
                VStack {
                    HStack {
                        Menu {
                            Button("mix".localized()) { onFilterSelected("mix".localized()) }
                            Button("famous".localized()) { onFilterSelected("famous".localized()) }
                            Button("personalised".localized()) { onFilterSelected("personalised".localized()) }
                                .disabled(true)
                        } label: {
                            HStack(spacing: 4) {
                                Text(!selectedFilter.isEmpty ? selectedFilter : "famous".localized())
                                    .font(.headline)
                                    .foregroundStyle(accent.opacity(0.7))
                                Image(systemName: "chevron.right")
                                    .font(.headline)
                                    .foregroundStyle(accent.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .padding(.leading, 8)
                        
                        Spacer()
                        
                        Button {
                            resetSelectionAndStop()
                            onChevronUp()
                        } label: {
                            Image(systemName: "chevron.up")
                                .resizable()
                                .scaledToFit()
                                .frame(width: H * 0.03, height: H * 0.03)   // ≈ 3% of screen height
                                .foregroundStyle(accent)
                                .padding(H * 0.01)                          // ≈ 1% of screen height
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 4)
                    
                    let fullDescription = model.description
                    HStack(alignment: .top, spacing: 12) {
                        // LEFT COLUMN: image on top, name below (like ModelItemView)
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                if let url = sharedData.publishedModelImageURLs[model.name] {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                                        @unknown default:
                                            RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                                        }
                                    }
                                    .onAppear { ensurePublishedAccentIfNeeded() }
                                } else {
                                    RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                                }
                            }
                            .frame(width: UIScreen.main.bounds.height * 0.15,
                                   height: UIScreen.main.bounds.height * 0.15)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        (sharedData.publishedAccentColors[model.name] ?? selectedAccent.color).opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                        
                            
                        }
                        .frame(width: UIScreen.main.bounds.height * 0.15) // keep the left column
                        .contentShape(Rectangle()) // makes the whole VStack tappable
                        .onTapGesture {
                            preNavigateStopHapticsThen(onTap)
                        }
                        
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(displayedText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.1, alignment: .leading)   // 👈 key line
                        .layoutPriority(1)                                    // 👈 helps HStack give this view space
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)       // optional but nice
                    .padding(.horizontal, 16)
                    .padding(.top, UIScreen.main.bounds.height * 0.05)   // 👈 add extra spacing from the menu
                    
                }
            }
        }
        .overlay {
            if let key = showingFullScreenButton {
                
                let accent = sharedData.publishedAccentColors[model.name] ?? selectedAccent.color
                ZStack {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle()) // ensure the whole area is tappable
                        .highPriorityGesture(       // win over other gestures
                            TapGesture().onEnded { showingFullScreenButton = nil
                                activeSpiralKey = nil
                                deviceBaseYaw = nil
                                deviceYawRotation = .zero
                            }
                        )
                    TimelineView(.animation) { timeline in
                        GeometryReader { geo in
                            // Center point in the chosen coordinate space
                            let center = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                            
                            let key = activeSpiralKey ?? 0      // or however you get the current key
                            let baseRotation = spiralBaseRotation[key] ?? .zero
                            
                            ZStack {
                                // Spiral that rotates with the drag
                                SpiralTextInCircle(
                                    text: commandNames[key]?[0] ?? "",
                                    accent: accent
                                )
                                .rotationEffect(baseRotation + spiralDragRotation + deviceYawRotation)
                                .contentShape(Circle())
                                
                                
                                
                                // Pulsing ring
                                let t = timeline.date.timeIntervalSinceReferenceDate
                                let flickerHz: Double = 2.0
                                let phase01 = CGFloat((sin(2 * .pi * flickerHz * t) + 1) * 0.5)
                                let scale = 1.3 + 0.05 * phase01
                                let shownAmp: CGFloat = (Haptics.shared.amp > 0) ? Haptics.shared.amp * scale : 0

                                
                                if shownAmp > 0 {
                                    PulsingRing(amplitude: shownAmp)
                                        .fill(accent.opacity(0.25), style: FillStyle(eoFill: true))
                                        .opacity(1)
                                        .contentShape(Circle())
                                }
                            }
                            .frame(
                                width: UIScreen.main.bounds.width * 0.7,
                                height: UIScreen.main.bounds.width * 0.7
                            )
                            // ⬇️ This frame makes the circle sit in the center of the GeometryReader
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let dx = value.location.x - center.x
                                        let dy = value.location.y - center.y
                                        let currentAngle = Angle(radians: Double(atan2(dy, dx)))

                                        if spiralDragStartAngle == nil {
                                            spiralDragStartAngle = currentAngle
                                        }

                                        if let start = spiralDragStartAngle {
                                            let delta = currentAngle.radians - start.radians
                                            spiralDragRotation = Angle(radians: delta)
                                        }
                                    }
                                    .onEnded { _ in
                                        guard let activeKey = activeSpiralKey else { return }

                                        let base = spiralBaseRotation[activeKey] ?? .zero
                                        let newBase = base + spiralDragRotation

                                        spiralBaseRotation[activeKey] = newBase
                                        spiralDragRotation = .zero
                                        spiralDragStartAngle = nil
                                    }
                            )
                        
                            
                        }
                        .zIndex(1)
                        
                    }
                    
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) // expand overlay
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .alert("cooldown".localized(), isPresented: $showLikeCooldownAlert) {
            Button("ok".localized(), role: .cancel) { }
        } message: { Text(likeCooldownMessage) }
            .onAppear {

            
                displayedText = model.description
                
                
                if let key = sharedData.GlobalModelsData.first(where: { $0.value == model.name })?.key {
                    modelID = key
                }
                AppDelegate.shared?.orientationLock = .portrait
                onAppearSetup()
                if isActive { HapticsManager.shared.activate(for: hOwner) }
                deviceBaseYaw = nil
                deviceYawRotation = .zero

        
            }

            .onChange(of: isActive) { active in
                if active {
                    HapticsManager.shared.activate(for: hOwner)
                } else {
                    // clean local UI state
                    selectedCMND = 0
                    selectedPart = 0
                    selectedCMNDType = 0
                    playbackIsPlayed = false
                    isPlayingPreview = false
                    playbackSpeed = 1.0
                    previewInSeconds = 0.0
                    previewSeconds = 0.0
                    
                    hardResetOnLoseFocus()
                    HapticsManager.shared.deactivate(for: hOwner)
                    
                    // Optional: only if you truly want to hard-stop all in-flight haptics
                    // HapticsManager.shared.cancelAll()
                }
            }
        
            .onDisappear {
                
                AppDelegate.shared?.orientationLock = .all
                selectedCMND = 0
                selectedPart = 0
                selectedCMNDType = 0
                playbackIsPlayed = false
                isPlayingPreview = false
                playbackSpeed = 1.0
                previewInSeconds = 0.0
                previewSeconds = 0.0
                
                hardResetOnLoseFocus()
                HapticsManager.shared.deactivate(for: hOwner)
            }
            .onChange(of: deviceMotion.yaw) { newYaw in
                // Only care while the overlay is showing
                guard showingFullScreenButton != nil else {
                    deviceBaseYaw = nil
                    deviceYawRotation = .zero
                    return
                }
                
                if deviceBaseYaw == nil {
                    // first time we see yaw this session: remember it
                    deviceBaseYaw = newYaw
                }
                
                let base = deviceBaseYaw ?? newYaw
                let delta = newYaw - base          // radians
                deviceYawRotation = Angle(radians: delta)
            }
    
    }



    @ViewBuilder
    private func speedPressOverlay(
        alignment: Alignment,
        leading: CGFloat? = nil,
        trailing: CGFloat? = nil,
        top: CGFloat? = nil,
        bottom: CGFloat? = nil,
        yOffset: CGFloat = 0
    ) -> some View {

        // How far user must drag UP to lock (tune)
        let lockDragThreshold: CGFloat = 18

        GeometryReader { g in
            Color.clear
                .frame(
                    width: max(44, g.size.width * 0.12),
                    height: max(44, g.size.height * 0.15)
                )
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(.leading, leading ?? 0)
                .padding(.trailing, trailing ?? 0)
                .padding(.top, top ?? 0)
                .padding(.bottom, bottom ?? 0)
                .offset(y: yOffset)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($speedPressing) { _, state, _ in
                            state = true
                        }
                        .onChanged { value in
                            // First touch-down
                            if speedPressStart == nil {
                                speedPressStart = Date()
                                speedLongHold = false
                                speedThresholdWorkItem?.cancel()

                                Task { @MainActor in enable2x() }

                                let wi = DispatchWorkItem {
                                    Task { @MainActor in speedLongHold = true }
                                }
                                speedThresholdWorkItem = wi
                                DispatchQueue.main.asyncAfter(
                                    deadline: .now() + latchThreshold,
                                    execute: wi
                                )
                            }

                            // ✅ Require upward drag to lock
                            if !speedLatched {
                                let draggedUp = -value.translation.height // up = positive
                                if draggedUp >= lockDragThreshold {
                                    speedLatched = true
                                    // optional: haptic / toast here
                                }
                            }
                        }
                )
                .onChange(of: speedPressing) { isDown in
                    if isDown {
                        speedWasPressing = true
                        return
                    }

                    guard speedWasPressing else { return }
                    speedWasPressing = false

                    speedThresholdWorkItem?.cancel()
                    speedPressStart = nil

                    // ✅ On release:
                    // - if locked, keep 2× active (do nothing)
                    // - if not locked, disable 2×
                    if !speedLatched {
                        Task { @MainActor in disable2x() }
                    }
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if speedBoostActive {
                            speedLatched = false
                            Task { @MainActor in disable2x() }
                        }
                    }
                )
        }
    }


    @inline(__always)
    private func fireScrubbedBucketNearest(oldT: Double, newT: Double) {
        guard previewInSeconds > 0 else { return }
        ensureOrderedKeys()

        // pick the bucket closest to the finger, direction-aware
        let idx: Int = {
            if newT >= oldT {
                return min(max(0, indexAfter(time: newT) - 1), orderedKeys.count - 1)
            } else {
                return min(max(0, indexAfter(time: newT)),     orderedKeys.count - 1)
            }
        }()

        let key = orderedKeys[idx]
        guard let perList = playbackTapEntries[key] else { return }

        for listIndex in perList.keys.sorted() {
            if let entries = perList[listIndex], !entries.isEmpty {
                HapticsManager.shared.playExactPreview(for: hOwner, entries)
            }
        }
    }

    
    private func setSpeedBoost(active: Bool) {
        // optional: hide UI during boost
        uiHidden = active

        let newSpeed = active ? 2.0 : 1.0
        guard newSpeed != playbackSpeed else { return }
        playbackSpeed = newSpeed

        let current = previewSeconds
        if isPlayingPreview {
            pausePlayback()
            seek(to: current)
            startPlayback()
        }
    }
    @MainActor
    private func ensureDummyImageIfNeeded(for modelName: String) async {
        // Already have URL? done.
        if sharedData.publishedModelImageURLs[modelName] != nil { return }
        guard Auth.auth().currentUser?.email != nil else { return }

        // --- Custom rule for Nimbus ---
        let choice: String
        if modelName == "Nimbus" {
            choice = "ModelImage_1.jpg"
            print("Using fixed dummy image for Nimbus → \(choice)")
        } else {
            // Normal random selection
            let allChoices = (0...50).map { "ModelImage_\($0).jpg" }
            let unused = allChoices.filter { !sharedData.alreadyUsed.contains($0) }

            guard let randomChoice = unused.randomElement() else {
                print("All dummy images used — placeholder for \(modelName)")
                return
            }
            choice = randomChoice
        }

        // Reserve to avoid duplicates during concurrent loads
        sharedData.alreadyUsed.append(choice)

        let ref = Storage.storage().reference()
            .child("DummyModelImages")
            .child(choice)

        // Wrap Firebase callback in async/await
        do {
            let url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                ref.downloadURL { url, error in
                    if let error = error { cont.resume(throwing: error); return }
                    guard let url = url else {
                        cont.resume(throwing: URLError(.badURL)); return
                    }
                    cont.resume(returning: url)
                }
            }

            // Publish URL immediately so AsyncImage can show it
            await MainActor.run {
                sharedData.publishedModelImageURLs[modelName] = url
                print("✅ Successfully fetched image for \(modelName): \(choice)")

            }

            // Optional accent extraction
            Task.detached {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            setAccent(from: uiImage)
                        }
                    }
                } catch {
                    print("⚠️ Failed to load image data for accent color (\(modelName)): \(error.localizedDescription)")
                }
            
            }
        } catch {
            // Roll back reservation so it can be retried later
            if let i = sharedData.alreadyUsed.firstIndex(of: choice) {
                sharedData.alreadyUsed.remove(at: i)
            }
            print("Dummy image URL error for \(modelName): \(error.localizedDescription)")
        }
    }

    func detectedLanguageCode(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    func shouldTranslate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= 3 else { return false }
        guard trimmed.range(of: #"\p{L}"#, options: .regularExpression) != nil else {
            return false
        }

        return true
    }



    @MainActor
    private func onAppearSetup() {
        if isActive {
            ensurePublishedAccentIfPreviewing()
            
            
            if
                let user = Auth.auth().currentUser,
                !user.isAnonymous
            {

                userID = user.uid

                // Check if model.name exists as a key in the dictionary
                if sharedData.publishedFavModels.keys.contains(model.name) {
                    isFavouriteModel = true
                } else {
                    isFavouriteModel = false
                }


            }
            
            if let name = sharedData.ALLUSERNAMES[model.creator]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                userName = name
                UserDefaults.standard.setValue(userName, forKey: "GoogleUserName")
            }
            
            loadingWorkItem?.cancel()
            showLoading = false
            let wi = DispatchWorkItem {
                DispatchQueue.main.async { if !model.justCreated { showLoading = true } }
            }
            loadingWorkItem = wi
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: wi)
            
            beginLoadingForCurrentModel()
        } else {
            resetSelectionAndStop()
        }
    }
    private func beginLoadingForCurrentModel() {
        loadGen &+= 1
        let myGen = loadGen
        
        publishFunctionality.fetchConfigForPublishedModel(modelName: model.name) { result in
            Task { @MainActor in
                guard myGen == loadGen else { return }
                switch result {
                case .success(let payload):
                    TapData = payload.taps
                    commandNames = payload.names


                    
                    if TapData[0]?[999] != nil { TapData[0]?.removeValue(forKey: 999) }
                    
                    loadingWorkItem?.cancel()
                    showLoading = false
                    
                    if let firstPrimary = TapData.keys.filter({ $0 > 0 }).sorted().first,
                       let inner = TapData[firstPrimary], !inner.isEmpty {
                        
                        if ScrollsAutoplay {
                            selectedCMND = firstPrimary
                            selectedPart = inner.keys.sorted().first ?? 0
                            selectedCMNDType = inner.keys.first ?? 0
                        }
                        
                        if let tapEntries = TapData[selectedCMND]?[selectedCMNDType] {
                            selectedEntryIndices = Set(tapEntries.map { $0.key })
                        }
                        
                        guard TapData[selectedCMND]?[selectedCMNDType] != nil,
                              !selectedEntryIndices.isEmpty else { return }
                        
                        isPlayingPreview = true
                        
                        // ✅ guard the delayed start
                        let delayedGen = myGen
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            guard delayedGen == loadGen, isActive else { return }
                            buildPlayback(for: selectedCMND, secondaryKey: selectedPart)
                        }
                    } else {
                        selectedCMND = 0
                        selectedPart = 0
                        selectedCMNDType = 0
                        showTAPSModificationLine = false
                    }
                    
                case .failure(let error):
                    print("❌ Fetch failed: \(error.localizedDescription)")
                }
            }
        }

    }
    func bucketDuration(for entries: [TapEntry]) -> Double {
        let steps = entries.filter { $0.value > 0 }
        let nonDelay = steps.filter { $0.entryType.lowercased() != "delay" }

        if nonDelay.count > 1 {
            // parallel
            return nonDelay.map(\.value).max() ?? 0
        } else {
            // sequence: delays + one motor step(s)
            return steps.reduce(0) { $0 + $1.value }
        }
    }

    // MARK: - Gestures / Toggles

    private func toggleMinimalMode(throttled: Bool = true, hide: Bool) {
        if throttled {
            let now = Date()
            guard now.timeIntervalSince(lastSpeedToggle) > 0.15 else { return }
            lastSpeedToggle = now
        }
        uiHidden = hide
        playbackSpeed = uiHidden ? 2.0 : 1.0

        let current = previewSeconds
        if isPlayingPreview {
            pausePlayback()
            seek(to: current)
            startPlayback()
        }
    }

    // MARK: - Favourite

    @MainActor
    private func performFavouriteToggle() {
        processingIsFavourite = true

        if !isFavouriteModel {
            personalModelsFunctions.upsertFavouriteModel(
                named: model.name,
                creator: model.creator,
                createdAt: model.publishDate,
                description: model.description,
                taps: TapData,
                commandNames: commandNames
            ) { result in
                switch result {
                case .success:
                    publishFunctionality.increaseModelRate(publishName: model.name) { _ in }
                    isFavouriteModel = true
                    processingIsFavourite = false
                    
                    model.rate += 1

                    if model.creator != userID {
                        publishFunctionality.notifyAboutLikingModel(
                            recepient_uid: model.creator,
                            author_uid: userID,
                            model_name: model.name,
                            author_name: userName
                        ) { _ in }
                    }

                case .failure:
                    isFavouriteModel = false
                    processingIsFavourite = false
                }
            }
        } else {
            personalModelsFunctions.deleteFavouriteModel(named: model.name) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        publishFunctionality.decreaseModelRate(publishName: model.name) { _ in }
                        model.rate -= 1
                        processingIsFavourite = false
                        sharedData.publishedFavModels.removeValue(forKey: model.name)
                        isFavouriteModel = false
                    case .failure:
                        processingIsFavourite = false
                    }
                }
            }
        }
    }

    private func handleLikeTap() {
        
        guard !processingIsFavourite else { return }
        let now = Date().timeIntervalSince1970

        if likingCooldownUntil > now {
            showLikeCooldown(remaining: likingCooldownUntil - now); return
        }
        if likingCooldownUntil != 0, likingCooldownUntil <= now { likingCooldownUntil = 0 }

        if now - likingLastTap > likeSpamWindow { likingSpamCount = 0 }
        likingSpamCount += 1
        likingLastTap = now

        if likingSpamCount >= likeSpamThreshold {
            likingCooldownUntil = now + likeCooldownWindow
            likingSpamCount = 0
            showLikeCooldown(remaining: likeCooldownWindow, justStarted: true)
            return
        }
        
        performFavouriteToggle()
    }

    private func showLikeCooldown(remaining: TimeInterval, justStarted: Bool = false) {
        let minutesLeft = Int(ceil(max(remaining, 0) / 60))
        let leftText = minutesLeft == 1 ? "1_minute".localized() : "\(minutesLeft) \("minutes".localized())"
        likeCooldownMessage = "\("cooldown_30_minutes".localized()) \(leftText) \("left".localized())."
        showLikeCooldownAlert = true
    }

    // MARK: - Playback building
    private func buildPlayback(for primary: Int, secondaryKey: Int) {
        guard let perSecondary = TapData[primary],
              var entries = perSecondary[secondaryKey] else {
            bucketDurations = [:]
            playbackTapEntries = [:]
            previewInSeconds = 0
            previewSeconds = 0
            return
        }

        // Optional but recommended: stable order inside groups/singles
        entries.sort { $0.key < $1.key }   // use your stable field

        bucketDurations = [:]
        playbackTapEntries = [:]

        var playback: [Double: [Int: [TapEntry]]] = [:]
        var cursor: Double = 0.0
        var totalTimeline: Double = 0.0
        let listIndex = 0

        func snap(_ t: Double) -> Double {
            // snap to 1ms to avoid tiny FP differences
            (t * 1000).rounded() / 1000
        }

        func append(at startTime: Double, listIndex: Int, entries: [TapEntry]) {
            var perIndex = playback[startTime] ?? [:]
            var arr = perIndex[listIndex] ?? []
            arr.append(contentsOf: entries)
            perIndex[listIndex] = arr
            playback[startTime] = perIndex

            let d = bucketDuration(for: entries)
            bucketDurations[startTime] = max(bucketDurations[startTime] ?? 0, d)

        }

        let groups = Dictionary(grouping: entries, by: \.groupId)

        // 1) Process grouped items in a **stable** gid order
        let orderedGIDs = groups.keys.filter { $0 != 0 }.sorted()
        for gid in orderedGIDs {
            // keep a stable order inside the group too
            let grouped = (groups[gid] ?? []).sorted { $0.key < $1.key }
            let groupDur = bucketDuration(for: grouped)
            let start = snap(cursor)
            append(at: start, listIndex: listIndex, entries: grouped)
            cursor = snap(cursor + groupDur)
            totalTimeline += groupDur
        }

        // 2) Singles in stable order
        if var singles = groups[0] {
            singles.sort { $0.key < $1.key }
            for e in singles {
                let start = snap(cursor)
                append(at: start, listIndex: listIndex, entries: [e])
                cursor = snap(cursor + e.value)
                totalTimeline += e.value
            }
        }

        playbackTapEntries = playback
        previewInSeconds = totalTimeline
        previewSeconds = 0.0

        bumpRowGen()                               // row run token
        HapticsManager.shared.prewarm()            // <- make sure engine is up

        // Give Core Haptics a runloop tick before we fire t=0
        DispatchQueue.main.async {                 // one UI tick (~0–16ms)
            self.startPlayback(rowToken: self.rowPlayGen)
        }
    }

    private func switchSelection(to primary: Int, secondary: Int) {
        // kill old run (no engine shutdown)
        bumpRowGen()
        isPlayingPreview = false
        playbackTask?.cancel()
        playbackTask = nil
        HapticsManager.shared.softStop()

        // reset timeline indices
        previewSeconds = 0
        orderedKeys.removeAll()
        nextBucketIndex = 0

        // rebuild + start
        buildPlayback(for: primary, secondaryKey: secondary)
    }


    // MARK: - Timeline helpers

    private func resetBucketSchedule() {
        orderedKeys = []
        nextBucketIndex = 0
    }

    private func ensureOrderedKeys() {
        if orderedKeys.isEmpty { orderedKeys = playbackTapEntries.keys.sorted() }
    }

    private func indexAfter(time: Double) -> Int {
        ensureOrderedKeys()
        let t = time + epsilon
        var lo = 0, hi = orderedKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if orderedKeys[mid] <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func nextIndexFor(time: Double) -> Int {
        ensureOrderedKeys()
        let ub = indexAfter(time: time)
        let i  = max(0, ub - 1)
        if i < orderedKeys.count {
            let k = orderedKeys[i]
            let dur = bucketDurations[k] ?? 0
            if time + epsilon < k + dur { return i }
        }
        return ub
    }

    private func seek(to time: Double, silent: Bool = false) {
        if !silent {
            pausePlayback() // this calls softStop()
        }
        previewSeconds = min(max(0, time), previewInSeconds)
        ensureOrderedKeys()
        nextBucketIndex = nextIndexFor(time: previewSeconds)
    }


    private func startPlayback(rowToken: UInt64? = nil) {
        guard isActive else { return }
        let token = rowToken ?? rowPlayGen

        // Before: if previewSeconds >= previewInSeconds { previewSeconds = 0 }
        // After: clamp to just-before-end so we keep the drop point
        if previewSeconds > max(0, previewInSeconds - epsilon) {
            previewSeconds = max(0, previewInSeconds - epsilon)
        }

        resetBucketSchedule()
        ensureOrderedKeys()
        nextBucketIndex = nextIndexFor(time: previewSeconds)

        isPlayingPreview = true
        fireDueBucketsOnce(at: previewSeconds, token: token)

        playbackSpeed = uiHidden ? 2.0 : 1.0

        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, isActive, token == rowPlayGen, previewSeconds < previewInSeconds {
                try? await Task.sleep(nanoseconds: 50_000_000)
                previewSeconds += 0.05 * playbackSpeed
                fireDueBucketsOnce(at: previewSeconds, token: token)
            }
            isPlayingPreview = false
            HapticsManager.shared.stop()             // <- was .stop()
        }
    }

    private func fireDueBucketsOnce(at time: Double, token: UInt64) {
        guard isActive, token == rowPlayGen else { return }
        while nextBucketIndex < orderedKeys.count,
              orderedKeys[nextBucketIndex] <= time + epsilon {
            let t = orderedKeys[nextBucketIndex]
            if let perList = playbackTapEntries[t] {
                for listIndex in perList.keys.sorted() {
                    let entries = perList[listIndex] ?? []
                    guard !entries.isEmpty else { continue }
                    let nonDelayCount = entries.filter { $0.entryType != "delay" && $0.value > 0 }.count
                    
                    let dbg = entries.map { "\($0.entryType):\($0.value)" }.joined(separator: ", ")


                    if nonDelayCount > 1 {
                        HapticsManager.shared.playBatch(for: hOwner, entries)
                    } else {
                        HapticsManager.shared.playSequence(for: hOwner, entries)
                    }
                }
            }
            nextBucketIndex += 1
        }
    }




    private func pausePlayback() {
        isPlayingPreview = false
        playbackTask?.cancel()
        playbackTask = nil
        HapticsManager.shared.softStop()          // <- was .stop()
    }

    @inline(__always)
    private func resetSelectionAndStop() {
        selectedCMND = 0
        selectedPart = 0
        selectedCMNDType = 0
        playbackIsPlayed = false
        isPlayingPreview = false
        playbackSpeed = 1.0
        previewInSeconds = 0.0
        previewSeconds = 0.0
        HapticsManager.shared.softStop()          // <- was .stop()

    }


    @MainActor
    private func teardownModel() {
        isPlayingPreview = false
        playbackTask?.cancel()
        playbackTask = nil
        previewInSeconds = 0
        previewSeconds   = 0
        HapticsManager.shared.stop()
        selectedCMND = 0
        selectedPart = 0
        selectedCMNDType = 0
        playbackSpeed = 1.0
    }

    // MARK: - Misc UI

    @ViewBuilder
    private func modelIconView(for modelId: String, size: CGFloat = 36) -> some View {
        if let url = iconURLCache[modelId] {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Circle().fill(Color.gray.opacity(0.2))
                case .success(let img):
                    img.resizable().scaledToFill().clipShape(Circle())
                case .failure:
                    ZStack {
                        Circle()
                            .fill(
                                (selectedAppearance == .system &&
                                 colorScheme == .light &&
                                 selectedAccent == .default)
                                ? .regularMaterial
                                : .ultraThinMaterial
                            )

                        Image(systemName: "person.fill")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                @unknown default: EmptyView()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        (selectedAppearance == .system &&
                         colorScheme == .light &&
                         selectedAccent == .default)
                        ? .regularMaterial
                        : .ultraThinMaterial
                    )

                Image(systemName: "person.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }
    @inline(__always)
    private func preNavigateStopHapticsThen(_ action: @escaping () -> Void, delay: TimeInterval = 0.2) {
        // 1) Stop local playback state immediately
        isPlayingPreview = false
        playbackTask?.cancel()
        playbackTask = nil
        previewInSeconds = 0
        previewSeconds   = 0
        selectedCMND = 0
        selectedPart = 0
        selectedCMNDType = 0
        playbackSpeed = 1.0

        // 2) Hard-stop Core Haptics (kills any in-flight players)
        HapticsManager.shared.cancelAll()

        // 3) Wait, then hand control to the caller
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }


                    
}

@inline(__always)
func stopHapticsEverywhere(after seconds: Double = 0) {
    Task.detached(priority: .high) {
        if seconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        HapticsManager.shared.cancelAll()
    }
}
