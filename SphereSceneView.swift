






import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Foundation
import CoreHaptics
import SceneKit
import simd
import UIKit





struct LineBuild {
    let node: SCNNode
    let segments: [SCNNode]
    let segmentLengths: [Float]
}
// MARK: - Reusable Connection Material

private struct ConnectionMaterialTemplate {
    /// Build a base material configured for thin lines we animate via color.
    static func make(opacity: CGFloat,
                     respectsDepth: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.readsFromDepthBuffer = respectsDepth
        m.writesToDepthBuffer = false
        m.diffuse.contents  = UIColor.clear   // start invisible; animator drives color
        m.emission.contents = UIColor.clear
        m.transparency = opacity
        m.blendMode = .alpha
        return m
    }

    /// Clone an instance so each segment can animate independently
    static func clone(from template: SCNMaterial) -> SCNMaterial {
        (template.copy() as? SCNMaterial) ?? template
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = self.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.traits: [
                UIFontDescriptor.TraitKey.weight: weight
            ]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

enum Palette {
    static let cyan  = UIColor(red: 0.09, green: 0.80, blue: 0.96, alpha: 1)  
    static let blue  = UIColor(red: 0.00, green: 0.58, blue: 0.87, alpha: 1)  
    static let navy  = UIColor(red: 0.07, green: 0.12, blue: 0.27, alpha: 1)  
    static let grid: UIColor = {
        if #available(iOS 13.0, *) {
            return UIColor { tc in
                if tc.userInterfaceStyle == .dark {
                    
                    return UIColor.white.withAlphaComponent(0.22)
                } else {
                    
                    let alpha: CGFloat = (tc.accessibilityContrast == .high) ? 0.85 : 0.65
                    return UIColor.black.withAlphaComponent(alpha)
                }
            }
        } else {
            return UIColor.black.withAlphaComponent(0.32)
        }
    }()
    static let darkGrid = UIColor.black
}
// Put this near SphereSceneView (file-level or inside an extension)
@inline(__always)
func effectiveStyle(
    selectedAppearance: AppearanceOption,
    systemStyle: UIUserInterfaceStyle
) -> UIUserInterfaceStyle {
    switch selectedAppearance {
    case .system: return systemStyle
    case .light:  return .light
    case .dark:   return .dark
    }
}



enum SpherePreloader {
    static func warmUp() {
        DispatchQueue.global(qos: .userInitiated).async {            
            // Optionally prewarm SceneKit pipeline
            let scene = SCNScene()
            let view = SCNView(frame: .zero)
            view.scene = scene
            view.prepare(scene, shouldAbortBlock: nil)
        }
    }
}

private enum SymbolImageCache {
    // Tune once; all icons share the same config
    private static let config = UIImage.SymbolConfiguration(pointSize: 512, weight: .bold)

    // Preload the symbols you actually use
    private static let preloaded: [String: UIImage] = {
        func load(_ name: String) -> UIImage? {
            if let img = UIImage(systemName: name, withConfiguration: config) {
                return img.withRenderingMode(.alwaysOriginal)
            }
            return UIImage(systemName: name)?.withRenderingMode(.alwaysOriginal)
        }
        let names = [
            "xmark.circle.fill",
            "eye.circle.fill",
            "play.circle.fill"
        ]
        var dict: [String: UIImage] = [:]
        for n in names { if let img = load(n) { dict[n] = img } }
        return dict
    }()

    /// Returns a cached image if preloaded; lazily creates & stores unknown names once.
    static func image(named name: String) -> UIImage? {
        if let img = preloaded[name] { return img }
        // Fallback for any future symbol you might pass in:
        if let img = UIImage(systemName: name, withConfiguration: config)?.withRenderingMode(.alwaysOriginal) {
            // NOTE: If you want strict singletons, elevate `preloaded` to a mutable store.
            return img
        }
        return UIImage(systemName: name)?.withRenderingMode(.alwaysOriginal)
    }
}




struct SphereSceneView: UIViewRepresentable {
    @Binding var isReady: Bool
    let largestShellValue: Int
    let rateForConnections: [Int: [Int: Double]]
    let orderForConnections: [Int: [Int: Int]]
    let GlobalModelsData: [Int: String]
    @Binding var selectedGroup: [Int]
    @Binding var selectedName: Int?
    @Binding var openModelCard: Bool
    @Binding var isPreviewVisible: Bool
    @Binding var hideTopInset: Bool
    @Binding var didRunInitialLayout: Bool
    @Binding var searchedNode: Int? 
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @Environment(\.colorScheme) private var colorScheme
    var outerColor: UIColor = .systemGray
    var innerColor: UIColor = .systemGray
    var coreColor:  UIColor = .systemGray
    
    var onActivity: (() -> Void)? = nil
    var onInactivity: (() -> Void)? = nil        // fires after 4.5 min of no interaction
    var onLayersBuilt: (([[String]]) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self, isReady: _isReady) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.overrideUserInterfaceStyle = .unspecified
        v.backgroundColor = .clear
        v.allowsCameraControl = false
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 30 // sane default; bump while interacting
        // 👉 Quality knobs that are surprisingly expensive
        v.antialiasingMode = .none
        
        isReady = false
        
        let scene = context.coordinator.buildScene()
        v.scene = scene
        
        
        // gestures…
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.observePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        
        
    
        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.observeTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = context.coordinator
        v.addGestureRecognizer(twoFingerPan)
        
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.observePinch(_:)))
        pinch.delegate = context.coordinator
        v.addGestureRecognizer(pinch)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)

        // ✅ Double tap
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        v.addGestureRecognizer(doubleTap)

        // Make single-tap wait for double-tap
        tap.require(toFail: doubleTap)

        
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0.2        // give tap a chance; 0.15–0.25 feels good
        press.allowableMovement = 16
        tap.require(toFail: pan)                 // keep this if you like
        press.require(toFail: tap)               // <-- critical: tap takes priority
        press.delegate = context.coordinator
        v.addGestureRecognizer(press)
        
        
        v.delegate = context.coordinator
        context.coordinator.view = v
        return v
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        let sys = (systemColorScheme == .dark) ? UIUserInterfaceStyle.dark : .light
        let style = effectiveStyle(selectedAppearance: selectedAppearance, systemStyle: sys)

        context.coordinator.applyIfNeeded(
            selectedName: selectedName,
            searchedName: searchedNode,
            effectiveScheme: style,
            selectedGroup: &selectedGroup,
            didRunInitialLayout: &didRunInitialLayout
        )
    }
    
    private enum Theme {

        static func iconFill(for style: UIUserInterfaceStyle) -> UIColor {
            style == .dark ? .white : .black
        }

        static func iconHighlight(for style: UIUserInterfaceStyle) -> UIColor {
            style == .dark
            ? UIColor(white: 1.0, alpha: 0.7)
            : UIColor(white: 0.0, alpha: 0.7)
        }

        static func usingForData(
            selectedAppearance: AppearanceOption,
            systemColorScheme: UIUserInterfaceStyle
        ) -> UIColor {
            let style = effectiveStyle(selectedAppearance: selectedAppearance,
                                       systemStyle: systemColorScheme)
            return (style == .dark) ? .black : .white
        }

        static func label(
            selectedAppearance: AppearanceOption,
            systemColorScheme: UIUserInterfaceStyle
        ) -> UIColor {
            usingForData(selectedAppearance: selectedAppearance,
                         systemColorScheme: systemColorScheme)
        }

        static func labelDimmed(
            selectedAppearance: AppearanceOption,
            systemColorScheme: UIUserInterfaceStyle
        ) -> UIColor {
            label(selectedAppearance: selectedAppearance,
                  systemColorScheme: systemColorScheme
            )
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, SCNSceneRendererDelegate {
        private let isReady: Binding<Bool>
        func markReady(_ value: Bool) {
            DispatchQueue.main.async { self.isReady.wrappedValue = value }
        }
        private var lastActivityStamp: CFTimeInterval = 0
        private let activityCooldown: CFTimeInterval = 300 // 4.5 minutes
        private var inactivityTimer: DispatchSourceTimer?
        
        var lastSelectedName: Int?
        var lastSearchedName: Int?
        var lastEffectiveScheme: UIUserInterfaceStyle?
        
        // Optional: guard against re-entrancy from state bouncing
        private var isApplying = false
        private var groupOverlayNodes: [SCNNode] = []
        private func makeLineLoop(_ pts: [SIMD3<Float>], color: UIColor, opacity: CGFloat = 1.0) -> SCNNode {
            guard pts.count >= 2 else { return SCNNode() }
            var positions = [Float]()
            var indices   = [UInt32]()
            // chain + close the loop
            for p in pts { positions += [p.x, p.y, p.z] }
            for i in 0..<(pts.count - 1) { indices += [UInt32(i), UInt32(i+1)] }
            indices += [UInt32(pts.count - 1), 0]
            
            let vData = Data(buffer: positions.withUnsafeBufferPointer { $0 })
            let iData = Data(buffer: indices.withUnsafeBufferPointer   { $0 })
            
            let src = SCNGeometrySource(
                data: vData, semantic: .vertex, vectorCount: positions.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3
            )
            let elem = SCNGeometryElement(
                data: iData, primitiveType: .line,
                primitiveCount: indices.count / 2,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            let g = SCNGeometry(sources: [src], elements: [elem])
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            m.diffuse.contents  = color
            m.emission.contents = color
            m.transparency = opacity
            m.blendMode = .alpha
            g.firstMaterial = m
            
            let n = SCNNode(geometry: g)
            n.renderingOrder = 2400
            n.name = "groupWire"
            return n
        }
        
        
        // --- Group overlay tracking ---
        private struct GroupOverlay {
            var rShell: Float
            var ids: [Int]                // the node ids that define this shell’s loop (unordered)
            var line: SCNNode?            // wire node (loop of .line segments)
            var fill: SCNNode?            // optional triangle fan fill
        }
        private var liveGroupOverlays: [GroupOverlay] = []
        
        
        
        func applyIfNeeded(
            selectedName: Int?,
            searchedName: Int?,
            effectiveScheme: UIUserInterfaceStyle,
            selectedGroup: inout [Int],
            didRunInitialLayout: inout Bool
        ) {
            if isApplying { return }
            isApplying = true
            defer { isApplying = false }
            
            // Theme changes only when scheme changes
            if lastEffectiveScheme != effectiveScheme {
                ensureTheme(uiStyle: effectiveScheme)
                lastEffectiveScheme = effectiveScheme
            }
            
            // Determine what changed
            let selectionChanged = (lastSelectedName != selectedName)
            if selectionChanged { lastSelectedName = selectedName }
            let searchChanged = (searchedName != lastSearchedName)
            if searchChanged { lastSearchedName = searchedName }
            let incomingGroupSet = Set(selectedGroup)
            
            
            if searchChanged {
                if let searched = searchedName {
                    didRunInitialLayout = true
                    let groupSnapshot = selectedGroup
                    restoreOriginalNodePlacement(animated: true, duration: 0.30) { [weak self] in
                        guard let self = self else { return }
                        self.updateGroupLayout(group: groupSnapshot, around: searched)
                        self.currentSelectedGroup = incomingGroupSet.union([searched])
                        
                        self.filterConnectionsForGroup()
                        
                    }
                    return
                    
                } else {
                    selectedGroup.removeAll()
                    currentSelectedGroup.removeAll()
                    didRunInitialLayout = false
                    restoreOriginalNodePlacement(animated: true, duration: 0.30){}
                    
                    for (_, wrapper) in self.labelByNumber {
                        self.setWrapperAlphaAndScale(wrapper, to: 1.0)
                    }
                    for c in self.connections {
                        c.container.isHidden = false
                        c.container.opacity  = 1
                    }
                    
                    return
                }
            }
            
            if selectionChanged {
                updateSelection(selectedName)
            }
        }
        
        
        let parent: SphereSceneView
        private let maxRadius: Float
        private let nodeScale: Float = 0.9
        private let shellRanges: [Int: ClosedRange<Int>] = [
            1: 1...50,
            2: 51...150,
            3: 151...350,
            4: 351...750,
            5: 751...1550,
            6: 1551...3150,
            7: 3151...6350,
            8: 6351...12750,
            9: 12751...25550,
            10: 25551...51150,
            11: 51151...102350,
            12: 102351...204750
        ]
        
        
        init(parent: SphereSceneView, isReady: Binding<Bool>) {
            self.parent = parent
            self.isReady = isReady
            
            
            let all = Array(parent.GlobalModelsData.keys)
            let largestShellKey = shellRanges
                .filter { _, range in all.contains(where: range.contains) }
                .map { $0.key }
                .max() ?? 1
            
            
            let barrierMap: [Int: Float] = [
                1: 0.1, 2: 0.1, 3: 0.1, 4: 0.18,
                5: 0.25, 6: 0.35, 7: 0.42, 8: 0.7,
                9: 0.7, 10: 0.7, 11: 0.7, 12: 0.7
            ]
            let maxRadiusBarrier = barrierMap[largestShellKey] ?? 1.0
            
            
            self.maxRadius = 120.0 * maxRadiusBarrier
            
            super.init()
            resetInactivityTimer() // start counting from creation
        }
        deinit { inactivityTimer?.cancel() }
        private struct RecenterAnim {
            var t0: TimeInterval = 0
            var dur: TimeInterval = 0.32
            var startCenter: SCNVector3 = SCNVector3(0, 0, 0)
            var endCenter:   SCNVector3 = SCNVector3(0, 0, 0)
            var startYaw:   Float = 0, endYaw:   Float = 0
            var startPitch: Float = 0, endPitch: Float = 0
            var startR:     Float = 0, endR:     Float = 0
        }
        private func targetHeightForLayer(localLayer: Int, totalLayers: Int) -> CGFloat {
            let coreHeight: CGFloat = 0.01    // size at the innermost layer (tweak)
            let falloff: CGFloat    = 1.5   // 0.6…0.9: lower = faster shrink
            return coreHeight * pow(falloff, CGFloat(localLayer))
        }
        
        // In Coordinator
        private var atlas: LabelAtlas?
        private var atlasEntryByID: [Int: AtlasEntry] = [:]
        private var atlasMaterials: [Int: SCNMaterial] = [:] // atlasIndex -> shared material
        
        
        private var lastAppliedScheme: UIUserInterfaceStyle?
        @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
        private var recenter: RecenterAnim?
        private let worldUnitsPerPoint: CGFloat = 2 // tune so label sizes
        // Wires (already there)
        private var wireNodes: [SCNNode] = []
        private var wireBaseOpacity: [CGFloat] = []
        private var foggedLayers = Set<Int>()
        
        // NEW: fog shells (solid translucent sphere per layer)
        private var fogSphereNodes: [SCNNode] = []
        private var fogSphereBaseAlpha: [CGFloat] = []
        
        // NEW: dim groups (all anchors/labels) when fogged
        private var groupBaseOpacity: [CGFloat] = []
        private var loadedLayerCount = 1  // start with the inner shell only
        
        // Tuning
        private let fogWireAlpha: CGFloat = 0.0   // line translucency when fogged
        private let fogFillAlpha: CGFloat = 0.0   // shell surface translucency when fogged
        private let fogGroupAlpha: CGFloat = 0.20  // dim anchors/labels on that shell
        private let fogAnim: TimeInterval = 0.25
        private let fogHysteresis: CGFloat = 0.15
        
        
        
        
        
        weak var view: SCNView?
        
        private struct ColorCache {
            var label: UIColor = .label
            var labelDimmed: UIColor = .label
            var iconFill: UIColor = .label
            var iconHighlight: UIColor = .systemBlue
            var wire: UIColor = .white
        }
        private var colors = ColorCache()
        
        
        private(set) var labelNodes: [SCNNode] = []
        private var orbitCenter = SCNVector3Zero
        
        
        private var labelNodesByLayer: [[SCNNode]] = Array(repeating: [], count: 5)
        private var namesByLayer:      [[String]]  = Array(repeating: [], count: 5)
        private var eyeByLabel: [ObjectIdentifier: SCNNode] = [:]
        
        private var labelByNumber: [Int: SCNNode] = [:]
        private var originalColors: [ObjectIdentifier: UIColor] = [:]
        private var cameraNode: SCNNode?
        private var lookConstraint: SCNLookAtConstraint?
        private let spinKey = "spin"
        private weak var sceneRoot: SCNNode?
        private var spinDirection: Float = 1.0
        private var lastTwoDirections: [Int] = []
        private var anchorByNumber: [Int: SCNNode] = [:]
        
        
        private var radiusValues: [CGFloat] = [0,0,0,0,0]
        private var radiusByGroupName: [String: CGFloat] = [:]
        private var groupNodes: [SCNNode] = []
        
        
        
        private var focusNode = SCNNode()
        private var distanceConstraint: SCNDistanceConstraint?
        
        private var outerRadiusValue: CGFloat = 5
        private var innerRadiusValue: CGFloat = 1
        private var coreRadiusValue:  CGFloat = 0.09
        
        private var yaw:   Float = 0
        private var pitch: Float = 0
        private var camRadius: Float = 25
        
        private var chromeHidden = false  // local cache to apply hysteresis
        private func setHideTopInset(_ val: Bool) {
            guard self.parent.hideTopInset != val else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88, blendDuration: 0.15)) {
                    self.parent.hideTopInset = val
                }
                
            }
        }
        private var chainConnIndicesByParent: [Int: [Int]] = [:]   // NEW: parentId → all connection indexes in that chain
        private var chainParentByNode: [Int: Int] = [:]            // NEW: nodeId   → chain parentId
        
        private func updateTopChromeVisibility() {
            let rMin = minZoom(for: focusAnchor)
            let t = (camRadius - rMin) / max(1e-6, (maxRadius - rMin)) // 0 (zoomed-in) → 1 (zoomed-out)
            
            // Hysteresis: hide below 0.18, show above 0.26
            let shouldHide = (chromeHidden ? (t < 0.26) : (t < 0.22))
            guard shouldHide != chromeHidden else { return }
            chromeHidden = shouldHide
            insetDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.setHideTopInset(shouldHide) }
            insetDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        private let pitchMin: Float = -Float.pi + 0.001
        private let pitchMax: Float =  Float.pi - 0.001
        private let yawSensitivity:   Float = 0.005
        private let pitchSensitivity: Float = 0.005
        private let minRadius: Float = 0.08
        private var insetDebounce: DispatchWorkItem?
        
        private var focusAnchor: SCNNode?
        private var followLerp: Float = 0.18
        
        private var yawVel:   Float = 0
        private var pitchVel: Float = 0
        
        // Reusable look-at target anchored at world origin (0,0,0)
        private let worldCenterTarget = SCNNode()
        private var worldCenterLook: SCNLookAtConstraint?
        
        
        private let inertiaThreshold: CGFloat = 600
        private let inertiaMax: CGFloat       = 2500
        private let boostFactor: Float        = 0.8
        
        
        private let friction: Float = 2.2
        private let maxSpeed: Float = 6.0
        
        private func sphereWireColorResolved(_ trait: UITraitCollection) -> UIColor {
            return resolvedLineColor(trait)
        }
        
        
        private var lastUpdateTime: TimeInterval?
        
        private var currentSelectedGroup = Set<Int>()
        private func nameFor(number: Int) -> String? {
            guard let raw = parent.GlobalModelsData[number]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return nil
            }
            return raw
        }
        func ensureTheme(uiStyle: UIUserInterfaceStyle) {
            
            guard lastAppliedScheme != uiStyle else { return }
            lastAppliedScheme = uiStyle
            view?.overrideUserInterfaceStyle = uiStyle
            resolveColors()
            reapplyDynamicColors()
        }
        private func reapplyDynamicColors() {
            guard let root = sceneRoot else { return }
            resolveColors()              // ⬅️ ensure fresh if trait changed outside ensureTheme()
            let wire = colors.wire
            
            // recolor wire spheres
            let wireMask = 1 << 1
            root.enumerateChildNodes { node, _ in
                guard (node.categoryBitMask & wireMask) != 0,
                      let geo = node.geometry,
                      let elem = geo.elements.first, elem.primitiveType == .line,
                      let mat = geo.firstMaterial
                else { return }
                mat.lightingModel = .constant
                mat.diffuse.contents  = wire
                mat.emission.contents = UIColor.clear
                mat.specular.contents = UIColor.clear
            }
            
            // recolor SCNText labels (fallback path only)
            for label in labelNodes {
                if let text = label.geometry as? SCNText,
                   let mat = text.firstMaterial {
                    mat.diffuse.contents = colors.label
                }
            }
        }
        
        // MARK: - Global spin (rotate whole structure)
        private var contentRoot: SCNNode?          // everything you want to spin goes under this
        private var spinEnabled: Bool = true
        private var spinAxis = simd_float3(0, 1, 0) // y-axis; change to (1,1,0) normalized for a tilted spin
        private var spinSpeed: Float = .pi / 18     // radians/sec (≈10°/s). tweak.
        private var lastSpinTime: TimeInterval?

        
        private final class LineMeshBuilder {
            private var positions = [Float]()       // xyz xyz xyz ...
            private var indices   = [UInt32]()      // pairs for .line
            private(set) var lineCount: Int = 0
            
            // Add a polyline as disjoint line segments: p0-p1, p1-p2, ...
            func addPolyline(_ pts: [SIMD3<Float>]) {
                guard pts.count >= 2 else { return }
                let base = UInt32(positions.count / 3)
                positions.reserveCapacity(positions.count + pts.count * 3)
                indices.reserveCapacity(indices.count + (pts.count - 1) * 2)
                
                for p in pts { positions.append(contentsOf: [p.x, p.y, p.z]) }
                for i in 0..<(pts.count - 1) {
                    indices.append(base + UInt32(i))
                    indices.append(base + UInt32(i + 1))
                }
                lineCount += (pts.count - 1)
            }
            
            /// New: accept a template (or build one) so this node matches your line style.
            func buildNode(
                opacity: CGFloat,
                renderingOrder: Int = 2300,
                materialTemplate: SCNMaterial? = nil,
                respectsDepth: Bool = true
            ) -> SCNNode {
                let vData = Data(buffer: positions.withUnsafeBufferPointer { $0 })
                let iData = Data(buffer: indices.withUnsafeBufferPointer   { $0 })
                
                let src = SCNGeometrySource(
                    data: vData, semantic: .vertex, vectorCount: positions.count / 3,
                    usesFloatComponents: true, componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                    dataStride: MemoryLayout<Float>.size * 3
                )
                let elem = SCNGeometryElement(
                    data: iData, primitiveType: .line,
                    primitiveCount: indices.count / 2,
                    bytesPerIndex: MemoryLayout<UInt32>.size
                )
                
                let geo = SCNGeometry(sources: [src], elements: [elem])
                
                let template = materialTemplate ?? ConnectionMaterialTemplate.make(
                    opacity: opacity,
                    respectsDepth: respectsDepth
                )
                // For the batched node we generally want one material (whole set animates together)
                geo.firstMaterial = ConnectionMaterialTemplate.clone(from: template)
                
                let n = SCNNode(geometry: geo)
                n.renderingOrder = renderingOrder
                return n
            }
        }
        
        final class TextImageCache {
            static let shared = TextImageCache()
            private var cache = NSCache<NSString, UIImage>()
            private init() { cache.countLimit = 200 } // tune as needed
            
            func image(text: String,
                       font: UIFont,
                       color: UIColor,
                       padding: CGFloat = 6,
                       maxWidth: CGFloat? = nil,
                       scale: CGFloat = UIScreen.main.scale) -> UIImage {
                let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(color.description)|\(padding)|\(maxWidth ?? -1)|\(scale)" as NSString
                if let img = cache.object(forKey: key) { return img }
                
                // Render with CoreGraphics (transparent background)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                var size = (text as NSString).size(withAttributes: attrs)
                
                if let maxW = maxWidth, size.width > maxW {
                    // Multi-pass simple shrink to fit (cheap); or use CTFramesetter if you need wrapping
                    let factor = maxW / max(size.width, 1)
                    let newFont = UIFont(descriptor: font.fontDescriptor, size: font.pointSize * factor)
                    let newAttrs = attrs.merging([.font: newFont]) { $1 }
                    size = (text as NSString).size(withAttributes: newAttrs)
                    return image(text: text, font: newFont, color: color, padding: padding, maxWidth: maxWidth, scale: scale)
                }
                
                let canvas = CGSize(width: ceil(size.width + padding*2), height: ceil(size.height + padding*2))
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                format.opaque = false
                
                let img = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                    let rect = CGRect(origin: CGPoint(x: padding, y: padding),
                                      size: size)
                    (text as NSString).draw(in: rect, withAttributes: attrs)
                }
                
                cache.setObject(img, forKey: key)
                return img
            }
        }
        
        func makeFogSphere(radius: CGFloat, baseAlpha: CGFloat) -> SCNNode {
            let s = SCNSphere(radius: radius * 1.0015)
            s.segmentCount = 96
            
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor { tc in
                tc.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
            }
            m.transparency = baseAlpha
            m.isDoubleSided = false            // <- important
            m.readsFromDepthBuffer = true
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
            
            s.firstMaterial = m
            
            let n = SCNNode(geometry: s)
            n.name = "fogSphere"
            n.renderingOrder = 1200
            return n
        }
        
        private func cameraDistanceFromWorldOrigin() -> CGFloat {
            guard let cam = cameraNode else { return .greatestFiniteMagnitude }
            // Use presentation if it’s non-zero, otherwise use the regular worldPosition
            let pw = cam.presentation.worldPosition
            let w  = cam.worldPosition
            let p: SCNVector3 = (pw.x == 0 && pw.y == 0 && pw.z == 0 &&
                                 (w.x != 0 || w.y != 0 || w.z != 0)) ? w : pw
            let (x,y,z) = (p.x, p.y, p.z)
            return CGFloat(sqrt(x*x + y*y + z*z))
        }
        
        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            ensureUnpaused()
            markActivityAndResetTimer()
            recordActivityThrottled()

            let r = camRadius
            let rMin = minZoom(for: nil)

            let nearStart = r >= (0.90 * maxRadius)     // within 10% of start (zoomed out)
            let deepZoom  = r <= (0.30 * maxRadius)     // ✅ 0.3 or deeper → allow zoom out

            let targetR: Float
            if nearStart {
                // Zoom IN hard (to 20% of current), but respect minimum zoom
                targetR = max(rMin, r * 0.2)
            } else if deepZoom {
                // Zoom OUT (inverse of 0.2x is 5x), capped to maxRadius
                targetR = min(maxRadius, max(rMin, r * 5.0))
            } else {
                return
            }

            recenter = RecenterAnim(
                t0: lastUpdateTime ?? CACurrentMediaTime(),
                dur: 0.28,
                startCenter: orbitCenter,
                endCenter:   SCNVector3Zero,
                startYaw:    yaw,
                endYaw:      yaw,
                startPitch:  pitch,
                endPitch:    pitch,
                startR:      camRadius,
                endR:        targetR
            )
        }

        private func attachButtons(to wrapper: SCNNode, plateSize: CGSize) {
            // compute sizes like your SCNText path
            let plateW = plateSize.width
            let plateH = plateSize.height
            
            let minSide: CGFloat = 0.028
            let baseSide = plateH * 0.48
            let edgeInset: CGFloat = max(0.004, plateW * 0.06)
            let minGap: CGFloat = max(0.004, plateW * 0.04)
            let oneRowMaxSide = max(minSide, (plateW - (edgeInset * 2) - (minGap * 2)) / 3.0)
            let heightCap = plateH * 0.8
            
            var side = min(max(minSide, baseSide), oneRowMaxSide, heightCap)
            
            let zPos: Float = 0.002
            let halfW = Float(plateW * 0.5)
            let halfH = Float(plateH * 0.5)
            
            let close = makeCloseNode(side: side)
            let eye   = makeEyeNode(side: side)
            let play  = makePlayNode(side: side)
            
            // prefer "top row" layout when there is room
            let useCornerLayout = (side < baseSide * 0.8)
            
            if !useCornerLayout {
                let padX  = Float(side * 0.65)
                let yTop  = halfH + Float(side * 0.6)
                close.position = SCNVector3(-halfW + padX, yTop, zPos)
                eye.position   = SCNVector3(0,             yTop, zPos)
                play.position  = SCNVector3( halfW - padX, yTop, zPos)
                close.renderingOrder = 2600; eye.renderingOrder = 2600; play.renderingOrder = 2600
                close.categoryBitMask = 1 << 0; eye.categoryBitMask = 1 << 0; play.categoryBitMask = 1 << 0
                
                wrapper.addChildNode(close)
                wrapper.addChildNode(eye)
                wrapper.addChildNode(play)
            } else {
                // corner layout fallback
                side = min(max(side, baseSide * 0.9), heightCap)
                let ix = Float(edgeInset + side * 0.5)
                let topY    =  halfH + Float(side * 0.15)
                let bottomY = -halfH + Float(side * 0.20)
                close.position = SCNVector3(-halfW + ix, topY,    zPos)
                play.position  = SCNVector3( halfW - ix, topY,    zPos)
                eye.position   = SCNVector3( halfW - ix, bottomY, zPos)
                close.renderingOrder = 2600; eye.renderingOrder = 2600; play.renderingOrder = 2600
                close.categoryBitMask = 1 << 0; eye.categoryBitMask = 1 << 0; play.categoryBitMask = 1 << 0
                
                wrapper.addChildNode(close)
                wrapper.addChildNode(eye)
                wrapper.addChildNode(play)
            }
            
            // billboard with the label; buttons start hidden until selection
            wrapper.constraints = [SCNBillboardConstraint()]
            
            close.isHidden = true
            eye.isHidden   = true
            play.isHidden  = true
            
            // remember for toggling in applySelection/clearSelection
            closeByLabel[ObjectIdentifier(wrapper)] = close
            eyeByLabel  [ObjectIdentifier(wrapper)] = eye
            playByLabel [ObjectIdentifier(wrapper)] = play
        }
        
        private func makeLabelPlane_FallbackBitmap(for key: String,
                                                   color: UIColor,
                                                   atRadius R: CGFloat) -> SCNNode {
            // 1) Render text into an image
            let font = UIFont.systemFont(ofSize: 14, weight: .medium)
            let img = TextImageCache.shared.image(
                text: key, font: font, color: color,
                padding: 4,
                maxWidth: 140,             // tune — small!
                scale: 1.0                 // <- huge memory saver
            )
            
            // 2) Build a plane matching the image’s aspect (in SceneKit world units)
            let w = img.size.width  * worldUnitsPerPoint
            let h = img.size.height * worldUnitsPerPoint
            
            let plane = SCNPlane(width: max(w, 0.06), height: max(h, 0.025))
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = img
            mat.diffuse.minificationFilter = .linear
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.mipFilter = .nearest
            
            mat.emission.contents = UIColor.clear
            mat.isDoubleSided = true
            mat.readsFromDepthBuffer = false
            mat.writesToDepthBuffer = false
            mat.blendMode = .alpha
            
            plane.firstMaterial = mat
            
            // 3) Wrapper that always faces the camera
            let wrapper = SCNNode()
            wrapper.name = "labelWrapper"
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.categoryBitMask = 1 << 0
            wrapper.renderingOrder = 1000
            
            // 4) Put the textured plane in front (z-slightly) and add a visible hit plate behind if you want
            let labelNode = SCNNode(geometry: plane)
            labelNode.name = "labelPlane"
            labelNode.categoryBitMask = 1 << 5
            if let labelMat = labelNode.geometry?.firstMaterial {
                labelMat.readsFromDepthBuffer = false
                labelMat.writesToDepthBuffer = false   // ← keep false
                labelMat.blendMode = .alpha            // label’s PNG needs alpha
                labelMat.diffuse.mipFilter = .none
                labelMat.diffuse.minificationFilter = .nearest
                labelMat.diffuse.magnificationFilter = .linear
                
            }
            labelNode.renderingOrder = 2000
            
            wrapper.addChildNode(labelNode)
            
            // 👉 Optional: visible hit plate similar to your old plate (contrasting color)
            let plate = SCNPlane(width: plane.width, height: plane.height)
            plate.cornerRadius = min(plate.width, plate.height) * 0.08
            
            let pm = SCNMaterial()
            pm.lightingModel = .constant
            let trait = view?.traitCollection ?? UIScreen.main.traitCollection
            let style = currentStyle()  // ← use the helper you already added
            pm.diffuse.contents = (style == .dark) ? UIColor.white : UIColor.black
            
            
            // ✅ Make it a solid, opaque occluder
            pm.transparency = 1.0
            pm.isDoubleSided = true        // was false
            
            pm.readsFromDepthBuffer = true
            pm.writesToDepthBuffer = true
            pm.blendMode = .replace                // treat as opaque (no alpha blending)
            
            plate.firstMaterial = pm
            
            let plateNode = SCNNode(geometry: plate)
            // Put the plate slightly behind the label image in local Z
            plateNode.position = SCNVector3(0, 0, -0.0005)
            plateNode.name = "labelPlate"
            plateNode.categoryBitMask = 1 << 0
            
            // ✅ Draw order: plate < labelPlane < icons
            plateNode.renderingOrder = 1500
            wrapper.addChildNode(plateNode)
            
            
            
            
            
            // Keep a reference so your selection/dimming code can find this label quickly
            remember(wrapper) // <- update remember() to accept wrapper, see below
            return wrapper
        }
        @inline(__always)
        private func currentStyle() -> UIUserInterfaceStyle {
            let system: UIUserInterfaceStyle = (parent.systemColorScheme == .dark) ? .dark : .light
            return lastAppliedScheme ?? effectiveStyle(selectedAppearance: parent.selectedAppearance,
                                                       systemStyle: system)
        }
        
        
        private func makeLabelPlane(for key: String,
                                    color: UIColor,
                                    atRadius R: CGFloat,
                                    id: Int) -> SCNNode {
            guard let entry = atlasEntryByID[id],
                  let sharedMat = atlasMaterials[entry.atlasIndex] else {
                return makeLabelPlane_FallbackBitmap(for: key, color: color, atRadius: R)
            }
            
            let px = entry.pixelSize
            let w = px.width  * worldUnitsPerPoint
            let h = px.height * worldUnitsPerPoint
            
            let plane = SCNPlane(width: max(w, 0.06), height: max(h, 0.025))
            
            // Copy the shared material so each plane can have its own UV transform.
            let mat = sharedMat.copy() as! SCNMaterial
            mat.isDoubleSided = true
            mat.blendMode = .alpha
            mat.readsFromDepthBuffer = false   // ← keep OFF so the plate can't occlude
            mat.writesToDepthBuffer = false
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.mipFilter = .none
            mat.diffuse.minificationFilter = .nearest
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.contentsTransform = atlasUVTransform(entry.uvRect)
            
            plane.firstMaterial = mat
            
            // Wrapper + nodes
            let wrapper = SCNNode()
            wrapper.name = "labelWrapper"
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.categoryBitMask = 1 << 0
            wrapper.renderingOrder = 1000
            
            let labelNode = SCNNode(geometry: plane)
            labelNode.name = "labelPlane"
            labelNode.categoryBitMask = 1 << 5
            labelNode.renderingOrder = 2000
            wrapper.addChildNode(labelNode)
            
            // Opaque plate behind
            let plate = SCNPlane(width: plane.width, height: plane.height)
            plate.cornerRadius = min(plate.width, plate.height) * 0.08
            
            let pm = SCNMaterial()

            let trait = view?.traitCollection ?? UIScreen.main.traitCollection
            let style = currentStyle()  // ← use the helper you already added
            pm.diffuse.contents = (style == .dark) ? UIColor.white : UIColor.black
            
            pm.transparency = 1.0
            pm.isDoubleSided = true
            pm.readsFromDepthBuffer = true
            pm.writesToDepthBuffer = true

            plate.firstMaterial = pm
            
            let plateNode = SCNNode(geometry: plate)
            plateNode.position = SCNVector3(0, 0, -0.0005)
            plateNode.name = "labelPlate"
            plateNode.categoryBitMask = 1 << 0
            plateNode.renderingOrder = 1500
            wrapper.addChildNode(plateNode)
            
            remember(wrapper)
            return wrapper
        }
        
        
        // Store once when you create anchors (or after your ordered layout)
        struct Spherical { var r: Float; var theta: Float; var phi: Float }
        var sphericalByID: [Int: Spherical] = [:]
        
        func setAnchor(_ anchor: SCNNode, to s: Spherical) {
            let x = s.r * sin(s.theta) * cos(s.phi)
            let y = s.r * cos(s.theta)
            let z = s.r * sin(s.theta) * sin(s.phi)
            anchor.position = SCNVector3(x, y, z)
        }
        
        func freezeCurrentPose(id: Int, anchor: SCNNode) {
            // Convert current position once → spherical and cache it
            let p = simd_float3(anchor.position)
            let r = max(1e-6, simd_length(p))
            let theta = acosf(max(-1, min(1, p.y / r)))
            let phi = atan2f(p.z, p.x)
            sphericalByID[id] = Spherical(r: r, theta: theta, phi: phi)
        }
        
        
        
        
        private func plateSize(in wrapper: SCNNode) -> CGSize? {
            if let plate = wrapper.childNode(withName: "labelPlate", recursively: false)?.geometry as? SCNPlane {
                return CGSize(width: plate.width, height: plate.height)
            }
            if let plane = wrapper.childNode(withName: "labelPlane", recursively: false)?.geometry as? SCNPlane {
                return CGSize(width: plane.width, height: plane.height)
            }
            return nil
        }
        
        /// Create and attach buttons for this wrapper if not present yet.
        private func ensureButtonsInstalled(on wrapper: SCNNode) {
            let key = ObjectIdentifier(wrapper)
            guard closeByLabel[key] == nil || eyeByLabel[key] == nil || playByLabel[key] == nil else { return }
            guard let sz = plateSize(in: wrapper) else { return }
            attachButtons(to: wrapper, plateSize: sz)
        }
        
        /// Remove (detach) buttons for this wrapper and clear maps.
        private func removeButtons(from wrapper: SCNNode) {
            let key = ObjectIdentifier(wrapper)
            if let n = closeByLabel[key] { n.removeFromParentNode() }
            if let n = eyeByLabel[key]   { n.removeFromParentNode() }
            if let n = playByLabel[key]  { n.removeFromParentNode() }
            closeByLabel[key] = nil
            eyeByLabel[key]   = nil
            playByLabel[key]  = nil
        }
        
        @inline(__always) private func shortestDelta(_ a: Float, _ b: Float) -> Float {
            var d = fmodf(b - a, 2 * .pi)
            if d >  .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            return d
        }
        
        @inline(__always) private func ease(_ t: Float) -> Float {
            let x = max(0, min(1, t))
            return x * x * (3 - 2 * x)
        }
        
        private func resolveColors() {
            let systemStyle: UIUserInterfaceStyle = (parent.systemColorScheme == .dark) ? .dark : .light
            let style = lastAppliedScheme
            ?? effectiveStyle(selectedAppearance: parent.selectedAppearance, systemStyle: systemStyle)
            
            colors.label         = Theme.label(selectedAppearance: parent.selectedAppearance, systemColorScheme: style)
            colors.labelDimmed   = Theme.labelDimmed(selectedAppearance: parent.selectedAppearance, systemColorScheme: style)
            colors.iconFill      = Theme.iconFill(for: style)
            colors.iconHighlight = Theme.iconHighlight(for: style)
            colors.wire = (style == .dark)
            ? UIColor(white: 1.0, alpha: 0.82)
            : UIColor(white: 0.0, alpha: 0.70)
        }
        
        @inline(__always)
        private func edgeSegments(forRadius R: Float, camR: Float) -> Int {
            // farther camera → fewer segments
            let t = max(0, min(1, R / max(0.01, camR)))
            let lo = 12, hi = 64
            return Int(Float(lo) + Float(hi - lo) * t)
        }
        private func sampleSphericalArcPoints(from a: SCNVector3,
                                              to b: SCNVector3,
                                              onRadius R: Float,
                                              segments: Int) -> [SIMD3<Float>] {
            func proj(_ p: SCNVector3) -> SIMD3<Float> {
                var v = SIMD3<Float>(p.x, p.y, p.z)
                let len = simd_length(v)
                return len < 1e-6 ? SIMD3<Float>(0,1,0) : (v / len) * R
            }
            let A = proj(a), B = proj(b)
            let aDir = simd_normalize(A), bDir = simd_normalize(B)
            var dot = simd_dot(aDir, bDir); dot = max(-1, min(1, dot))
            let omega = acos(dot)
            
            var pts = [SIMD3<Float>]()
            pts.reserveCapacity(max(2, segments + 1))
            if omega < 1e-4 {
                for i in 0...segments {
                    let t = Float(i) / Float(segments)
                    pts.append(simd_normalize((1 - t) * aDir + t * bDir) * R)
                }
            } else {
                let invSin = 1 / sin(omega)
                for i in 0...segments {
                    let t = Float(i) / Float(segments)
                    let s0 = sin((1 - t) * omega) * invSin
                    let s1 = sin(t * omega) * invSin
                    pts.append(simd_normalize(s0 * aDir + s1 * bDir) * R)
                }
            }
            return pts
        }
        private func sampleRadialPoints(direction dirIn: simd_float3,
                                        fromRadius r0: Float,
                                        toRadius r1: Float,
                                        segments: Int) -> [SIMD3<Float>] {
            let dir = simd_normalize(dirIn)
            var pts = [SIMD3<Float>]()
            pts.reserveCapacity(max(2, segments + 1))
            for i in 0...max(1, segments) {
                let t = Float(i) / Float(max(1, segments))
                let r = (1 - t) * r0 + t * r1
                pts.append(dir * r)
            }
            return pts
        }
        private func zoomScaleForControls() -> Float {
            let rMin = max(1e-6, minZoom(for: focusAnchor))
            let rMax = max(rMin * 1.0001, maxRadius)
            let r    = max(rMin, min(rMax, camRadius))
            
            // Normalize radius in log space
            let t = Float((log(Double(r)) - log(Double(rMin))) /
                          (log(Double(rMax)) - log(Double(rMin))))
            let clampedT = max(0, min(1, t))
            
            // Base exponent
            let k: Float = 4
            
            // Extra strength at far zoom-out (e.g. +2 = k=6 at t=0)
            let extraStrength: Float = 10
            
            // Dynamic exponent: starts at k+extra, fades to k
            let dynamicK = k + extraStrength * (1 - clampedT)
            
            // Apply progressive exponent curve
            let eased = powf(clampedT, dynamicK)
            
            // Scale to range
            let near: Float = 0.05
            let far:  Float = 1.00
            return near + (far - near) * eased
        }
        
        
        private func dynamicNodeColor(_ base: UIColor, lightBrightnessScale: CGFloat = 0.65) -> UIColor {
            if #available(iOS 13.0, *) {
                return UIColor { tc in
                    
                    guard tc.userInterfaceStyle != .dark else { return base }
                    
                    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    
                    if base.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
                        return UIColor(hue: h, saturation: s, brightness: max(0, b * lightBrightnessScale), alpha: a)
                    } else {
                        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
                        if base.getRed(&r, green: &g, blue: &bl, alpha: &a) {
                            return UIColor(red: r * lightBrightnessScale, green: g * lightBrightnessScale, blue: bl * lightBrightnessScale, alpha: a)
                        }
                        return base
                    }
                }
            } else {
                return base
            }
        }
        private var lastPanPoint: CGPoint?
        private func wrap(_ a: Float, period: Float = 2 * .pi) -> Float {
            var x = fmodf(a, period)
            if x < 0 { x += period }
            return x
        }
        private var rig: SCNNode?
        private var yawNode: SCNNode?
        private var pitchNode: SCNNode?
        private var baseScaleByLabel: [ObjectIdentifier: SCNVector3] = [:]
        private var closeByLabel: [ObjectIdentifier: SCNNode] = [:]
        private var playByLabel: [ObjectIdentifier: SCNNode] = [:]
        private var deferredLayers: [(layerIndex: Int, radius: CGFloat)] = []
        private final class DSU {
            private var parent: [Int: Int] = [:]
            func find(_ x: Int) -> Int {
                if parent[x] == nil { parent[x] = x }
                if parent[x] == x { return x }
                parent[x] = find(parent[x]!)
                return parent[x]!
            }
            func union(_ a: Int, _ b: Int) {
                let ra = find(a), rb = find(b)
                if ra != rb { parent[rb] = ra }
            }
        }
        private var dsu = DSU()
        private var groupSegsByGid: [Int: [SCNNode]] = [:]
        private var groupLensByGid: [Int: [Float]] = [:]
        private var selectedNodeID: Int?
        private var connectionGroupsByParent: [Int: SCNNode] = [:]
        private var lastSelectedId: Int?

        var nodeIDs: [ObjectIdentifier: Int] = [:]
        private struct Connection {
            let from: Int
            let to: Int
            let container: SCNNode
            let segments: [SCNNode]
            var  lengths: [Float]
        }
        
        private var connections: [Connection] = []
        private var connectionsByNode: [Int: [Int]] = [:]
        private var idsByLayer: [[Int]] = []
        private func resolvedLineColor(_ trait: UITraitCollection) -> UIColor {
            // Respect the user's AppearanceOption first, fall back to system
            let style: UIUserInterfaceStyle = {
                if let scheme = selectedAppearance.colorScheme {
                    return (scheme == .dark) ? .dark : .light
                }
                return trait.userInterfaceStyle
            }()
            
            // Tweak alphas to taste
            if style == .dark {
                return UIColor(white: 1.0, alpha: 0.82)   // "whiter" in dark
            } else {
                return UIColor(white: 0.0, alpha: 0.70)   // "darker" in light
            }
        }
        private func resamplePolyline(_ pts: [SIMD3<Float>], desiredSegments n: Int) -> [SIMD3<Float>] {
            guard pts.count >= 2, n >= 1 else { return pts }
            // cumulative distances
            var d: [Float] = [0]
            d.reserveCapacity(pts.count)
            for i in 1..<pts.count {
                d.append(d[i-1] + simd_length(pts[i] - pts[i-1]))
            }
            let total = max(d.last ?? 0, 1e-6)
            func point(at s: Float) -> SIMD3<Float> {
                // find segment
                var lo = 0, hi = d.count - 1
                while lo + 1 < hi {
                    let mid = (lo + hi) >> 1
                    if d[mid] < s { lo = mid } else { hi = mid }
                }
                let t = (s - d[lo]) / max(d[lo+1] - d[lo], 1e-6)
                return simd_mix(pts[lo], pts[lo+1], SIMD3<Float>(repeating: t))
            }
            var out: [SIMD3<Float>] = []
            out.reserveCapacity(n+1)
            for i in 0...n {
                let s = (Float(i) / Float(n)) * total
                out.append(point(at: s))
            }
            return out
        }
        private func currentEdgePolyline(from a: SCNNode, to b: SCNNode) -> [SIMD3<Float>] {
            let rFrom = radiusForAnchor(a)
            let rTo   = radiusForAnchor(b)
            let segCountArc = edgeSegments(forRadius: Float(rFrom), camR: maxRadius)
            let arcPts = sampleSphericalArcPoints(from: a.presentation.position,
                                                  to:   b.presentation.position,
                                                  onRadius: Float(rFrom),
                                                  segments: segCountArc)
            if rFrom == rTo { return arcPts }
            let dirTo = unitDir(from: b.presentation.position)
            let segCountRadial = max(8, segCountArc / 2)
            let bridge = sampleRadialPoints(direction: dirTo,
                                            fromRadius: Float(rFrom),
                                            toRadius:   Float(rTo),
                                            segments:   segCountRadial)
            var all = arcPts
            all.append(contentsOf: bridge)
            return all
        }
        private func retargetConnection(at index: Int) {
            guard index >= 0 && index < connections.count else { return }
            var conn = connections[index]
            guard let a = anchorByNumber[conn.from], let b = anchorByNumber[conn.to] else { return }
            
            // 1) compute fresh polyline, then resample to EXACTLY segments.count
            let poly   = currentEdgePolyline(from: a, to: b)
            let points = resamplePolyline(poly, desiredSegments: conn.segments.count)
            
            guard points.count == conn.segments.count + 1 else { return }
            
            // 2) update each segment node’s geometry (2 verts per line)
            var newLens: [Float] = []
            newLens.reserveCapacity(conn.segments.count)
            
            for i in 0..<conn.segments.count {
                let A = points[i], B = points[i+1]
                var positions: [Float] = [A.x, A.y, A.z, B.x, B.y, B.z]
                var indices:   [UInt32] = [0, 1]
                
                let vData = Data(buffer: positions.withUnsafeBufferPointer { $0 })
                let iData = Data(buffer: indices.withUnsafeBufferPointer   { $0 })
                
                let src = SCNGeometrySource(
                    data: vData, semantic: .vertex, vectorCount: 2,
                    usesFloatComponents: true, componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                    dataStride: MemoryLayout<Float>.size * 3
                )
                let elem = SCNGeometryElement(
                    data: iData, primitiveType: .line,
                    primitiveCount: 1,
                    bytesPerIndex: MemoryLayout<UInt32>.size
                )
                
                // Keep material (and its animated color) intact
                let segNode = conn.segments[i]
                let oldMat = segNode.geometry?.firstMaterial
                
                let geo = SCNGeometry(sources: [src], elements: [elem])
                if let m = oldMat { geo.firstMaterial = m }
                segNode.geometry = geo
                
                newLens.append(simd_length(B - A))
            }
            
            // 3) store fresh per-segment lengths so the next appear/disappear pass is correct
            conn.lengths = newLens
            connections[index] = conn
        }
        private func retargetEdgesForNodes(_ ids: Set<Int>) {
            var idxs = Set<Int>()
            for id in ids {
                if let list = connectionsByNode[id] { idxs.formUnion(list) }
            }
            for i in idxs { retargetConnection(at: i) }
        }
        private func makeSymbolPlane(side: CGFloat, symbolName: String) -> SCNNode {
            let base = symbolName
                .replacingOccurrences(of: ".circle.fill", with: "")
                .replacingOccurrences(of: ".circle", with: "")
            let fillSymbol = "\(base).circle.fill"
            
            let iconWrapper = SCNNode()
            iconWrapper.name = "icon"
            
            func makePlane(maskSymbol: String, color: UIColor) -> SCNNode? {
                guard let img = SymbolImageCache.image(named: maskSymbol) else { return nil }
                let plane = SCNPlane(width: side, height: side)
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = color
                m.transparent.contents = img
                m.transparencyMode = .aOne
                m.isDoubleSided = true
                m.readsFromDepthBuffer = false
                m.writesToDepthBuffer = false
                m.blendMode = .alpha
                plane.firstMaterial = m
                let node = SCNNode(geometry: plane)
                node.renderingOrder = 2500
                return node
            }
            
            // 🔑 use the effective style, never `.unspecified`
            let systemStyle: UIUserInterfaceStyle = (parent.systemColorScheme == .dark) ? .dark : .light
            let style = lastAppliedScheme
            ?? effectiveStyle(selectedAppearance: parent.selectedAppearance, systemStyle: systemStyle)
            
            if let fillNode = makePlane(maskSymbol: fillSymbol, color: Theme.iconFill(for: style)) {
                iconWrapper.addChildNode(fillNode)
            }
            return iconWrapper
        }
        private func setButtonHighlighted(_ button: SCNNode, _ highlighted: Bool) {
            if let icon = button.childNode(withName: "icon", recursively: false) {
                // find the first SCNPlane under the icon wrapper
                let planeNode = icon.childNodes.first { $0.geometry is SCNPlane }
                if let mat = planeNode?.geometry?.firstMaterial {
                    mat.diffuse.contents = highlighted ? Theme.iconHighlight : Theme.iconFill
                }
            }
        }
        private func makeEyeNode(side: CGFloat) -> SCNNode {
            let icon = makeSymbolPlane(side: side, symbolName: "eye.circle.fill")
            
            let hit = SCNPlane(width: side * 1.8, height: side * 1.8)
            let mh = SCNMaterial()
            mh.diffuse.contents = UIColor.clear
            mh.isDoubleSided = true
            mh.readsFromDepthBuffer = false
            mh.writesToDepthBuffer = false
            hit.firstMaterial = mh
            
            let hitNode = SCNNode(geometry: hit)
            hitNode.name = "hit"
            hitNode.categoryBitMask = 1 << 0
            hitNode.renderingOrder = 2400
            
            let wrapper = SCNNode()
            wrapper.name = "eye"
            wrapper.addChildNode(icon)
            wrapper.addChildNode(hitNode)
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.categoryBitMask = 1 << 0
            return wrapper
        }
        private func recordActivityThrottled() {
            let now = CACurrentMediaTime()
            guard now - lastActivityStamp >= activityCooldown else { return }
            lastActivityStamp = now
            DispatchQueue.main.async { self.parent.onActivity?() }
            resetInactivityTimer()
        }
        private func markActivityAndResetTimer() {
            lastActivityStamp = CACurrentMediaTime()
            resetInactivityTimer()
        }
        private func resetInactivityTimer() {
            inactivityTimer?.cancel()
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now() + activityCooldown)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                let now = CACurrentMediaTime()
                if now - self.lastActivityStamp >= self.activityCooldown {
                    DispatchQueue.main.async { self.parent.onInactivity?() }
                    // keep watching for the next inactivity window
                    self.lastActivityStamp = now
                }
                self.resetInactivityTimer()
            }
            inactivityTimer = timer
            timer.resume()
        }
        private var isGroupActive: Bool {
            return !currentSelectedGroup.isEmpty
        }
        private var isResettingCamera = false
        
        private func updateCameraOrbit() {
            let rMin = minZoom(for: focusAnchor)
            camRadius = max(rMin, min(maxRadius, camRadius))
            rig?.position = orbitCenter
            yawNode?.eulerAngles.y = yaw
            pitchNode?.eulerAngles.x = pitch
            cameraNode?.position = SCNVector3(0, 0, camRadius)
            
            
            updateTopChromeVisibility()
            
            if didRenderOnce && !isGroupActive && parent.selectedName == nil{
                let rWorld = cameraDistanceFromWorldOrigin()
                //updateFogForShellCrossings(currentCameraRadius: rWorld)
            }
            
        }
        @objc func observeTwoFingerPan(_ g: UIPanGestureRecognizer) {
            observePan(g)
        }
        private func applySelection(for id: Int?) {
      
            if currentSelectedGroup.isEmpty {
                
                for (idx, wrapper) in labelByNumber {
                    setLabelHighlighted(wrapper, id == idx)
                }
            
                
                
                // 3) Focus camera / filter connections (unchanged)
                if let id, let anchorNode = (labelByNumber[id]?.parent ?? labelByNumber[id]) {
                    focusAnchor = anchorNode
                    let newCenter = anchorNode.presentation.worldPosition
                    let camWorld  = cameraNode?.presentation.worldPosition
                    ?? cameraNode?.worldPosition
                    ?? SCNVector3Zero
                    
                    let vx = Float(camWorld.x - newCenter.x)
                    let vy = Float(camWorld.y - newCenter.y)
                    let vz = Float(camWorld.z - newCenter.z)
                    
                    let dist = sqrtf(vx*vx + vy*vy + vz*vz)
                    let rMin = minZoom(for: anchorNode)
                    let targetR = max(rMin, min(maxRadius, dist))
                    let targetYaw   = wrap(atan2f(vx, vz))
                    let horiz       = max(1e-6, sqrtf(vx*vx + vz*vz))
                    let targetPitch = wrap(atan2f(-vy, horiz), period: 2 * .pi)
                    
                    recenter = RecenterAnim(
                        t0: lastUpdateTime ?? 0,
                        dur: 0.28,
                        startCenter: orbitCenter,
                        endCenter:   newCenter,
                        startYaw:    yaw,
                        endYaw:      targetYaw,
                        startPitch:  pitch,
                        endPitch:    targetPitch,
                        startR:      camRadius,
                        endR:        targetR
                    )
                    
                    focusAnchor = anchorNode
                

                    if lastSelectedId != id {
                        parent.openModelCard = true
                        lastSelectedId = id
                    } else {
                        lastSelectedId = nil
                        parent.openModelCard = false
                        clearSelection()
                        filterConnections(for: nil)
                    }
                    
                } else {
                    clearSelection()
                    filterConnections(for: nil)
                }
            } else {
                
                
                if let id, let anchorNode = (labelByNumber[id]?.parent ?? labelByNumber[id]) {
                    focusAnchor = anchorNode
                    let newCenter = anchorNode.presentation.worldPosition
                    let camWorld  = cameraNode?.presentation.worldPosition
                    ?? cameraNode?.worldPosition
                    ?? SCNVector3Zero
                    
                    let vx = Float(camWorld.x - newCenter.x)
                    let vy = Float(camWorld.y - newCenter.y)
                    let vz = Float(camWorld.z - newCenter.z)
                    
                    let dist = sqrtf(vx*vx + vy*vy + vz*vz)
                    let rMin = minZoom(for: anchorNode)
                    let targetR = max(rMin, min(maxRadius, dist))
                    let targetYaw   = wrap(atan2f(vx, vz))
                    let horiz       = max(1e-6, sqrtf(vx*vx + vz*vz))
                    let targetPitch = wrap(atan2f(-vy, horiz), period: 2 * .pi)
                    
                    recenter = RecenterAnim(
                        t0: lastUpdateTime ?? 0,
                        dur: 0.28,
                        startCenter: orbitCenter,
                        endCenter:   newCenter,
                        startYaw:    yaw,
                        endYaw:      targetYaw,
                        startPitch:  pitch,
                        endPitch:    targetPitch,
                        startR:      camRadius,
                        endR:        targetR
                    )
                    
                    focusAnchor = anchorNode
                    
                    if lastSelectedId != id {
                        parent.openModelCard = true
                        lastSelectedId = id
                    } else {
                        lastSelectedId = nil
                        parent.openModelCard = false
                        clearSelection()
                    }
                } else {
                    clearSelection()
                }
            }
        }
        private func clearSelection() {
            
            if currentSelectedGroup.isEmpty {
                selectedNodeID = nil
                
                for ln in labelNodes {
                    setLabelHighlighted(ln, true)
                    // remove any attached buttons
                    if let wrapper = (ln.name == "labelWrapper") ? ln : ln.parent {
                        removeButtons(from: wrapper)
                    }
                }
                focusAnchor = nil
                let newCenter = SCNVector3(0, 0, 0)
                
                
                let camWorld = cameraNode?.presentation.worldPosition
                ?? cameraNode?.worldPosition
                ?? SCNVector3(0, 0, 0)
                
                
                let vx = Float(camWorld.x - newCenter.x)
                let vy = Float(camWorld.y - newCenter.y)
                let vz = Float(camWorld.z - newCenter.z)
                
                let dist = sqrtf(vx*vx + vy*vy + vz*vz)
                
                // No focus here → pass nil
                let rMin = minZoom(for: nil)
                
                let targetR = max(rMin, min(maxRadius, dist))
                let targetYaw   = wrap(atan2f(vx, vz))
                let horiz       = max(1e-6, sqrtf(vx*vx + vz*vz))
                let targetPitch = wrap(atan2f(-vy, horiz), period: 2 * .pi)
                
                
                let startCenter = orbitCenter
                let startYaw    = yaw
                let startPitch  = pitch
                let startR      = camRadius
                
                
                recenter = RecenterAnim(
                    t0: lastUpdateTime ?? 0,
                    dur: 0.28,
                    startCenter: startCenter,
                    endCenter:   newCenter,
                    startYaw:    startYaw,
                    endYaw:      targetYaw,
                    startPitch:  startPitch,
                    endPitch:    targetPitch,
                    startR:      startR,
                    endR:        targetR
                )
                cameraNode?.constraints = nil
                lookConstraint = nil
                filterConnections(for: nil)
            } else {
                selectedNodeID = nil
                
                focusAnchor = nil
                let newCenter = SCNVector3(0, 0, 0)
                
                
                let camWorld = cameraNode?.presentation.worldPosition
                ?? cameraNode?.worldPosition
                ?? SCNVector3(0, 0, 0)
                
                
                let vx = Float(camWorld.x - newCenter.x)
                let vy = Float(camWorld.y - newCenter.y)
                let vz = Float(camWorld.z - newCenter.z)
                
                let dist = sqrtf(vx*vx + vy*vy + vz*vz)
                
                // No focus here → pass nil
                let rMin = minZoom(for: nil)
                
                let targetR = max(rMin, min(maxRadius, dist))
                let targetYaw   = wrap(atan2f(vx, vz))
                let horiz       = max(1e-6, sqrtf(vx*vx + vz*vz))
                let targetPitch = wrap(atan2f(-vy, horiz), period: 2 * .pi)
                
                
                let startCenter = orbitCenter
                let startYaw    = yaw
                let startPitch  = pitch
                let startR      = camRadius
                
                
                recenter = RecenterAnim(
                    t0: lastUpdateTime ?? 0,
                    dur: 0.28,
                    startCenter: startCenter,
                    endCenter:   newCenter,
                    startYaw:    startYaw,
                    endYaw:      targetYaw,
                    startPitch:  startPitch,
                    endPitch:    targetPitch,
                    startR:      startR,
                    endR:        targetR
                )
                cameraNode?.constraints = nil
                lookConstraint = nil
                
            }
        }
    
        private func minZoom(for anchor: SCNNode?) -> Float {
            // baseline when nothing is focused
            let base = max(0.05, Float(coreRadiusValue) * 0.35)
            
            guard let a = anchor else { return base }
            
            if isCoreAnchor(a) {                // extra close if focusing the core
                return max(0.02, Float(coreRadiusValue) * 0.20)
            }
            
            let shellR = radiusForAnchor(a)     // friendlier when focusing a shell node
            return max(0.02, shellR * 0.02)
        }
        private func layoutAnchorsOnSphereOrdered() {
            // Golden angle for nice even distribution around longitude
            let goldenAngle: Float = Float.pi * (3.0 - sqrt(5.0)) // ≈ 2.399963...
            
            for (layerIdx, idsInLayer) in idsByLayer.enumerated() {
                guard !idsInLayer.isEmpty else { continue }
                
                // radius of this layer
                let R = Float(radiusValues[layerIdx])
                // sort ascending so order is deterministic low→high
                let sorted = idsInLayer.sorted()
                
                let n = Float(sorted.count)
                for (i, nodeID) in sorted.enumerated() {
                    guard let anchor = anchorByNumber[nodeID] else { continue }
                    
                    // map index→latitude monotonic: y goes from ~+1 (north) to ~-1 (south)
                    // Use i+0.5 to avoid placing exactly on the poles
                    let k   = Float(i) + 0.5
                    let y   = 1.0 - 2.0 * (k / n)              // [-1, 1]
                    let r   = max(0.0, sqrt(1.0 - y*y))        // radial component on unit circle
                    let phi = goldenAngle * k                  // longitudes wrap around
                    
                    let x = r * cos(phi)
                    let z = r * sin(phi)
                    
                    anchor.position = SCNVector3(x * R, y * R, z * R)
                }
            }
        }
        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard let v = view else { return }
            let p = g.location(in: v)
            
            let hits = v.hitTest(p, options: [
                .categoryBitMask: 1 << 0,
                .backFaceCulling: false,
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            
            
            
            
            switch g.state {
            case .began, .changed:
                
                let btn = buttonFrom(hits.first?.node)
                for cand in [btn].compactMap({ $0 }) {
                    setButtonHighlighted(cand, true)
                }
                
                if btn == nil {
                    for (_, close) in closeByLabel { setButtonHighlighted(close, false) }
                    for (_, eye)   in eyeByLabel   { setButtonHighlighted(eye,   false) }
                    for (_, play)  in playByLabel  { setButtonHighlighted(play,  false) }
                }
                
                
            case .ended, .cancelled, .failed:
                
                for (_, close) in closeByLabel { setButtonHighlighted(close, false) }
                for (_, eye)   in eyeByLabel   { setButtonHighlighted(eye,   false) }
                for (_, play)  in playByLabel  { setButtonHighlighted(play,  false) }
                
                
            default: break
            }
        }
        private func atlasUVTransform(_ rect: CGRect) -> SCNMatrix4 {
            // rect is normalized in [0,1] in UIKit space (origin = top-left).
            // Convert to GL-style bottom-left.
            let vMin = 1.0 - rect.origin.y - rect.size.height
            
            var m = SCNMatrix4Identity
            m = SCNMatrix4Translate(m, Float(rect.origin.x), Float(vMin), 0)
            m = SCNMatrix4Scale(m, Float(rect.size.width), Float(rect.size.height), 1)
            return m
        }
        private let overlayEdgeMarginDeg: Float = 0.05
        private let overlayRadialBloat:   Float = 0.015 // +1.5% radius for the overlay geometry
        private let dimScale: Float = 0.5  // tweak: 0.65–0.85 looks nice

        @inline(__always)
        private func scaleFor(alpha: CGFloat, base: SCNVector3) -> SCNVector3 {
            // alpha ∈ [0,1]  →  scale ∈ [dimScale, 1]
            let t = Float(max(0, min(1, alpha)))
            let s = dimScale + (1 - dimScale) * t
            return SCNVector3(base.x * s, base.y * s, base.z * s)
        }
        private var _lastVisualTarget: [ObjectIdentifier: (alpha: CGFloat, scale: SCNVector3)] = [:]
        private func setWrapperAlphaAndScale(
            _ wrapper: SCNNode,
            to alpha: CGFloat,
            duration: TimeInterval = 0.10
        ) {
            let key  = ObjectIdentifier(wrapper)
            let base = baseScaleByLabel[key] ?? wrapper.scale
            let targetScale = scaleFor(alpha: alpha, base: base)

            // If current target matches the last one, do nothing
            if let last = _lastVisualTarget[key],
               abs(last.alpha - alpha) < 0.001,
               approxEqual(last.scale, targetScale) {
                return
            }

            // Also skip if the node is already visually at target (helps on first call)
            if abs(CGFloat(wrapper.opacity) - alpha) < 0.001,
               approxEqual(wrapper.scale, targetScale) {
                _lastVisualTarget[key] = (alpha, targetScale)
                return
            }
            

            // Record new target
            _lastVisualTarget[key] = (alpha, targetScale)

            // Animate to target
            wrapper.removeAction(forKey: "fadeOpacity")
            let fade = SCNAction.fadeOpacity(to: alpha, duration: duration)
            wrapper.runAction(fade, forKey: "fadeOpacity")

            wrapper.removeAction(forKey: "fadeScale")
            let scale = SCNAction.customAction(duration: duration) { node, t in
                let u = duration == 0 ? 1 : CGFloat(t) / CGFloat(duration)
                let ix = CGFloat(base.x) + (CGFloat(targetScale.x) - CGFloat(base.x)) * u
                let iy = CGFloat(base.y) + (CGFloat(targetScale.y) - CGFloat(base.y)) * u
                let iz = CGFloat(base.z) + (CGFloat(targetScale.z) - CGFloat(base.z)) * u
                node.scale = SCNVector3(ix, iy, iz)
            }
            wrapper.runAction(scale, forKey: "fadeScale")
        }
        private var coreSpinNode: SCNNode?
        private var coreSpinAngle: Float = 0
        private let coreSpinSpeed: Float = .pi / 12 // radians/sec (~15°/sec). Adjust if you want faster/slower.

        @inline(__always)
        private func approxEqual(_ a: SCNVector3, _ b: SCNVector3, eps: Float = 0.001) -> Bool {
            return abs(a.x - b.x) < eps && abs(a.y - b.y) < eps && abs(a.z - b.z) < eps
        }
        private func stageNodeReveal(_ node: SCNNode,
                                     index: Int,
                                     step: TimeInterval = 0.5,
                                     fade: TimeInterval = 0.25,
                                     key: String = "stageNodeReveal")
        {
            let target = node.opacity   // preserve intended final alpha
            node.removeAction(forKey: key)
            node.opacity = 0.0          // start hidden

            let wait   = SCNAction.wait(duration: max(0, Double(index)) * step)
            let fadeIn = SCNAction.fadeOpacity(to: target, duration: fade)
            fadeIn.timingMode = .easeInEaseOut

            node.runAction(.sequence([wait, fadeIn]), forKey: key)
        }


        func updateGroupLayout(group: [Int], around selected: Int) {
            guard
                !group.isEmpty,
                let centerAnchor = anchorByNumber[selected]
            else { return }
            guard !isResettingCamera else { return }  // <-- new
            guard !cameraSnappedForGroup else {return}
            // 0) Clear overlays (no animation)
            for n in groupOverlayNodes { n.removeFromParentNode() }
            groupOverlayNodes.removeAll()
            
            // --- basis from the selected ---
            let u0: simd_float3 = unitDir(from: centerAnchor.presentation.worldPosition)
            let arbitrary = simd_float3(0, 1, 0)
            let useX = abs(simd_dot(u0, arbitrary)) > 0.95
            var u1 = simd_normalize(simd_cross(u0, useX ? simd_float3(1, 0, 0) : arbitrary))
            if simd_length(u1) < 1e-5 { u1 = simd_float3(1, 0, 0) }
            let u2 = simd_normalize(simd_cross(u0, u1))
            
            // --- overlay bloat (keeps circle visible around nodes) ---
            let overlayEdgeMarginDeg: Float = 3.0   // angular growth of the cap (2°–6° is typical)
            let overlayRadialBloat:   Float = 0.015 // +1.5% radius to avoid coplanarity/z-fighting
            
            
            
            // --- spread scaling config (no outer tightening) ---
            let Rmin = Float(radiusValues.min() ?? 1)
            let Rmax = Float(radiusValues.max() ?? CGFloat(Rmin))
            let innerBoost: Float  = 1.0
            let outerShrink: Float = 1.0
            func spreadScale(for R: Float) -> Float {
                guard Rmax > Rmin else { return 1 }
                let t = max(0, min(1, (R - Rmin) / (Rmax - Rmin))) // 0 inner → 1 outer
                return innerBoost + (outerShrink - innerBoost) * t
            }
            
            @inline(__always)
            func nodeVisualRadius(_ n: SCNNode) -> Float {
                // Try geometry bounding sphere (respects scale), fall back to a small default
                if let g = n.geometry {
                    let sphere = g.boundingSphere
                    let r = Float(sphere.radius) * Float(n.scale.x) // assume uniform scale
                    if r.isFinite && r > 0 { return r }
                }
                return 0.01 // ~1 cm fallback; tweak for your scene units
            }
            
            // Ensure the selected is first (θ = 0), others follow
            let others = group.filter { $0 != selected }
            let orderedGroup = [selected] + others
            
            // --- global spacing params ---
            let golden: Float = .pi * (3.0 - sqrtf(5.0))
            let gamma:  Float = 0.2                 // 0 = no correction, 1 ≈ constant arc length
            let innerFactor: Float = 1.6            // inner shell angular boost
            let innerPower:  Float = 1.0
            
            let minSepWorld: Float = 0.06           // world "don’t get too close"
            let relaxIters = 6
            
            @inline(__always)
            func thetaCap(for rShell: Float, nTotal: Int) -> Float {
                let baseThetaMax = min(0.40, 0.08 + 0.04 * sqrtf(Float(nTotal)))
                let thetaBaseByR = baseThetaMax * pow(max(1e-6, Rmin) / max(1e-6, rShell), gamma)
                let tRadius = max(0, min(1, (rShell - Rmin) / max(1e-6, (Rmax - Rmin))))
                return thetaBaseByR * (1 + (innerFactor - 1) * pow(1 - tRadius, innerPower))
            }
            
            // 1) Move nodes and collect per-radius buckets
            struct Bucket { var dirs = [SIMD3<Float>](); var pts = [SIMD3<Float>]() }
            var bucketsByRadius = [Float: Bucket]()
            
            struct Shell { var ids = [Int]() }
            var shells = [Float: Shell]()
            
            for id in orderedGroup {
                if let a = anchorByNumber[id] {
                    let r = radiusForAnchor(a)
                    var sh = shells[r] ?? Shell()
                    sh.ids.append(id)
                    shells[r] = sh
                }
            }
            
            @inline(__always)
            func normRadius(_ r: Float, _ Rmin: Float, _ Rmax: Float) -> Float {
                guard Rmax > Rmin else { return 0 }
                return max(0, min(1, (r - Rmin) / (Rmax - Rmin)))
            }
            
            @inline(__always)
            func outerBoost(_ t: Float, bias: Float, power: Float) -> Float {
                // bias the start, then ease with a power curve
                let u = max(0, min(1, (t - bias) / max(1e-6, 1 - bias)))
                return pow(u, power)
            }
            
            
            for (rShell, shell) in shells {
                // Base cap span for this shell
                let thetaMaxR = thetaCap(for: rShell, nTotal: orderedGroup.count)
                
                // Keep a floor so nodes don’t collide with the peak
                let thetaMinR = minSepWorld / max(1e-6, rShell)
                let thetaMin  = thetaMinR * 1.25
                
                // The actual cap rim we draw/fill to
                let capTheta  = min(.pi - 1e-4, thetaMaxR + overlayEdgeMarginDeg * .pi / 180)
                
                // ---- Preserve preview (phi, theta) instead of collapsing to a ring
                var ids = shell.ids
                if let selIdx = ids.firstIndex(of: selected) { ids.swapAt(0, selIdx) }

                struct Ang { let id: Int; let phi: Float; let theta: Float }
                var angles: [Ang] = []

                @inline(__always)
                func wrapAngle(_ x: Float) -> Float {
                    var a = fmodf(x, 2 * .pi)
                    if a <= -Float.pi { a += 2 * .pi }
                    if a >  Float.pi  { a -= 2 * .pi }
                    return a
                }

                // Gather preview angles from current positions
                for id in ids {
                    guard let a = anchorByNumber[id] else { continue }
                    let d   = unitDir(from: a.presentation.worldPosition)
                    let cu0 = simd_dot(d, u0)
                    let cu1 = simd_dot(d, u1)
                    let cu2 = simd_dot(d, u2)
                    let theta = acos(max(-1, min(1, cu0)))   // 0 at peak, grows toward rim
                    let phi   = atan2(cu2, cu1)              // (-π, π], around u0 in u1/u2 plane
                    angles.append(Ang(id: id, phi: phi, theta: theta))
                }

                // Normalize original θ into [0,1] based on what we observed in this shell (excluding selected)
                let nonSel = angles.filter { $0.id != selected }
                let observedMaxTheta = max(nonSel.map(\.theta).max() ?? 0, 1e-6)

                // Easing for radial mapping: <1.0 packs near the peak, >1.0 pushes toward rim
                let radialGamma: Float = 0.85

                // --- NEW: enforce equal azimuth spacing while preserving order ---
                // Sort by current phi so "left/right" relation is preserved
                let byPhi = angles.sorted { $0.phi < $1.phi }
                let N = byPhi.count
                guard N > 0 else { continue }
                let dPhi = 2 * Float.pi / Float(N)

                // Choose a stable starting azimuth to minimize sudden rotation.
                // Use the original phi of the first element as the anchor.
                let phi0 = byPhi.first!.phi

                // Build mapping: id -> evenly spaced phi, in the same cyclic order as byPhi
                var targetPhi = [Int: Float]()
                for (i, ainfo) in byPhi.enumerated() {
                    targetPhi[ainfo.id] = wrapAngle(phi0 + Float(i) * dPhi)
                }

                // Write targets (NO animation), keep your spreadScale on tangential part
                for ainfo in byPhi {
                    guard let a = anchorByNumber[ainfo.id] else { continue }

                    // Selected stays at the peak (θ = 0); azimuth is irrelevant there.
                    let thetaMapped: Float = {
                        if ainfo.id == selected { return 0 }
                        let t = max(0, min(1, ainfo.theta / observedMaxTheta))
                        let tEased = pow(t, radialGamma)
                        return thetaMin + (capTheta - thetaMin) * tEased
                    }()

                    let cth = cos(thetaMapped), sth = sin(thetaMapped)
                    let phi = targetPhi[ainfo.id] ?? ainfo.phi
                    let cph = cos(phi), sph = sin(phi)

                    // Optional shell-dependent spread
                    let s = spreadScale(for: rShell)

                    // Compose direction from basis; apply spread to tangential component
                    let tangential = (u1 * cph + u2 * sph) * sth * s
                    let dir = simd_normalize(u0 * cth + tangential)

                    // Sit slightly above an inflated cap radius so nodes are visibly on the surface
                    let rCap  = rShell * (1 + overlayRadialBloat)
                    let lift  = max(nodeVisualRadius(a) * 0.60, 0.004)
                    let rNode = rCap + lift
                    let target = dir * rNode

                    a.removeAllActions()
                    a.position = SCNVector3(target)

                    var b = bucketsByRadius[rShell] ?? Bucket()
                    b.dirs.append(dir)
                    b.pts.append(target)
                    bucketsByRadius[rShell] = b
                }
            }
            
            @inline(__always)
            func makeSphericalCapMesh(u0: SIMD3<Float>, u1: SIMD3<Float>, u2: SIMD3<Float>,
                                      rShell: Float,
                                      thetaRim: Float,
                                      radialBloat: Float = 0.015,
                                      segR: Int = 24,
                                      segPhi: Int = 96,
                                      color: UIColor,
                                      alpha: CGFloat = 0.12) -> SCNNode
            {
                // Slightly bloat to avoid z-fighting with nodes/edges
                let r = rShell * (1 + radialBloat)
                
                // Build vertex grid in (ρ, φ) where ρ ∈ [0, 1] maps to θ ∈ [0, thetaRim]
                var positions = [SIMD3<Float>]()
                positions.reserveCapacity((segR + 1) * (segPhi + 1))
                
                for i in 0...segR {
                    let t = Float(i) / Float(segR)                 // 0 at peak → 1 at rim
                    let theta = thetaRim * t
                    let cth = cos(theta), sth = sin(theta)
                    
                    for j in 0...segPhi {
                        let phi = (2 * .pi) * Float(j) / Float(segPhi)
                        let cph = cos(phi), sph = sin(phi)
                        
                        let dir = simd_normalize(u0 * cth + (u1 * cph + u2 * sph) * sth)
                        positions.append(dir * r)
                    }
                }
                
                // Triangles
                var indices = [UInt32]()
                indices.reserveCapacity(segR * segPhi * 6)
                
                let stride = segPhi + 1
                for i in 0..<segR {
                    for j in 0..<segPhi {
                        let a = UInt32(i * stride + j)
                        let b = UInt32((i + 1) * stride + j)
                        let c = UInt32((i + 1) * stride + (j + 1))
                        let d = UInt32(i * stride + (j + 1))
                        
                        // two triangles (a,b,c) (a,c,d)
                        indices.append(contentsOf: [a, b, c, a, c, d])
                    }
                }
                
                // SceneKit geometry
                let posData = Data(bytes: positions, count: positions.count * MemoryLayout<SIMD3<Float>>.stride)
                let src = SCNGeometrySource(data: posData,
                                            semantic: .vertex,
                                            vectorCount: positions.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 3,
                                            bytesPerComponent: MemoryLayout<Float>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD3<Float>>.stride)
                
                let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
                let elem = SCNGeometryElement(data: idxData,
                                              primitiveType: .triangles,
                                              primitiveCount: indices.count / 3,
                                              bytesPerIndex: MemoryLayout<UInt32>.size)
                
                let geom = SCNGeometry(sources: [src], elements: [elem])
                
                // Simple unlit material for soft translucent cap
                let mat = SCNMaterial()
                mat.diffuse.contents  = color.withAlphaComponent(alpha)
                mat.emission.contents = color.withAlphaComponent(alpha)
                mat.isDoubleSided     = true
                mat.lightingModel     = .constant
                
                // OLD (occludes nodes behind)
                /// mat.readsFromDepthBuffer = true
                /// mat.writesToDepthBuffer = true
                
                // NEW (pure translucent overlay; never occludes)
                mat.readsFromDepthBuffer = false
                mat.writesToDepthBuffer  = false
                mat.blendMode            = .alpha    // ensure proper blending
                
                geom.materials = [mat]
                
                let node = SCNNode(geometry: geom)
                node.renderingOrder = -1  // draw beneath wires/nodes
                return node
            }
            
            
            let accent: UIColor = {
                if parent.selectedAccent == .default {
                    switch parent.selectedAppearance {
                    case .system:
                        return parent.colorScheme == .dark
                            ? .white   // system dark → white
                            : .black   // system light → black

                    case .light:        // aka `.white`
                        return .black

                    case .dark:         // aka `.black`
                        return .white
                    }
                } else {
                    return UIColor(parent.selectedAccent.color)
                }
            }()

            let root = sceneRoot ?? view?.scene?.rootNode
            
            @inline(__always)
            func circlePointsOnCap(theta capTheta: Float,
                                   u0: SIMD3<Float>, u1: SIMD3<Float>, u2: SIMD3<Float>,
                                   rShell: Float,
                                   segments: Int = 96,
                                   radialBloat: Float = 0.015) -> [SIMD3<Float>] {
                let cth = cos(capTheta), sth = sin(capTheta)
                let rOut = rShell * (1 + radialBloat)
                var pts = [SIMD3<Float>]()
                pts.reserveCapacity(segments)
                for i in 0..<segments {
                    let phi = (2 * .pi) * Float(i) / Float(segments)
                    let cph = cos(phi), sph = sin(phi)
                    let dir = simd_normalize(u0 * cth + (u1 * cph + u2 * sph) * sth)
                    pts.append(dir * rOut)
                }
                return pts
            }
            
            
            func stageOverlayReveal(_ node: SCNNode,
                                    index: Int,
                                    step: TimeInterval = 0.5,
                                    fade: TimeInterval = 0.25)
            {
                // Keep whatever the node’s intended final opacity is (usually 1.0).
                let targetOpacity = node.opacity

                // Start fully hidden, cancel any prior staged fade on this node only.
                node.removeAction(forKey: "stageOverlayReveal")
                node.opacity = 0.0

                // Build staggered wait + fade sequence.
                let wait = SCNAction.wait(duration: max(0, Double(index)) * step)
                let fadeIn = SCNAction.fadeOpacity(to: targetOpacity, duration: fade)
                fadeIn.timingMode = .easeInEaseOut

                let seq = SCNAction.sequence([wait, fadeIn])
                node.runAction(seq, forKey: "stageOverlayReveal")
            }
            
            let sortedShellsAsc = bucketsByRadius.keys.sorted() // smallest first

            for (idx, rShell) in sortedShellsAsc.enumerated() {
                guard let bucket = bucketsByRadius[rShell], !bucket.dirs.isEmpty else { continue }

                // ---------- existing overlay computations (capTheta, circlePts, etc.) ----------
                var thetaMaxSide: Float = 0
                for d in bucket.dirs {
                    let c0 = max(-1, min(1, simd_dot(d, u0)))
                    let th = acos(c0)
                    if th > 1e-3 { thetaMaxSide = max(thetaMaxSide, th) }
                }
                let capTheta = min(.pi - 1e-4, thetaMaxSide + overlayEdgeMarginDeg * .pi / 180)

                // --- overlays (unchanged) ---
                let circlePts = circlePointsOnCap(theta: capTheta,
                                                  u0: u0, u1: u1, u2: u2,
                                                  rShell: rShell,
                                                  segments: 128,
                                                  radialBloat: overlayRadialBloat)
                guard circlePts.count >= 2 else { continue }

                let wireNode = makeLineLoop(circlePts, color: accent, opacity: 1.0)
                root?.addChildNode(wireNode)
                groupOverlayNodes.append(wireNode)

                let capNode = makeSphericalCapMesh(u0: u0, u1: u1, u2: u2,
                                                   rShell: rShell,
                                                   thetaRim: capTheta,
                                                   radialBloat: overlayRadialBloat,
                                                   segR: 24, segPhi: 128,
                                                   color: accent, alpha: 0.12)
                root?.addChildNode(capNode)
                groupOverlayNodes.append(capNode)

                // Stagger overlays (existing)
                stageOverlayReveal(wireNode, index: idx)
                stageOverlayReveal(capNode,  index: idx)

                // --- NEW: stagger the ANCHORS + LABEL WRAPPERS for this shell too ---
                // find which ids live on this shell
                guard let shell = shells[rShell] else { continue }
                for id in shell.ids {
                    guard let anchor = anchorByNumber[id] else { continue }

                    // Anchors (node geometry)
                    // Ensure final "intended" node alpha (in-group = 1.0)
                    anchor.opacity = 1.0
                    stageNodeReveal(anchor, index: idx, key: "appear.anchor.\(id)")

                    // Label wrappers, if any
                    if let wrapper = labelByNumber[id] {
                        // If you want labels to appear with the nodes, do the same:
                        wrapper.opacity = 1.0
                        stageNodeReveal(wrapper, index: idx, key: "appear.wrapper.\(id)")
                    }
                }
            }
            
            
            // 3) Push non-group nodes out of each shell’s (non-inflated) cap (NO animation)
            let groupSet = Set(group).union([selected])
            let pad: Float = max(0.5 * (minSepWorld / max(Rmin, 1e-6)), 0.035)
            
            for (r, _) in bucketsByRadius {
                let eps: Float = 1e-3
                let thetaMaxR = thetaCap(for: r, nTotal: orderedGroup.count)
                
                for (id, anchor) in anchorByNumber {
                    if groupSet.contains(id) { continue }
                    let rr = radiusForAnchor(anchor)
                    if abs(rr - r) > eps { continue }
                    
                    let d = unitDir(from: anchor.presentation.worldPosition)
                    let cu0 = simd_dot(d, u0)
                    let cu1 = simd_dot(d, u1)
                    let cu2 = simd_dot(d, u2)
                    
                    let theta = acos(max(-1, min(1, cu0)))
                    let phi   = atan2(cu2, cu1)
                    
                    if theta < (thetaMaxR + pad) {
                        let thetaPrime = thetaMaxR + pad
                        let cth = cos(thetaPrime), sth = sin(thetaPrime)
                        let cph = cos(phi),        sph = sin(phi)
                        let newDir = simd_normalize(u0 * cth + (u1 * cph + u2 * sph) * sth)
                        let target = SIMD3<Float>(newDir.x * r, newDir.y * r, newDir.z * r)
                        
                        anchor.removeAllActions()
                        anchor.position = SCNVector3(target)
                    }
                }
            }
            
            let affected = Set(orderedGroup)

            filterConnectionsForGroup()
            
            if !cameraSnappedForGroup {
                // --- Improved camera framing (smooth, seam-safe, no hard snap) ---
                if let (rOut, bucket) = bucketsByRadius.max(by: { $0.key < $1.key }),
                   bucket.pts.count >= 3,
                   let selectedAnchor = anchorByNumber[selected]
                {
                    // 1) Recompute same rim points used for overlay (stable target)
                    var thetaMax: Float = 0
                    thetaMax = bucket.dirs.reduce(0) { acc, d in
                        let c0 = max(-1, min(1, simd_dot(d, u0)))
                        return max(acc, acos(c0))
                    }
                    let dTheta = overlayEdgeMarginDeg * .pi / 180
                    let capTheta = min(.pi - 1e-4, thetaMax + dTheta)
                    let circlePts = circlePointsOnCap(theta: capTheta,
                                                      u0: u0, u1: u1, u2: u2,
                                                      rShell: rOut, segments: 96,
                                                      radialBloat: overlayRadialBloat)

                    // 2) Stable aim point: pull barycenter toward the selected node to reduce drift
                    var capCenter = SIMD3<Float>(repeating: 0)
                    for p in circlePts { capCenter += p }
                    capCenter /= Float(circlePts.count)

                    let sel = selectedAnchor.presentation.worldPosition
                    let sel3 = SIMD3<Float>(Float(sel.x), Float(sel.y), Float(sel.z))
                    let aimBlend: Float = 0.55   // 0 = only cap center, 1 = only selected; 0.5–0.7 feels good
                    let aimPoint = sel3 * aimBlend + capCenter * (1 - aimBlend)

                    // Small lift toward u0 keeps UI feeling “peaked” and reduces occlusion
                    let lift: Float = 0.04 * rOut
                    let aim = aimPoint + u0 * lift

                    // 3) Compute yaw/pitch to face the aim point from current orbit center
                    // We’ll keep orbitCenter near the selected, but ease toward aim to avoid big recenter jumps
                    let desiredCenter = SIMD3<Float>(Float(sel.x), Float(sel.y), Float(sel.z))
                    let centerBlend: Float = 0.6
                    let newCenter = desiredCenter * centerBlend + aim * (1 - centerBlend)

                    // Direction from (future) center to aim
                    let dir = simd_normalize(aim - newCenter)
                    let dx = dir.x, dy = dir.y, dz = dir.z
                    let desiredYaw   = atan2f(dx, dz)                    // [-π, π]
                    let horiz        = max(1e-6, sqrtf(dx*dx + dz*dz))
                    let desiredPitch = atan2f(-dy, horiz)                // [-π, π]

                    // 4) Choose camera distance to *frame the entire cap*
                    // Use vertical FOV; add safety margins for UI and overlays
                    let fovDegrees = Float((cameraNode?.camera?.fieldOfView ?? 45.0))
                    let fov = max(5.0, min(120.0, fovDegrees)) * (.pi / 180)

                    // Cap radius as it appears around the aim direction: approximate with rOut * sin(capTheta)
                    // (works well because we’re looking roughly along u0 toward the cap)
                    let projectedRadius = rOut * sin(capTheta)
                    let margin = 1.18 as Float  // ~18% headroom for overlays and labels

                    // Distance so that projectedRadius fits inside half-viewport height: d = R / tan(FOV/2)
                    let desiredRadius = max(minZoom(for: selectedAnchor), projectedRadius / tan(fov * 0.5)) * margin

                    // 5) Smoothly ease yaw, pitch, radius, center with a critically-damped spring
                    // (No SCNActions needed; this runs per-update; if you’re calling from a gesture or tick, keep state)


                    if camSpringState == nil { camSpringState = CamSpringState() }

                    // Choose a time step (assuming updateGroupLayout is called on interaction frames)
                    let dt: Float = 1.0 / 60.0
                    let halflife: Float = 0.18 // ~180ms to converge most of the way
                    let k = springK(halflife: halflife)

                    // Unwrap angles to shortest path
                    let yawNow   = yaw
                    let pitchNow = pitch
                    let yawGoal  = unwrapAngle(to: desiredYaw, from: yawNow)
                    let pitGoal  = unwrapAngle(to: desiredPitch, from: pitchNow)

                    // Critically damped integration
                    yaw   = springStep(current: yawNow,   target: yawGoal,   vel: &camSpringState!.yawVel,   k: k, dt: dt)
                    pitch = springStep(current: pitchNow, target: pitGoal,   vel: &camSpringState!.pitchVel, k: k, dt: dt)

                    let radNow = camRadius
                    camRadius  = springStep(current: radNow,  target: desiredRadius, vel: &camSpringState!.radVel, k: k, dt: dt)

                    var oc = SIMD3<Float>(Float(orbitCenter.x), Float(orbitCenter.y), Float(orbitCenter.z))
                    oc = springStep3(current: oc, target: newCenter, vel: &camSpringState!.cxVel, k: k, dt: dt)
                    orbitCenter = SCNVector3(oc.x, oc.y, oc.z)

                    // Flag so we don’t re-initialize; still allows continuous smoothing while user scrubs
                    cameraSnappedForGroup = true
                    
                    // --- Upright roll fix: keep world-up pointing +Y without changing position/aim ---
                    if let cam = cameraNode {
                        // Read current world transform
                        let t = cam.presentation.simdTransform
                        let worldUp = SIMD3<Float>(0, 1, 0)
                        
                        // Camera's world-space up (Y column) and forward (-Z column)
                        let camUp  = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
                        let camFwd = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
                        
                        // If we're upside down, rotate around forward by π (roll only)
                        if simd_dot(camUp, worldUp) < 0 {
                            let axis = simd_normalize(camFwd)
                            let q = simd_quatf(angle: .pi, axis: axis)
                            cam.simdOrientation = simd_mul(q, cam.simdOrientation)
                        }
                    }

                }

            }
        
        }
        
        struct CamSpringState {
            var yawVel: Float = 0, pitchVel: Float = 0, radVel: Float = 0
            var cxVel: SIMD3<Float> = .zero
        }
        // Keep around as a stored property somewhere (e.g., on your controller)
        private var camSpringState: CamSpringState?

        @inline(__always)
        func unwrapAngle(to goal: Float, from current: Float) -> Float {
            var g = goal
            var c = current
            let twoPi: Float = 2 * .pi
            // Map both near each other
            let diff = fmodf(g - c + .pi, twoPi) - .pi
            return c + diff
        }

        // Critically damped spring constant from half-life (seconds)
        @inline(__always)
        func springK(halflife: Float) -> Float {
            // From exponential decay: k ≈ (ln 2) * 8 / halflife  (critically damped m=1)
            return (logf(2) * 8.0) / max(1e-4, halflife)
        }

        @inline(__always)
        func springStep(current x: Float, target r: Float, vel v: inout Float, k: Float, dt: Float) -> Float {
            // Critically damped spring (m=1, c=2*sqrt(k), stable for any dt)
            let c = 2.0 * sqrtf(k)
            let a = -k * (x - r) - c * v
            v += a * dt
            return x + v * dt
        }

        @inline(__always)
        func springStep3(current x: SIMD3<Float>, target r: SIMD3<Float>, vel v: inout SIMD3<Float>, k: Float, dt: Float) -> SIMD3<Float> {
            let c = 2.0 * sqrtf(k)
            let a = -k * (x - r) - c * v
            v += a * dt
            return x + v * dt
        }
        
        private var cameraSnappedForGroup: Bool = false
        private func clearGroupOverlays(animated: Bool = true, duration: TimeInterval = 0.18) {
            guard !groupOverlayNodes.isEmpty else { return }
            let nodes = groupOverlayNodes
            groupOverlayNodes.removeAll()

            guard animated else {
                nodes.forEach { $0.removeAllActions(); $0.removeFromParentNode() }
                return
            }

            for n in nodes {
                n.removeAllActions()
                if let m = n.geometry?.firstMaterial {
                    let from = CGFloat(m.transparency)
                    let fade = SCNAction.customAction(duration: duration) { _, t in
                        let u = duration == 0 ? 1 : CGFloat(t) / CGFloat(duration)
                        m.transparency = max(0, from * (1 - u))
                    }
                    n.runAction(.sequence([fade, .removeFromParentNode()]))
                } else {
                    n.removeFromParentNode()
                }
            }
        }
        func restoreOriginalNodePlacement(
            animated: Bool = true,
            duration: TimeInterval = 0.30,
            completion: (() -> Void)? = nil
        ) {
            let finish: () -> Void = { [weak self] in
                completion?()
                _ = self
            }

            // We only want to clear overlays (colors/highlights)
            isResettingCamera = true

            // This already restores original node appearance using existing logic
            clearGroupOverlays(animated: animated, duration: min(0.22, duration * 0.5))

            // Do NOT move nodes
            // Do NOT update camera
            // Do NOT retarget edges

            DispatchQueue.main.async { [weak self] in
                self?.isResettingCamera = false
                self?.cameraSnappedForGroup = false
                finish()
            }
        }
        func restoreOriginalNodePlacementOld(
            animated: Bool = true,
            duration: TimeInterval = 0.30,
            completion: (() -> Void)? = nil
        ) {
            var allNodeIDsSet: Set<Int> { Set(anchorByNumber.keys) }

            // We'll complete on the main queue in every path.
            let finish: () -> Void = { [weak self] in
                completion?()
                _ = self // keep weak self used
            }

            isResettingCamera = true
            clearGroupOverlays(animated: true, duration: min(0.22, duration * 0.5))

            guard !idsByLayer.isEmpty, !radiusValues.isEmpty else {
                // Nothing to do — release/reset + complete.
                isResettingCamera = false
                cameraSnappedForGroup = false
                finish()
                return
            }

            // Track async pieces: node moves, edge tracking, and SCNTransaction.
            let group = DispatchGroup()

            let golden: Float = .pi * (3.0 - sqrtf(5.0))
            for (layerIdx, idsInLayer) in idsByLayer.enumerated() {
                guard !idsInLayer.isEmpty else { continue }
                let R = Float(radiusValues[layerIdx])

                let sorted = idsInLayer.sorted()
                let n = Float(sorted.count)

                for (i, nodeID) in sorted.enumerated() {
                    guard let anchor = anchorByNumber[nodeID] else { continue }

                    let k   = Float(i) + 0.5
                    let y   = 1.0 - 2.0 * (k / n)
                    let r   = max(0.0, sqrtf(1.0 - y*y))
                    let phi = golden * k

                    let x = r * cosf(phi)
                    let z = r * sinf(phi)
                    let target = SCNVector3(x * R, y * R, z * R)

                    if animated {
                        let move = SCNAction.move(to: target, duration: duration)
                        move.timingMode = .easeInEaseOut
                        anchor.removeAction(forKey: "clusterMove")
                        group.enter()
                        anchor.runAction(move, forKey: "clusterMove") {
                            group.leave()
                        }
                    } else {
                        anchor.removeAllActions()
                        anchor.position = target
                    }
                }
            }

            // ==== keep edges in lockstep with the node reset ====
            let affected = allNodeIDsSet                     // every node can affect some edge
            let tracker  = sceneRoot ?? view?.scene?.rootNode
            tracker?.removeAction(forKey: "edgeTracking")    // cancel any prior tracking
            if animated {
                let follow = SCNAction.customAction(duration: duration) { [weak self] _, _ in
                    self?.retargetEdgesForNodes(affected)
                }
                let finalize = SCNAction.run { [weak self] _ in
                    self?.retargetEdgesForNodes(affected)    // final snap at end
                }
                if let tracker {
                    group.enter()
                    tracker.runAction(.sequence([follow, finalize]), forKey: "edgeTracking") {
                        group.leave()
                    }
                }
            } else {
                retargetEdgesForNodes(affected)               // instant update in no-anim path
            }

            let savedFocus = focusAnchor
            focusAnchor = nil
            if animated {
                // Include the camera SCNTransaction in our completion group.
                group.enter()
                SCNTransaction.begin()
                SCNTransaction.animationDuration = duration
                yaw = 0
                pitch = 0
                camRadius = maxRadius
                updateCameraOrbit()
                SCNTransaction.completionBlock = { [weak self] in
                    guard let self = self else { group.leave(); return }
                    self.focusAnchor = savedFocus
                    self.isResettingCamera = false    // <-- release
                    self.cameraSnappedForGroup = false
                    group.leave()
                }
                SCNTransaction.commit()

                // When ALL async bits are done, call the completion on main.
                group.notify(queue: .main) {
                    finish()
                }
            } else {
                // No animations — update immediately and complete.
                yaw = 0
                pitch = 0
                camRadius = maxRadius
                updateCameraOrbit()
                focusAnchor = savedFocus
                isResettingCamera = false
                cameraSnappedForGroup = false
                finish()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let v = view else { return }
            let p = gesture.location(in: v)

            let hits = v.hitTest(p, options: [
                .categoryBitMask: 1 << 0,
                .backFaceCulling: false,
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            // 1) Try to handle any button tap on ANY hit first.
            for h in hits {
                if let target = firstAncestor(namedIn: ["close", "play", "eye"], from: h.node) {
                    switch target.name {
                    case "close":
                        buttonTapFlash(target)
                        selectedNodeID = nil
                        parent.selectedName = nil
                        clearSelection()
                        return

                    case "play":
                        buttonTapFlash(target)
                        if let labelWrapper = labelNode(for: target),
                           let (idx, _) = labelByNumber.first(where: { $0.value === labelWrapper }) {
                            parent.openModelCard = true
                        }
                        return

                    case "eye":
                        buttonTapFlash(target)
                        if selectedNodeID != nil {
                            parent.isPreviewVisible = true
                        }
                        return

                    default:
                        break
                    }
                }
            }

            // 2) No button matched; handle label selection (skip nodes that belong to buttons).
            if let tappedWrapper = hits.lazy
                .compactMap({ hit -> SCNNode? in
                    let node = hit.node                     // Extract SCNNode from SCNHitTestResult
                    return self.hasButtonAncestor(node: node)    // Skip if part of a button
                        ? nil
                        : self.labelNode(for: node)         // Otherwise process label nodes
                })
                .first,
               let id = nodeIDs[ObjectIdentifier(tappedWrapper)] {

                if selectedNodeID == id {
                    selectedNodeID = nil
                    parent.selectedName = nil
                    clearSelection()
                } else {
                    selectedNodeID = id
                    parent.selectedName = id
                    applySelection(for: selectedNodeID)
                }
            }

        }

        // MARK: - Helpers

        private func firstAncestor(namedIn names: Set<String>, from node: SCNNode) -> SCNNode? {
            var n: SCNNode? = node
            while let cur = n {
                if let name = cur.name, names.contains(name) { return cur }
                n = cur.parent
            }
            return nil
        }

        private func hasButtonAncestor(node: SCNNode) -> Bool {
            return firstAncestor(namedIn: ["close", "play", "eye"], from: node) != nil
        }

        @inline(__always)
        private func isCoreAnchor(_ a: SCNNode?) -> Bool {
            
            return a?.parent?.name == "layer0"
        }
        
        private func appearSegmentsOnly(
            _ segments: [SCNNode],
            lengths: [Float],
            totalDuration: TimeInterval,
            color: UIColor,
            appearPortion: Double = 0.75
        ) {
            guard !segments.isEmpty, !lengths.isEmpty else { return }
            
            for seg in segments {
                if let m = seg.geometry?.firstMaterial {
                    m.diffuse.contents  = UIColor.clear
                    m.emission.contents = UIColor.clear
                    m.blendMode = .alpha
                }
            }
            
            let totalLen = max(1e-6, lengths.reduce(0, +))
            let appearDur = max(1e-6, totalDuration * appearPortion)
            
            func lerpColor(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
                var ar: CGFloat=0, ag: CGFloat=0, ab: CGFloat=0, aa: CGFloat=0
                var br: CGFloat=0, bg: CGFloat=0, bb: CGFloat=0, ba: CGFloat=0
                a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
                b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                return UIColor(red: ar+(br-ar)*t, green: ag+(bg-ag)*t, blue: ab+(bb-ab)*t, alpha: aa+(ba-aa)*t)
            }
            func tween(duration: TimeInterval, from: UIColor, to: UIColor) -> SCNAction {
                SCNAction.customAction(duration: duration) { node, elapsed in
                    guard let m = node.geometry?.firstMaterial else { return }
                    let tt = CGFloat(duration == 0 ? 1 : max(0, min(1, elapsed / CGFloat(duration))))
                    let c  = lerpColor(from, to, t: tt)
                    m.diffuse.contents  = c
                    m.emission.contents = c
                }
            }
            
            var acc: TimeInterval = 0
            for (i, seg) in segments.enumerated() {
                let ratio = TimeInterval(lengths[i] / totalLen)
                let segDur = appearDur * ratio
                let wait = SCNAction.wait(duration: acc)
                let up   = tween(duration: segDur, from: .clear, to: color)
                seg.runAction(.sequence([wait, up]))
                acc += segDur
            }
        }
        private func disappearSegmentsPiecewise(
            _ segments: [SCNNode],
            lengths: [Float],
            totalDuration: TimeInterval,
            fromColor: UIColor,
            disappearPortion: Double = 0.25
        ) {
            guard !segments.isEmpty, !lengths.isEmpty else { return }
            
            let totalLen = max(1e-6, lengths.reduce(0, +))
            let disappearDur = max(1e-6, totalDuration * disappearPortion)
            
            func lerpColor(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
                var ar: CGFloat=0, ag: CGFloat=0, ab: CGFloat=0, aa: CGFloat=0
                var br: CGFloat=0, bg: CGFloat=0, bb: CGFloat=0, ba: CGFloat=0
                a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
                b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                return UIColor(red: ar+(br-ar)*t, green: ag+(bg-ag)*t, blue: ab+(bb-ab)*t, alpha: aa+(ba-aa)*t)
            }
            func tween(duration: TimeInterval, from: UIColor, to: UIColor) -> SCNAction {
                SCNAction.customAction(duration: duration) { node, elapsed in
                    guard let m = node.geometry?.firstMaterial else { return }
                    let tt = CGFloat(duration == 0 ? 1 : max(0, min(1, elapsed / CGFloat(duration))))
                    let c  = lerpColor(from, to, t: tt)
                    m.diffuse.contents  = c
                    m.emission.contents = c
                }
            }
            
            var acc: TimeInterval = 0
            for (i, seg) in segments.enumerated() {
                let ratio = TimeInterval(lengths[i] / totalLen)
                let segDur = disappearDur * ratio
                let wait = SCNAction.wait(duration: acc)
                let down = tween(duration: segDur, from: fromColor, to: .clear)
                seg.runAction(.sequence([wait, down]))
                acc += segDur
            }
        }
        private func scheduleChainedEdgeAnimations() {
            
            let accent: UIColor = {
                if parent.selectedAccent == .default {
                    switch parent.selectedAppearance {
                    case .system:
                        return parent.colorScheme == .dark
                            ? .white   // system dark → white
                            : .black   // system light → black

                    case .light:        // aka `.white`
                        return .black

                    case .dark:         // aka `.black`
                        return .white
                    }
                } else {
                    return UIColor(parent.selectedAccent.color)
                }
            }()


            // ---- A) CHAINED edges (sequential, your current logic) ----
            for (parentId, indices) in chainConnIndicesByParent {
                guard let groupNode = connectionGroupsByParent[parentId], !indices.isEmpty else { continue }

                groupNode.removeAllActions()

                var seq: [SCNAction] = []

                // APPEAR sequential
                for idx in indices {
                    guard idx >= 0 && idx < connections.count else { continue }
                    let conn = connections[idx]
                    let dur: TimeInterval = parent.rateForConnections[conn.from]?[conn.to]
                        ?? parent.rateForConnections[conn.to]?[conn.from]
                        ?? 8.0

                    let appearRun = SCNAction.run { [weak self] _ in
                        self?.appearSegmentsOnly(conn.segments,
                                                 lengths: conn.lengths,
                                                 totalDuration: dur,
                                                 color: accent,
                                                 appearPortion: 0.75)
                    }
                    seq.append(appearRun)
                    seq.append(.wait(duration: dur * 0.75 + 0.08))
                }

                // DISAPPEAR sequential
                for idx in indices {
                    guard idx >= 0 && idx < connections.count else { continue }
                    let conn = connections[idx]
                    let dur: TimeInterval = parent.rateForConnections[conn.from]?[conn.to]
                        ?? parent.rateForConnections[conn.to]?[conn.from]
                        ?? 8.0

                    let disappearRun = SCNAction.run { [weak self] _ in
                        self?.disappearSegmentsPiecewise(conn.segments,
                                                        lengths: conn.lengths,
                                                        totalDuration: dur,
                                                        fromColor: accent,
                                                        disappearPortion: 0.25)
                    }
                    seq.append(disappearRun)
                    seq.append(.wait(duration: dur * 0.25 + 0.08))
                }

                groupNode.runAction(.repeatForever(.sequence(seq)))
            }

            // ---- B) DIRECT/STAR edges (simultaneous) ----
            for (parentId, indices) in directConnIndicesByParent {
                guard let groupNode = connectionGroupsByParent[parentId], !indices.isEmpty else { continue }

                // Run in parallel with any existing chain animation on the same group node:
                // use a different action key so both can coexist.
                groupNode.removeAction(forKey: "directStarAnim")

                // Choose a cycle duration: use the MAX dur among these edges, so all finish together.
                var maxDur: TimeInterval = 0
                var conns: [Connection] = []
                conns.reserveCapacity(indices.count)

                for idx in indices {
                    guard idx >= 0 && idx < connections.count else { continue }
                    let conn = connections[idx]
                    conns.append(conn)

                    let dur: TimeInterval = parent.rateForConnections[conn.from]?[conn.to]
                        ?? parent.rateForConnections[conn.to]?[conn.from]
                        ?? 8.0
                    maxDur = max(maxDur, dur)
                }

                guard maxDur > 0, !conns.isEmpty else { continue }

                let appearAll = SCNAction.run { [weak self] _ in
                    guard let self else { return }
                    for conn in conns {
                        let dur: TimeInterval = self.parent.rateForConnections[conn.from]?[conn.to]
                            ?? self.parent.rateForConnections[conn.to]?[conn.from]
                            ?? 8.0

                        self.appearSegmentsOnly(conn.segments,
                                                lengths: conn.lengths,
                                                totalDuration: dur,
                                                color: accent,
                                                appearPortion: 0.75)
                    }
                }

                let disappearAll = SCNAction.run { [weak self] _ in
                    guard let self else { return }
                    for conn in conns {
                        let dur: TimeInterval = self.parent.rateForConnections[conn.from]?[conn.to]
                            ?? self.parent.rateForConnections[conn.to]?[conn.from]
                            ?? 8.0

                        self.disappearSegmentsPiecewise(conn.segments,
                                                        lengths: conn.lengths,
                                                        totalDuration: dur,
                                                        fromColor: accent,
                                                        disappearPortion: 0.25)
                    }
                }

                // One full cycle: appear phase then disappear phase, but both phases run "all at once"
                let seq = SCNAction.sequence([
                    appearAll,
                    .wait(duration: maxDur * 0.75 + 0.08),
                    disappearAll,
                    .wait(duration: maxDur * 0.25 + 0.08)
                ])

                groupNode.runAction(.repeatForever(seq), forKey: "directStarAnim")
            }
        }

        private func setWireFogged(layer i: Int, fogged: Bool, animated: Bool = true) {
            guard i >= 0, i < wireNodes.count,
                  let m = wireNodes[i].geometry?.firstMaterial else { return }

            let target = fogged ? fogWireAlpha : wireBaseOpacity[i]
            let apply: (CGFloat) -> Void = { a in m.transparency = a }

            if !animated {
                apply(target); return
            }

            let from = CGFloat(m.transparency)
            let dur = fogAnim
            let action = SCNAction.customAction(duration: dur) { _, t in
                let u = dur == 0 ? 1 : CGFloat(t) / CGFloat(dur)
                apply(from + (target - from) * u)
            }
            wireNodes[i].removeAction(forKey: "fogFade")
            wireNodes[i].runAction(action, forKey: "fogFade")
        }
        private func updateFogForShellCrossings(currentCameraRadius r: CGFloat) {
            guard !radiusValues.isEmpty else { return }
            let focusedLayer: Int? = {
                guard let a = focusAnchor, let name = a.parent?.name else { return nil }
                return groupNodes.firstIndex { $0.name == name }
            }()

            for (i, R) in radiusValues.enumerated() {
                if focusedLayer == i {                   // <- don’t fog the selected layer
                    if foggedLayers.contains(i) {
                        foggedLayers.remove(i)
                        setLayerFogState(i, fogged: false, animated: true)
                    }
                    continue
                }
                let isInside  = r < (R - fogHysteresis)
                let isOutside = r > (R + fogHysteresis)

                if isInside, !foggedLayers.contains(i) {
                    foggedLayers.insert(i)
                    setLayerFogState(i, fogged: true, animated: true)
                } else if isOutside, foggedLayers.contains(i) {
                    foggedLayers.remove(i)
                    setLayerFogState(i, fogged: false, animated: true)
                }
            }
        }
        private func makeLoadMoreButton(radius: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: 0.4, height: 0.1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.systemBlue
            m.emission.contents = UIColor.white
            m.isDoubleSided = true
            plane.firstMaterial = m

            let n = SCNNode(geometry: plane)
            n.name = "loadMore"
            n.constraints = [SCNBillboardConstraint()]
            n.position = SCNVector3(0, 0, Float(radius) * 1.1) // slightly outside current layer
            n.renderingOrder = 3000
            n.categoryBitMask = 1 << 0
            return n
        }
        private var directConnIndicesByParent: [Int: [Int]] = [:]

        func buildScene() -> SCNScene {
            resolveColors() // ⬅️ do this once at the top
            labelNodes.removeAll()
            originalColors.removeAll()
            anchorByNumber.removeAll()
            labelByNumber.removeAll()
            radiusByGroupName.removeAll()
            groupNodes.removeAll()
            connections.removeAll()
            connectionsByNode.removeAll()
            connectionGroupsByParent.removeAll()
            // NEW:
            chainConnIndicesByParent.removeAll()
            chainParentByNode.removeAll()
            
            directConnIndicesByParent.removeAll()

            func colorForLayer(_ i: Int) -> UIColor {
                let c: UIColor
                if i <= 1 { c = parent.coreColor }
                else if i <= 6 { c = parent.innerColor }
                else { c = parent.outerColor }
                
                return dynamicNodeColor(c)
            }
            
            // MARK: - 99999 tagging
            let tagMod = 100_000
            let tagRemainder = 99_999

            func isTagged99999(_ id: Int) -> Bool {
                id % tagMod == tagRemainder
            }

            /// 12399999 -> 123 (because 123*100000 + 99999)
            /// If not tagged, returns id unchanged.
            func normalize99999(_ id: Int) -> Int {
                isTagged99999(id) ? (id / tagMod) : id
            }

            
            func labelScaleForRadius(_ R: CGFloat) -> SCNVector3 {
                
                let s = max(0.006, min(0.200, R * 0.024))
                return SCNVector3(Float(s) * nodeScale, Float(s) * nodeScale, Float(s) * nodeScale)
            }
            
            func pointOnShell(_ R: CGFloat) -> SCNVector3 {
                let (ux,uy,uz) = randomPointOnUnitSphere()
                return SCNVector3(Float(R)*ux, Float(R)*uy, Float(R)*uz)
            }
            func opacityForLayer(_ i: Int, L: Int) -> CGFloat {
                
                let maxOpacity: CGFloat = 0.35
                let minOpacity: CGFloat = 0.20
                let step = (maxOpacity - minOpacity) / CGFloat(max(1, L - 1))
                return minOpacity + step * CGFloat(L - 1 - i)
            }
            func ensureParentGroupNode(_ parentId: Int, in scene: SCNScene) -> SCNNode {
                if let g = connectionGroupsByParent[parentId] { return g }
                let g = SCNNode()
                g.name = "conn_parent_\(parentId)"
                g.isHidden = false
                g.opacity  = 1.0
                scene.rootNode.addChildNode(g)
                connectionGroupsByParent[parentId] = g
                return g
            }
            func orderedChildrenSplit(by map: [Int: [Int: Int]]) -> [Int: (chain: [Int], direct: [Int])] {
                var result: [Int: (chain: [Int], direct: [Int])] = [:]

                for (rawParent, orderMap) in map {
                    let parentTagged = isTagged99999(rawParent)
                    let parent = normalize99999(rawParent)

                    // keep your existing ordering behavior
                    let rawChildren = orderMap
                        .sorted { a, b in a.key != b.key ? a.key < b.key : a.value < b.value }
                        .map { $0.value }

                    // Start from any existing entry for this normalized parent
                    var chain = result[parent]?.chain ?? []
                    var direct = result[parent]?.direct ?? []

                    // Track what we've already added for this parent (after normalization)
                    var seen = Set(chain + direct)

                    for child in rawChildren {
                        let normChild = normalize99999(child)
                        guard !seen.contains(normChild) else { continue }
                        seen.insert(normChild)

                        // RULE:
                        // - If the *parent* is tagged, ALL children become direct edges (star)
                        // - Else, only tagged children become direct; normal children go into chain
                        if parentTagged || isTagged99999(child) {
                            direct.append(normChild)
                        } else {
                            chain.append(normChild)
                        }
                    }

                    result[parent] = (chain: chain, direct: direct)
                }

                return result
            }


            
            let radiiPalette: [CGFloat] = [
                0.10, 1.00, 2.50, 5.00, 7.50,
                10.00, 12.50, 15.00, 17.50, 20.00, 22.50, 25.00
            ]
            
            let allModelIndices = Array(parent.GlobalModelsData.keys)
            
            guard !allModelIndices.isEmpty else { return SCNScene() }
            
            
            let activeShells: [Int] = shellRanges
                .sorted { $0.key < $1.key }
                .compactMap { (shellId, range) in
                    allModelIndices.contains(where: range.contains) ? shellId : nil
                }
            guard !activeShells.isEmpty else { return SCNScene() }
            
            
            let shellToLocal: [Int: Int] = Dictionary(
                uniqueKeysWithValues: activeShells.enumerated().map { (local, shellId) in (shellId, local) }
            )
            
            
            let chosenRadii: [CGFloat] = activeShells.map { shellId in
                radiiPalette[min(max(shellId - 1, 0), radiiPalette.count - 1)]
            }
            
            let scene = SCNScene()

            // Content container: EVERYTHING (except camera rig) goes here
            let content = SCNNode()
            content.name = "contentRoot"
            scene.rootNode.addChildNode(content)
            self.contentRoot = content

            let L = chosenRadii.count

            loadedLayerCount = L
            
            
            radiusValues = chosenRadii
            labelNodesByLayer = Array(repeating: [], count: L)
            namesByLayer      = Array(repeating: [], count: L)
            idsByLayer        = Array(repeating: [], count: L)
            
            
            coreRadiusValue  = radiusValues.first ?? 0.10
            innerRadiusValue = radiusValues[min(2, max(0, L - 1))]
            outerRadiusValue = radiusValues.last ?? coreRadiusValue
            
            let trait = view?.traitCollection ?? UIScreen.main.traitCollection
            let baseWire = sphereWireColorResolved(trait)
            
            
            for i in 0..<loadedLayerCount {
                let mer = max(3, 20 - i)
                let par = max(0, 10 - i / 2)
                
                let wire = makeWireSphere(
                    radius: radiusValues[i],
                    meridians: mer,
                    parallels: par,
                    color: baseWire,
                    opacity: 0.0
                )
                wire.name = "wire_\(i)"
                wire.categoryBitMask = 1 << 1
                wire.geometry?.firstMaterial?.readsFromDepthBuffer = false
                scene.rootNode.addChildNode(wire)

                wireNodes.append(wire)
                wireBaseOpacity.append(wire.geometry?.firstMaterial?.transparency ?? 1.0)

                // NEW: fog sphere starts invisible (alpha 0), we’ll fade it when fogging
                let fog = makeFogSphere(radius: radiusValues[i], baseAlpha: 0.0)
                scene.rootNode.addChildNode(fog)
                fogSphereNodes.append(fog)
                fogSphereBaseAlpha.append(0.0)
                deferredLayers.append((layerIndex: i, radius: radiusValues[i]))

            }
            
            
            
            for i in 0..<loadedLayerCount {
                let g = SCNNode()
                g.name = "layer\(i)"
                scene.rootNode.addChildNode(g)
                groupNodes.append(g)
                radiusByGroupName[g.name!] = radiusValues[i]

                groupBaseOpacity.append(CGFloat(g.opacity))
                deferredLayers.append((layerIndex: i, radius: radiusValues[i]))
            }


            if loadedLayerCount < L {
                let nextR = radiusValues[loadedLayerCount]
                let btn = makeLoadMoreButton(radius: nextR * 0.9)
                scene.rootNode.addChildNode(btn)
            }

            let deviceScale: CGFloat = UIScreen.main.scale
            let atlasSize = 4096                      // or 2048 on older devices if you want
            let atlas = LabelAtlas(size: atlasSize, scale: deviceScale)
            self.atlas = atlas
            atlasEntryByID.removeAll()

            let font = UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(.medium)

            let uiColor = colors.label

            for idx in allModelIndices.sorted() {
                guard let raw = parent.GlobalModelsData[idx]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { continue }

                let img = LabelRasterizer.makeImage(
                    text: raw, font: font, color: uiColor,
                    padding: 4, maxWidth: 140, scale: 1.0
                )
                if let entry = atlas.add(image: img) {
                    atlasEntryByID[idx] = entry
                }
            }
            // Freeze CPU → UIImage for SceneKit
            atlas.snapshotAtlases()
            
            atlasMaterials.removeAll()
            if let atlas = self.atlas {
                for (i, image) in atlas.atlasImages.enumerated() {
                    // one material per atlas to keep GPU bindings minimal
                    let m = SCNMaterial()
                    m.lightingModel = .constant
                    m.diffuse.contents = image
                    m.diffuse.wrapS = .clamp
                    m.diffuse.wrapT = .clamp
                    m.diffuse.mipFilter = .none            // <- no mipmaps
                    m.diffuse.minificationFilter = .nearest
                    m.diffuse.magnificationFilter = .linear
                    m.emission.contents = UIColor.clear
                    m.isDoubleSided = true
                    m.readsFromDepthBuffer = true
                    m.writesToDepthBuffer = false
                    m.blendMode = .alpha
                    atlasMaterials[i] = m
                }
            }

            
            
            for idx in allModelIndices.sorted() {
                guard let raw = parent.GlobalModelsData[idx]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { continue }

                guard let shellId = shellRanges.first(where: { $0.value.contains(idx) })?.key,
                      let localLayer = shellToLocal[shellId] else { continue }

                // 👇 Skip labels for layers not yet built
                guard localLayer < groupNodes.count else { continue }

                let layerR = radiusValues[localLayer]
                let anchor = SCNNode()
                anchor.position = (localLayer == 0)
                    ? randomPointInsideSphere(radius: Float(radiusValues[0]))
                    : pointOnShell(layerR)
                
                let label = makeLabelPlane(
                    for: raw,
                    color: colors.label,     // ⬅️ cached
                    atRadius: layerR,
                    id: idx
                )

                label.name = "labelWrapper"

                // Scale to target height
                if let plane = label.childNode(withName: "labelPlane", recursively: false)?.geometry as? SCNPlane {
                    let targetH = targetHeightForLayer(localLayer: localLayer, totalLayers: L)
                    let currentH = CGFloat(plane.height)
                    let s = max(0.0001, targetH / max(currentH, 1e-6))
                    label.scale = SCNVector3(Float(s), Float(s), Float(s))
                }

                // Normal insertion
                labelByNumber[idx] = label
                nodeIDs[ObjectIdentifier(label)] = idx
                anchor.addChildNode(label)
                groupNodes[localLayer].addChildNode(anchor)
                remember(label)
                anchorByNumber[idx] = anchor
                
                labelNodesByLayer[localLayer].append(label)
                namesByLayer[localLayer].append(raw)
                idsByLayer[localLayer].append(idx)
            }

            
            
            connections.removeAll()
            connectionsByNode.removeAll()
            connectionGroupsByParent.removeAll()
            
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0

            for (_, anchor) in anchorByNumber {
                anchor.opacity = anchor.opacity
            }

            SCNTransaction.commit()
            
            let split = orderedChildrenSplit(by: parent.orderForConnections)


            
            
            let rig = SCNNode()
            let yawNode = SCNNode()
            let pitchNode = SCNNode()
            scene.rootNode.addChildNode(rig)
            rig.addChildNode(yawNode)
            yawNode.addChildNode(pitchNode)
            
            let cam = SCNNode()
            let scnCam = SCNCamera()
            scnCam.automaticallyAdjustsZRange = true
            scnCam.zNear = 0.001
            scnCam.zFar  = 5000
            
            scnCam.wantsHDR = false
            scnCam.wantsExposureAdaptation = false
            scnCam.bloomIntensity = 0
            scnCam.bloomThreshold = 1
            scnCam.bloomBlurRadius = 0
            scnCam.motionBlurIntensity = 0
            scnCam.vignettingPower = 0
            scnCam.colorFringeStrength = 0
            
            cam.camera = scnCam
            pitchNode.addChildNode(cam)
            
            
            cameraNode = cam
            view?.pointOfView = cam
            self.rig = rig
            self.yawNode = yawNode
            self.pitchNode = pitchNode
            
            camRadius = maxRadius
            yaw = 0
            pitch = 0
            updateCameraOrbit()
            view?.delegate = self
            
            updateLayerVisibility()
            sceneRoot = scene.rootNode
            
            if worldCenterTarget.parent == nil {
                worldCenterTarget.name = "worldCenterTarget"
                worldCenterTarget.position = SCNVector3Zero
                sceneRoot?.addChildNode(worldCenterTarget)
            }

            
            if let cb = parent.onLayersBuilt {
                let allLayers = namesByLayer
                DispatchQueue.main.async { cb(allLayers) }
            }
            scheduleChainedEdgeAnimations()
            return scene
        }
        @discardableResult
        private func ensureEdgesForNode(_ id: Int) -> [Int] {
            // 1) Collect neighbors from your existing rates map.
            let neighborRates = parent.rateForConnections[id] ?? [:]
            let neighbors = Array(neighborRates.keys).filter { anchorByNumber[$0] != nil }
            guard !neighbors.isEmpty, anchorByNumber[id] != nil else {
                return connectionsByNode[id] ?? []
            }

            // 2) Start from already known edges (if any).
            var touched = Set(connectionsByNode[id] ?? [])

            // 3) Create any missing edges (id <-> nb).
            for nb in neighbors {
                // Skip if an edge already exists.
                if let idxs = connectionsByNode[id],
                   idxs.contains(where: { i in
                       let e = connections[i]; return (e.from == id && e.to == nb) || (e.from == nb && e.to == id)
                   }) {
                    continue
                }

                guard let a = anchorByNumber[id], let b = anchorByNumber[nb] else { continue }

                // Build the polyline and segmented line using your existing helpers.
                let pts = currentEdgePolyline(from: a, to: b)
                let built = buildSegmentedLine(from: pts, opacity: 0.5)   // starts clear; you animate later
                built.node.name = "edge_\(id)_\(nb)"
                (sceneRoot ?? view?.scene?.rootNode)?.addChildNode(built.node)

                let conn = Connection(from: id, to: nb, container: built.node,
                                      segments: built.segments, lengths: built.segmentLengths)
                connections.append(conn)
                let newIndex = connections.count - 1

                // Index by node
                connectionsByNode[id, default: []].append(newIndex)
                connectionsByNode[nb, default: []].append(newIndex)
                touched.insert(newIndex)
            }

            return Array(touched)
        }

        private func filterConnectionsForGroup() {
            // --- CASE 1: Group is active -> show edges touching ANY id in the group
            if !currentSelectedGroup.isEmpty {
                let groupSet = Set(currentSelectedGroup)

                // Determine which connections to keep (touch group)
                var related = groupSet                     // start with the group itself
                for (i, c) in connections.enumerated() {
                    let e = connections[i]
                    let show = groupSet.contains(e.from) || groupSet.contains(e.to)
                    c.container.isHidden = !show
                    c.container.opacity  = show ? 1.0 : 0
                    if show {
                        related.insert(e.from)
                        related.insert(e.to)
                    }
                }
                
                // Labels: brighten group + endpoints of kept edges; dim everything else
                for (id, wrapper) in labelByNumber {
                    let a: CGFloat = related.contains(id) ? 1.0 : 0.2
                    setWrapperAlphaAndScale(wrapper, to: a)   // animates when needed
                }

                return
            }
        }
        
        private func filterConnections(for selectedId: Int?) {
            // Helper to fade wrapper opacity smoothly
            func setOpacity(_ n: SCNNode, to alpha: CGFloat) {
                n.removeAction(forKey: "fadeOpacity")
                n.runAction(.fadeOpacity(to: alpha, duration: 0.20), forKey: "fadeOpacity")
            }



            guard let id = selectedId else {
                for c in connections { c.container.isHidden = false; c.container.opacity = 1 }
                for (_, wrapper) in labelByNumber { setWrapperAlphaAndScale(wrapper, to: 1.0) }
                return
            }
            
            // Make sure edges exist for the selected node (if you didn’t prebuild all)
            let touched = ensureEdgesForNode(id)
            
            if let chainParent = chainParentByNode[id],
               let chainIdxs = chainConnIndicesByParent[chainParent],
               !chainIdxs.isEmpty
            {
                let keepSet = Set(chainIdxs)
                
                // Edges visibility
                for (i, c) in connections.enumerated() {
                    let show = keepSet.contains(i)
                    c.container.isHidden = !show
                    c.container.opacity  = show ? 1 : 0
                }
                
                // Related labels = endpoints of kept edges
                var related = Set<Int>([id])
                for i in keepSet { let e = connections[i]; related.insert(e.from); related.insert(e.to) }

                for (nid, wrapper) in labelByNumber {
                    let a: CGFloat = related.contains(nid) ? 1.0 : 0.2
                    setWrapperAlphaAndScale(wrapper, to: a)
                }
                 
                return
            }
            
            // …fallback: only edges incident to this node (using touched set if needed)
            let keep = (connectionsByNode[id] ?? touched)
            
            // Start with the selected id; we'll add endpoints below (if any)
            var related = Set<Int>([id])
            
            if keep.isEmpty {
                // No edges at all → show everything but still highlight the selected
                for c in connections { c.container.isHidden = false; c.container.opacity = 1 }
                for (nid, wrapper) in labelByNumber {
                    let a: CGFloat = related.contains(nid) ? 1.0 : 0.2
                    setWrapperAlphaAndScale(wrapper, to: a)
                }
                return
            }
            
            let keepSet = Set(keep)
            for (i, c) in connections.enumerated() {
                let show = keepSet.contains(i)
                c.container.isHidden = !show
                c.container.opacity  = show ? 1 : 0
            }
            
            // Dim unrelated: related = endpoints of kept edges (+ the selected)
            for i in keepSet {
                let e = connections[i]
                related.insert(e.from)
                related.insert(e.to)
            }
            
            for (nid, wrapper) in labelByNumber {
                let a: CGFloat = related.contains(nid) ? 1.0 : 0.2
                setWrapperAlphaAndScale(wrapper, to: a)
                setLabelHighlighted(wrapper, true)
            

            }
        }

        private func setLayerFogState(_ i: Int, fogged: Bool, animated: Bool = true) {
            
            guard i >= 0,
                  i < wireNodes.count,
                  i < fogSphereNodes.count,
                  i < groupNodes.count else { return }

            // Targets
            let wireTarget = 0.0
            let fogFillTarget = fogged ? fogFillAlpha : 0.0
            let groupTarget = fogged ? fogGroupAlpha : (groupBaseOpacity[i] > 0 ? groupBaseOpacity[i] : 1.0)

            // Apply helper
            func tween(_ node: SCNNode, key: String, getter: @escaping ()->CGFloat,
                       setter: @escaping (CGFloat)->Void, to target: CGFloat) {
                if !animated {
                    setter(target); return
                }
                let from = getter()
                let dur = fogAnim
                let act = SCNAction.customAction(duration: dur) { _, t in
                    let u = dur == 0 ? 1 : CGFloat(t)/CGFloat(dur)
                    setter(from + (target - from) * u)
                }
                node.removeAction(forKey: key)
                node.runAction(act, forKey: key)
            }

            // Wires: material transparency
            if let m = wireNodes[i].geometry?.firstMaterial {
                tween(wireNodes[i], key: "fogWire",
                      getter: { CGFloat(m.transparency) },
                      setter: { m.transparency = $0 },
                      to: wireTarget)
            }

            // Fog sphere: material transparency
            if let m = fogSphereNodes[i].geometry?.firstMaterial {
                tween(fogSphereNodes[i], key: "fogFill",
                      getter: { CGFloat(m.transparency) },
                      setter: { m.transparency = $0 },
                      to: fogFillTarget)
            }

            // Nodes on that layer: dim the whole group
            tween(groupNodes[i], key: "fogGroup",
                  getter: { CGFloat(self.groupNodes[i].opacity) },
                  setter: { self.groupNodes[i].opacity = CGFloat(Float($0)) },
                  to: groupTarget)
            
            // labels/anchors on this layer: dim + scale
            let alpha: CGFloat = fogged ? fogGroupAlpha : 1.0
            if i >= 0, i < labelNodesByLayer.count {
                for wrapper in labelNodesByLayer[i] {
                    setWrapperAlphaAndScale(wrapper, to: alpha, duration: animated ? fogAnim : 0)
                }
            }
        }
        private var isUserInteracting: Bool = false

        
        private func buildSegmentedLine(
            from pts: [SIMD3<Float>],
            opacity: CGFloat,
            materialTemplate: SCNMaterial? = nil,
            respectsDepth: Bool = true
        ) -> LineBuild {
            let container = SCNNode()
            var segNodes: [SCNNode] = []
            var segLens: [Float] = []
            guard pts.count >= 2 else { return .init(node: container, segments: [], segmentLengths: []) }

            // choose (or build) the template once
            let trait = view?.traitCollection ?? UIScreen.main.traitCollection
            let baseTemplate = materialTemplate ?? ConnectionMaterialTemplate.make(
                opacity: opacity,
                respectsDepth: respectsDepth
            )

            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i+1]

                var positions: [Float] = [a.x, a.y, a.z, b.x, b.y, b.z]
                var indices:   [UInt32] = [0, 1]

                let vData = Data(buffer: positions.withUnsafeBufferPointer { $0 })
                let iData = Data(buffer: indices.withUnsafeBufferPointer   { $0 })

                let src = SCNGeometrySource(
                    data: vData, semantic: .vertex, vectorCount: 2,
                    usesFloatComponents: true, componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                    dataStride: MemoryLayout<Float>.size * 3
                )
                let elem = SCNGeometryElement(
                    data: iData, primitiveType: .line,
                    primitiveCount: 1,
                    bytesPerIndex: MemoryLayout<UInt32>.size
                )

                let geo = SCNGeometry(sources: [src], elements: [elem])
                // Clone so each segment animates independently
                geo.firstMaterial = ConnectionMaterialTemplate.clone(from: baseTemplate)

                let segNode = SCNNode(geometry: geo)
                segNode.renderingOrder = 2300
                container.addChildNode(segNode)

                let d = simd_length(b - a)
                segLens.append(d)
                segNodes.append(segNode)
            }

            return .init(node: container, segments: segNodes, segmentLengths: segLens)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {

            // ✅ Never mix pinch with any pan (this is the snap culprit)
            if (g is UIPinchGestureRecognizer) || (other is UIPinchGestureRecognizer) {
                return false
            }

            // Optional: don’t let the 1-finger pan and 2-finger pan fight each other
            if (g is UIPanGestureRecognizer) && (other is UIPanGestureRecognizer) {
                return false
            }

            return true
        }

        private func ensureUnpaused() {
            view?.scene?.isPaused = false
            view?.isPlaying = true
        }
        @objc func observePan(_ g: UIPanGestureRecognizer) {
            ensureUnpaused()
            if g.state == .began { markActivityAndResetTimer(); recordActivityThrottled() }
            guard let v = view else { return }
            let p = g.location(in: v)

            switch g.state {
            case .began:
                isUserInteracting = true
                lastPanPoint = p
                
                yawVel *= 0.5; pitchVel *= 0.5

            case .changed:
                guard let last = lastPanPoint else { return }
                var dx = Float(p.x - last.x)
                var dy = Float(p.y - last.y)

                let damp: Float = (focusAnchor == nil) ? 1.0 : 0.75
                dx *= damp; dy *= damp

                
                let zoomScale = zoomScaleForControls()
                dx *= zoomScale
                dy *= zoomScale


                
                yaw   += dx * yawSensitivity
                pitch -= dy * pitchSensitivity
                yaw = wrap(yaw); pitch = wrap(pitch, period: 2 * .pi)
                updateCameraOrbit()

                
                let vel = g.velocity(in: v)
                let speed = hypot(vel.x, vel.y)

                
                let gain: Float
                if speed <= inertiaThreshold {
                    gain = 0
                } else {
                    let t = min(1.0,
                                (speed - inertiaThreshold) / max(1, (inertiaMax - inertiaThreshold)))
                    gain = Float(t)
                }

                if gain > 0 {
                    let vx = Float(vel.x) * yawSensitivity   * boostFactor * gain * zoomScale
                    let vy = Float(vel.y) * pitchSensitivity * boostFactor * gain * zoomScale
                    yawVel   = max(-maxSpeed, min(maxSpeed,   yawVel   + vx))
                    pitchVel = max(-maxSpeed, min(maxSpeed,   pitchVel - vy))
                }


                lastPanPoint = p

            case .ended, .cancelled, .failed:
                lastPanPoint = nil
                isUserInteracting = false
                
                let vel = g.velocity(in: v)
                let speed = hypot(vel.x, vel.y)
                if speed < inertiaThreshold {
                    yawVel = 0
                    pitchVel = 0
                }

            default:
                break
            }
        }
        private func makeCloseNode(side: CGFloat) -> SCNNode {
            let icon = makeSymbolPlane(side: side, symbolName: "xmark.circle.fill")

            
            let hit = SCNPlane(width: side * 1.8, height: side * 1.8)
            let mh = SCNMaterial()
            mh.diffuse.contents = UIColor.clear
            mh.isDoubleSided = true
            mh.readsFromDepthBuffer = false
            mh.writesToDepthBuffer = false
            hit.firstMaterial = mh
            let hitNode = SCNNode(geometry: hit)
            hitNode.name = "hit"
            hitNode.categoryBitMask = 1 << 0
            hitNode.renderingOrder = 2400

            let wrapper = SCNNode()
            wrapper.name = "close"
            wrapper.addChildNode(icon)
            wrapper.addChildNode(hitNode)
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.categoryBitMask = 1 << 0
            return wrapper
        }
        private func makePlayNode(side: CGFloat) -> SCNNode {
            let icon = makeSymbolPlane(side: side, symbolName: "play.circle.fill")

            let hit = SCNPlane(width: side * 1.8, height: side * 1.8)
            let mh = SCNMaterial()
            mh.diffuse.contents = UIColor.clear
            mh.isDoubleSided = true
            mh.readsFromDepthBuffer = false
            mh.writesToDepthBuffer = false
            hit.firstMaterial = mh
            let hitNode = SCNNode(geometry: hit)
            hitNode.name = "hit"
            hitNode.categoryBitMask = 1 << 0
            hitNode.renderingOrder = 2400

            let wrapper = SCNNode()
            wrapper.name = "play"
            wrapper.addChildNode(icon)
            wrapper.addChildNode(hitNode)
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.categoryBitMask = 1 << 0
            return wrapper
        }
        @objc func observePinch(_ g: UIPinchGestureRecognizer) {
            ensureUnpaused()
            if g.state == .began { markActivityAndResetTimer(); recordActivityThrottled() }
            if g.state == .changed {
                let rMin = minZoom(for: focusAnchor)
                let t = (camRadius - rMin) / (maxRadius - rMin)
                let exp: Float = 1.35 - 0.50 * t
                let factor = pow(1.0 / Float(g.scale), exp)
                camRadius *= factor
                g.scale = 1.0
                updateCameraOrbit()
            }
        }
        private func buttonTapFlash(_ button: SCNNode) {
            
            setButtonHighlighted(button, true)
            let unflash = SCNAction.run { _ in self.setButtonHighlighted(button, false) }
            
            let sUp   = SCNAction.scale(by: 1.12, duration: 0.08)
            let sDown = SCNAction.scale(to: 1.0,   duration: 0.10)
            button.runAction(.sequence([sUp, sDown, unflash]))
        }
        private func updateLayerVisibility() {

        }
        private func makeWireSphere(radius: CGFloat,
                                    meridians: Int,
                                    parallels: Int,
                                    color: UIColor,
                                    opacity: CGFloat) -> SCNNode {

            let r = Float(radius)
            let M = max(3, meridians)
            let P = max(0, parallels)

            
            let segsMeridian = max(24, M * 2)
            let segsParallel = max(18, M)

            var positions = [Float]()
            var indices   = [UInt32]()

            func appendPolyline(_ pts: [SIMD3<Float>]) {
                guard pts.count >= 2 else { return }
                let base = UInt32(positions.count / 3)
                for p in pts { positions += [p.x, p.y, p.z] }
                for i in 0..<(pts.count - 1) {
                    indices.append(base + UInt32(i))
                    indices.append(base + UInt32(i + 1))
                }
            }

            
            let capEpsilon: Float = 0.08
            let thetaSpan = Float.pi - 2 * capEpsilon

            for i in 0..<M {
                let lambda = 2.0 * Float.pi * Float(i) / Float(M)
                var curve: [SIMD3<Float>] = []
                for k in 0...segsMeridian {
                    let t = Float(k) / Float(segsMeridian)
                    let theta = capEpsilon + thetaSpan * t
                    let x = r * sin(theta) * cos(lambda)
                    let y = r * cos(theta)
                    let z = r * sin(theta) * sin(lambda)
                    curve.append(SIMD3<Float>(x, y, z))
                }
                appendPolyline(curve)
            }

            
            if P > 0 {
                let equatorSkipEps: Float = 1e-5
                for j in 1...P {
                    let phi = -Float.pi/2 + Float.pi * Float(j) / Float(P + 1)

                    
                    if abs(phi) < equatorSkipEps { continue }
                    
                    

                    let cosphi = cos(phi), sinphi = sin(phi)
                    var ring: [SIMD3<Float>] = []
                    for k in 0...segsParallel {
                        let lambda = 2.0 * Float.pi * Float(k) / Float(segsParallel)
                        let x = r * cosphi * cos(lambda)
                        let y = r * sinphi
                        let z = r * cosphi * sin(lambda)
                        ring.append(SIMD3<Float>(x, y, z))
                    }
                    appendPolyline(ring)
                }
            }


            
            let vertexData = Data(buffer: positions.withUnsafeBufferPointer { $0 })
            let indexData  = Data(buffer: indices.withUnsafeBufferPointer   { $0 })

            let source = SCNGeometrySource(
                data: vertexData, semantic: .vertex, vectorCount: positions.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3
            )
            let element = SCNGeometryElement(
                data: indexData, primitiveType: .line,
                primitiveCount: indices.count / 2,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )

            let geo = SCNGeometry(sources: [source], elements: [element])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.readsFromDepthBuffer = true
            mat.writesToDepthBuffer = false

            mat.diffuse.contents = color          // ← base wire color (systemBackground/secondaryLabel)
            mat.emission.contents = UIColor.clear // ← no accent tint
            mat.transparency = opacity
            mat.blendMode = .alpha

            geo.firstMaterial = mat
            return SCNNode(geometry: geo)

        }

        private func radiusForAnchor(_ anchor: SCNNode) -> Float {
            if let name = anchor.parent?.name, let R = radiusByGroupName[name] {
                return Float(R)
            }
            
            let p = simd_float3(anchor.position)
            let r = simd_length(p)
            let candidates = radiusValues.map { Float($0) }
            return candidates.min { abs($0 - r) < abs($1 - r) } ?? candidates[0]
        }
        private func unitDir(from p: SCNVector3) -> simd_float3 {
            var v = simd_float3(p.x, p.y, p.z)
            let L = simd_length(v)
            return L > 1e-6 ? v / L : simd_float3(0, 1, 0)
        }
        private func remember(_ labelWrapper: SCNNode) {
            labelNodes.append(labelWrapper)
            if let plane = labelWrapper.childNode(withName: "labelPlane", recursively: false)?.geometry?.firstMaterial,
               let c = plane.diffuse.contents as? UIImage {
                // We don’t need original colors anymore; keep a marker if you want
                originalColors[ObjectIdentifier(labelWrapper)] = .white // dummy or remove dictionary entirely
            }
            baseScaleByLabel[ObjectIdentifier(labelWrapper)] = labelWrapper.scale
        }
        private func setLabelHighlighted(_ wrapper: SCNNode, _ highlighted: Bool) {
            guard let mat = wrapper
                .childNode(withName: "labelPlane", recursively: false)?
                .geometry?.firstMaterial else { return }

            if highlighted {
                mat.multiply.contents = UIColor.white
                mat.transparency = 1.0
            } else {
                let style = (view?.traitCollection ?? UIScreen.main.traitCollection).userInterfaceStyle
                mat.multiply.contents = Theme.labelDimmed(
                    selectedAppearance: parent.selectedAppearance,
                    systemColorScheme: style
                )

                mat.transparency = 1.0
            }
        }
        private func randomPointInsideSphere(radius: Float) -> SCNVector3 {
            
            let (ux,uy,uz) = randomPointOnUnitSphere()
            let u = Float.random(in: 0...1)
            let r = radius * pow(u, 1.0/3.0)
            return SCNVector3(r * ux, r * uy, r * uz)
        }
        func updateSelection(_ selected: Int?) {
            selectedNodeID = selected
            applySelection(for: selected)
        }
        private func loadNextLayer() {
            guard let next = deferredLayers.first else { return }
            deferredLayers.removeFirst()
            let i = next.layerIndex
            let R = next.radius

            // Build the wire + fog sphere
            let wire = makeWireSphere(radius: R,
                                      meridians: 10,
                                      parallels: 6,
                                      color: sphereWireColorResolved(view?.traitCollection ?? .current),
                                      opacity: 0.25)
            wire.name = "wire_\(i)"
            wire.categoryBitMask = 1 << 1
            sceneRoot?.addChildNode(wire)
            wireNodes.append(wire)
            wireBaseOpacity.append(wire.geometry?.firstMaterial?.transparency ?? 1.0)

            let fog = makeFogSphere(radius: R, baseAlpha: 0.0)
            sceneRoot?.addChildNode(fog)
            fogSphereNodes.append(fog)
            fogSphereBaseAlpha.append(0.0)

            // Labels + anchors for this layer
            let g = SCNNode()
            g.name = "layer\(i)"
            sceneRoot?.addChildNode(g)
            groupNodes.append(g)

            let style = (view?.traitCollection ?? UIScreen.main.traitCollection).userInterfaceStyle
            let color = Theme.label(
                selectedAppearance: parent.selectedAppearance,
                systemColorScheme: style
            )


            for idx in idsByLayer[i] {
                guard let raw = parent.GlobalModelsData[idx] else { continue }
                let label = makeLabelPlane(for: raw, color: color, atRadius: R, id: idx)
                let anchor = SCNNode()
                anchor.position = pointOnShell(R)
                anchor.addChildNode(label)
                g.addChildNode(anchor)
            }

            loadedLayerCount += 1

            // If there are still deferred layers left, place the next “Load More”
            if let nextDeferred = deferredLayers.first {
                let btn = makeLoadMoreButton(radius: nextDeferred.radius * 0.9)
                sceneRoot?.addChildNode(btn)
            }
        }
        private func pointOnShell(_ r: CGFloat) -> SCNVector3 {
            // Use spherical coordinates with uniform distribution.
            let u = Float.random(in: 0...1)
            let v = Float.random(in: 0...1)
            let theta = 2 * Float.pi * u           // longitude
            let phi = acos(2 * v - 1)              // latitude
            let x = r * CGFloat(sin(phi) * cos(theta))
            let y = r * CGFloat(sin(phi) * sin(theta))
            let z = r * CGFloat(cos(phi))
            return SCNVector3(x, y, z)
        }
        private var didRenderOnce = false
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if lastUpdateTime == nil { lastUpdateTime = time }
            let dt = Float(time - (lastUpdateTime ?? time))
            lastUpdateTime = time
            if let coreSpinNode = coreSpinNode {
                if !isUserInteracting {
                    coreSpinAngle += coreSpinSpeed * dt
                }
                coreSpinNode.eulerAngles.y = coreSpinAngle
            }

            if let a = focusAnchor {
                let t = a.presentation.worldPosition
                orbitCenter = SCNVector3(
                    x: orbitCenter.x + (t.x - orbitCenter.x) * followLerp,
                    y: orbitCenter.y + (t.y - orbitCenter.y) * followLerp,
                    z: orbitCenter.z + (t.z - orbitCenter.z) * followLerp
                )
                rig?.position = orbitCenter
            }

            
            if let lastT = lastUpdateTime {
                let dt = Float(time - lastT)

                if dt > 0 {
                    
                    if abs(yawVel) > 1e-4 || abs(pitchVel) > 1e-4 {
                        yaw   = wrap(yaw   + yawVel   * dt)
                        pitch = wrap(pitch + pitchVel * dt, period: 2 * .pi)
                        updateCameraOrbit()
                    }

                    
                    let damp = exp(-friction * dt)
                    yawVel   *= damp
                    pitchVel *= damp

                    
                    if abs(yawVel) < 1e-3 { yawVel = 0 }
                    if abs(pitchVel) < 1e-3 { pitchVel = 0 }
                }
            }
            
            if var rc = recenter, let t0 = lastUpdateTime {
                let α = Float((time - rc.t0) / rc.dur)
                let u = ease(α)

                
                orbitCenter.x = rc.startCenter.x + (rc.endCenter.x - rc.startCenter.x) * u
                orbitCenter.y = rc.startCenter.y + (rc.endCenter.y - rc.startCenter.y) * u
                orbitCenter.z = rc.startCenter.z + (rc.endCenter.z - rc.startCenter.z) * u

                rig?.position = orbitCenter

                
                yaw   = wrap(rc.startYaw   + shortestDelta(rc.startYaw,   rc.endYaw)   * u)
                pitch = wrap(rc.startPitch + shortestDelta(rc.startPitch, rc.endPitch) * u,
                             period: 2 * .pi)

                
                camRadius = rc.startR + (rc.endR - rc.startR) * u

                updateCameraOrbit()

                if α >= 1 {
                    recenter = nil
                } else {
                    
                    recenter = rc
                }
            }

            
            lastUpdateTime = time
            if !didRenderOnce { didRenderOnce = true }
            updateLayerVisibility()
            updateTopChromeVisibility() 
        }
        private func labelNode(for node: SCNNode?) -> SCNNode? {
            var n = node
            while let cur = n {
                if cur.name == "labelWrapper" { return cur }
                n = cur.parent
            }
            return nil
        }
        private func makeLabel(for key: String, colour: UIColor) -> SCNNode {
            let textGeo = SCNText(string: key, extrusionDepth: 0)
            textGeo.font = .systemFont(ofSize: 0.25, weight: .medium)
            textGeo.flatness = 0.2
            textGeo.firstMaterial?.lightingModel = .constant   // <- add this
            textGeo.firstMaterial?.diffuse.contents = colour
            textGeo.firstMaterial?.isDoubleSided = true
            textGeo.firstMaterial?.readsFromDepthBuffer = false
            textGeo.firstMaterial?.writesToDepthBuffer = false

            let wrapper = SCNNode()
            let textNode = SCNNode(geometry: textGeo)

            
            let (minB, maxB) = textGeo.boundingBox
            let cx = (minB.x + maxB.x) * 0.5
            let cy = (minB.y + maxB.y) * 0.5
            let cz = (minB.z + maxB.z) * 0.5
            textNode.position = SCNVector3(-cx, -cy, -cz)
            textNode.renderingOrder = 2000

            
            let hitPlate = addVisibleHitPlate(in: wrapper, boundsMin: minB, boundsMax: maxB)

            
            let plate = hitPlate.geometry as? SCNPlane
            let plateW = CGFloat(plate?.width ?? 0.12)
            let plateH = CGFloat(plate?.height ?? 0.05)

            
            let minSide: CGFloat = 0.028
            let baseSide = plateH * 0.48
            let edgeInset: CGFloat = max(0.004, plateW * 0.06)
            let minGap: CGFloat = max(0.004, plateW * 0.04)

            
            let oneRowMaxSide = max(
                minSide,
                (plateW - (edgeInset * 2) - (minGap * 2)) / 3.0
            )

            
            let heightCap = plateH * 0.8

            
            var side = min(max(minSide, baseSide), oneRowMaxSide, heightCap)

            
            let close = makeCloseNode(side: side)
            let eye   = makeEyeNode(side: side)
            let play  = makePlayNode(side: side)

            
            let zPos: Float = 0.002

            
            
            
            let useCornerLayout = (side < baseSide * 0.8)

            
            let halfW = Float(plateW * 0.5)
            let halfH = Float(plateH * 0.5)

            if !useCornerLayout {
                
                
                let padX  = Float(side * 0.65)
                let plateTop = halfH
                let yTop     = plateTop + Float(side * 0.6)

                close.position = SCNVector3(-halfW + padX, yTop, zPos)
                eye.position   = SCNVector3(0,              yTop, zPos)
                play.position  = SCNVector3( halfW - padX,  yTop, zPos)
            } else {
                
                
                
                side = min(max(side, baseSide * 0.9), heightCap)
                
                close.removeFromParentNode(); eye.removeFromParentNode(); play.removeFromParentNode()
                let close2 = makeCloseNode(side: side)
                let eye2   = makeEyeNode(side: side)
                let play2  = makePlayNode(side: side)

                
                let ix = Float(edgeInset + side * 0.5)
                let iy = Float(edgeInset + side * 0.5)

                
                let topY    =  halfH + Float(side * 0.15)
                let bottomY = -halfH + Float(side * 0.20)

                close2.position = SCNVector3(-halfW + ix, topY,    zPos)
                play2.position  = SCNVector3( halfW - ix, topY,    zPos)
                eye2.position   = SCNVector3( halfW - ix, bottomY, zPos)

                
                close2.name = "close"; eye2.name = "eye"; play2.name = "play"
                close2.renderingOrder = 2600; eye2.renderingOrder = 2600; play2.renderingOrder = 2600
                close2.categoryBitMask = 1 << 0; eye2.categoryBitMask = 1 << 0; play2.categoryBitMask = 1 << 0

                wrapper.addChildNode(close2)
                wrapper.addChildNode(eye2)
                wrapper.addChildNode(play2)

                
                closeByLabel[ObjectIdentifier(wrapper)] = close2
                eyeByLabel  [ObjectIdentifier(wrapper)] = eye2
                playByLabel [ObjectIdentifier(wrapper)] = play2

                
                wrapper.addChildNode(textNode)
                wrapper.constraints = [SCNBillboardConstraint()]
                wrapper.renderingOrder = 1000
                wrapper.categoryBitMask = 1 << 0
                return wrapper
            }

            
            close.isHidden = false; eye.isHidden = false; play.isHidden = false
            close.renderingOrder = 2600; eye.renderingOrder = 2600; play.renderingOrder = 2600
            wrapper.addChildNode(close); wrapper.addChildNode(eye); wrapper.addChildNode(play)

            
            closeByLabel[ObjectIdentifier(wrapper)] = close
            eyeByLabel  [ObjectIdentifier(wrapper)] = eye
            playByLabel [ObjectIdentifier(wrapper)] = play


            wrapper.addChildNode(textNode)
            wrapper.constraints = [SCNBillboardConstraint()]
            wrapper.renderingOrder = 1000
            wrapper.categoryBitMask = 1 << 0
            
            let s = nodeScale
            wrapper.scale = SCNVector3(s, s, s)
            return wrapper
        }
        func buttonFrom(_ node: SCNNode?) -> SCNNode? {
            var n = node
            while let cur = n {
                if cur.name == "close" || cur.name == "eye" || cur.name == "play" { return cur }
                n = cur.parent
            }
            return nil
        }
        @discardableResult
        private func addVisibleHitPlate(in wrapper: SCNNode,
                                        boundsMin minB: SCNVector3,
                                        boundsMax maxB: SCNVector3,
                                        padding: CGFloat = 1.4,
                                        zOffset: Float = 0.0) -> SCNNode {
            let w = CGFloat(maxB.x - minB.x) * padding
            let h = CGFloat(maxB.y - minB.y) * (padding * 1.1)

            let plane = SCNPlane(width: max(w, 0.06), height: max(h, 0.025))
            plane.cornerRadius = min(plane.width, plane.height) * 0.08

            // Resolve appearance (respect your AppearanceOption first)
            let trait = view?.traitCollection ?? UIScreen.main.traitCollection
            let isDark: Bool = {
                if let scheme = selectedAppearance.colorScheme { return scheme == .dark }
                return trait.userInterfaceStyle == .dark
            }()

            // ✅ Black plate in light mode (white background), white plate in dark mode
            let plateColor = isDark
                ? UIColor.white
                : UIColor.black

            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = plateColor
            m.transparency = 1.0
            m.isDoubleSided = false
            m.readsFromDepthBuffer = true
            m.writesToDepthBuffer = true
            m.blendMode = .replace
            plane.firstMaterial = m

            let hitNode = SCNNode(geometry: plane)
            hitNode.position = SCNVector3(0, 0, zOffset)
            hitNode.categoryBitMask = 1 << 0
            hitNode.renderingOrder = 1000      // plate first; your text is at 2000
            wrapper.addChildNode(hitNode)
            return hitNode
        }
        private func randomPointOnUnitSphere() -> (Float,Float,Float) {
            let u = Float.random(in: 0..<1)
            let v = Float.random(in: 0..<1)
            let θ = 2 * .pi * u
            let φ = acos(2*v - 1)
            return (sin(φ)*cos(θ), sin(φ)*sin(θ), cos(φ))
        }
    }
}

final class LabelRasterizer {
    static func makeImage(text: String,
                          font: UIFont,
                          color: UIColor,
                          padding: CGFloat = 4,
                          maxWidth: CGFloat? = 140,
                          scale: CGFloat = 2.0) -> UIImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        var size = (text as NSString).size(withAttributes: attrs)
        if let maxW = maxWidth, size.width > maxW {
            let factor = maxW / max(size.width, 1)
            let newFont = UIFont(descriptor: font.fontDescriptor, size: font.pointSize * factor)
            attrs[.font] = newFont
            size = (text as NSString).size(withAttributes: attrs)
        }
        
        let canvas = CGSize(width: ceil(size.width + padding*2),
                            height: ceil(size.height + padding*2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let rect = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}

struct AtlasEntry {
    let atlasIndex: Int
    let uvRect: CGRect      // in 0..1 texture space (origin=bottom-left in CG, SceneKit expects origin=bottom-left)
    let pixelSize: CGSize   // rendered label pixels (incl. padding)
}

final class LabelAtlas {
    struct Shelf { var x: Int = 0; var y: Int = 0; var h: Int = 0 }
    private(set) var atlases: [CGContext] = []
    private(set) var atlasImages: [UIImage] = []
    private var shelves: [Shelf] = []
    
    private let atlasSizePx: Int
    private let padding: Int = 2                // avoid bleeding
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    private let scale: CGFloat                   // device scale (e.g. 2.0 or 3.0)

    init(size: Int = 4096, scale: CGFloat = 2.0) {
        self.atlasSizePx = size
        self.scale = scale
        makeNewAtlas()
    }
    
    private func makeNewAtlas() {
        guard let ctx = CGContext(
            data: nil,
            width: atlasSizePx,
            height: atlasSizePx,
            bitsPerComponent: 8,
            bytesPerRow: atlasSizePx * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }
        ctx.interpolationQuality = .none
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(UIColor.clear.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: atlasSizePx, height: atlasSizePx))
        atlases.append(ctx)
        shelves.append(Shelf(x: 0, y: 0, h: 0))
        atlasImages.append(UIImage()) // placeholder; filled when snapshot()
    }
    
    /// Render a label UIImage once (outside), then pack it here.
    /// Returns which atlas and UV rect to sample.
    func add(image: UIImage) -> AtlasEntry? {
        guard let cg = image.cgImage else { return nil }
        let iw = cg.width  + padding * 2
        let ih = cg.height + padding * 2
        guard iw <= atlasSizePx && ih <= atlasSizePx else { return nil } // too big
        
        var atlasIdx = atlases.count - 1
        var shelf = shelves[atlasIdx]
        
        // move to next row if not enough horizontal space
        if shelf.x + iw > atlasSizePx {
            shelf.x = 0
            shelf.y += shelf.h
            shelf.h = 0
        }
        // if not enough vertical space, open a new atlas
        if shelf.y + ih > atlasSizePx {
            shelves[atlasIdx] = shelf
            makeNewAtlas()
            atlasIdx = atlases.count - 1
            shelf = shelves[atlasIdx]
        }
        
        // draw into atlas (note: CoreGraphics origin is bottom-left in our math here)
        let dstX = shelf.x + padding
        let dstY = shelf.y + padding
        let drawRect = CGRect(x: dstX, y: dstY, width: cg.width, height: cg.height)
        
        let ctx = atlases[atlasIdx]
        // Flip coordinate system because CG draws with origin at bottom-left if we set text matrix; simpler: draw with transform
        // Here we draw directly with UIKit-style y-up correction:
        ctx.saveGState()
        // CoreGraphics origin is bottom-left for our created bitmap; to draw UIImage upright:
        // drawRect is already correct because CGImage is pixel data without orientation.
        ctx.draw(cg, in: drawRect)
        ctx.restoreGState()
        
        // advance shelf
        shelf.x += iw
        shelf.h = max(shelf.h, ih)
        shelves[atlasIdx] = shelf
        
        // UVs in 0..1 (SceneKit expects bottom-left origin for textures)
        let u0 = CGFloat(dstX) / CGFloat(atlasSizePx)
        let v0 = CGFloat(dstY) / CGFloat(atlasSizePx)
        let u1 = CGFloat(dstX + cg.width) / CGFloat(atlasSizePx)
        let v1 = CGFloat(dstY + cg.height) / CGFloat(atlasSizePx)
        let uv = CGRect(x: u0, y: v0, width: (u1 - u0), height: (v1 - v0))
        
        return AtlasEntry(atlasIndex: atlasIdx, uvRect: uv, pixelSize: CGSize(width: cg.width, height: cg.height))
    }
    
    /// Freeze current atlas contexts into UIImages (call after packing).
    func snapshotAtlases() {
        for i in 0..<atlases.count {
            guard let cg = atlases[i].makeImage() else { continue }
            atlasImages[i] = UIImage(cgImage: cg, scale: scale, orientation: .up)
        }
    }
}

struct CircleKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension PreviewPopupTemplate {
    private func timelineDuration(for entries: [TapEntry]) -> Double {
        let groups = Dictionary(grouping: entries, by: \.groupId)

        var duration: Double = 0

        // grouped: add max value in each group
        for (gid, grouped) in groups where gid != 0 {
            duration += grouped.map(\.value).max() ?? 0
        }

        // singles: sum their values
        if let singles = groups[0] {
            for e in singles {
                duration += e.value
            }
        }

        return duration
    }

    /// Computes the total duration across *all* primaries and secondary keys
    /// for the current `modelName`. Returns seconds as `Double`.
    private func computeTotalDurationAcrossAllTaps() -> Double {
        guard let perPrimary = sharedData.cachedCommandData[modelName] else {
            return 0
        }

        var total: Double = 0

        for (_, perSecondary) in perPrimary {
            for (_, entries) in perSecondary {
                total += timelineDuration(for: entries)
            }
        }

        return total
    }

    private func buildPlayback(for primary: Int, secondaryKey: Int) {
        
        guard let perSecondary = sharedData.cachedCommandData[modelName]?[primary],
              let entries = perSecondary[secondaryKey] else {
            
            bucketDurations = [:]
            playbackTapEntries = [:]
            previewInSeconds = 0
            previewSeconds = 0
            return
        }

        
        bucketDurations = [:]
        playbackTapEntries = [:]

        var playback: [Double: [Int: [TapEntry]]] = [:]  
        var cursor: Double = 0.0
        var totalTimeline: Double = 0.0
        var listIndex = 0

        func append(at startTime: Double, listIndex: Int, entries: [TapEntry]) {
            var perIndex = playback[startTime] ?? [:]
            var arr = perIndex[listIndex] ?? []
            arr.append(contentsOf: entries)
            perIndex[listIndex] = arr
            playback[startTime] = perIndex

            
            let nonDelay = entries.filter { $0.entryType != "delay" && $0.value > 0 }
            let d: Double = nonDelay.map(\.value).max()
                ?? entries.first(where: { $0.entryType == "delay" })?.value
                ?? 0
            bucketDurations[startTime] = max(bucketDurations[startTime] ?? 0, d)
        }

        
        let groups = Dictionary(grouping: entries, by: \.groupId)

        
        for (gid, grouped) in groups where gid != 0 {
            let groupDur = grouped.map(\.value).max() ?? 0
            append(at: cursor, listIndex: listIndex, entries: grouped)
            cursor += groupDur
            totalTimeline += groupDur
        }

        
        if let singles = groups[0] {
            for e in singles {
                append(at: cursor, listIndex: listIndex, entries: [e])
                cursor += e.value
                totalTimeline += e.value
            }
        }

        playbackTapEntries = playback
        previewInSeconds = totalTimeline
        previewSeconds = 0.0
        selectedPrimary = primary

        startPlayback()
    }
}

private struct ButtonAnchorKey: Hashable {
    let primary: Int
    let secondary: Int
}

private struct KeyButtonFramePref: PreferenceKey {
    static var defaultValue: [ButtonAnchorKey: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ButtonAnchorKey: Anchor<CGRect>],
                       nextValue: () -> [ButtonAnchorKey: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}


private struct SecondaryCircle: View {
    let primary: Int
    let number: Int
    let isSelected: Bool
    let namesList: [Int:String]
    private let diameter: CGFloat = 72 * 0.8
    private var name: String { namesList[number] ?? "_" }
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? selectedAccent.color.opacity(0.16)
                      : Color.secondary.opacity(0.12))
                .overlay(
                    Circle()
                        .stroke(
                            selectedAccent.color.opacity(isSelected ? 0.9 : 0.45), 
                            lineWidth: 1.2
                        )
                )
                .shadow(radius: 8, x: 0, y: 4)
            
            Text("")
                .font(.headline.monospacedDigit())
                .opacity(isSelected ? 0.0 : 1.0)
            
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .transition(.scale.combined(with: .opacity))
                
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topLeading) {
            Text("#\(primary)")
                .font(.caption2).bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                .foregroundStyle(Color.white)
                .clipShape(Capsule())
                .offset(x: -6, y: -10)
                .allowsHitTesting(false)
        }
    
    }
}

private struct SecondarySplitView: View {
    let primary: Int
    let secondaries: [Int]   
    @Binding var selectedPair: (primary: Int, secondary: Int)?
    let commandNames: [Int: [Int: String]]
    let onTap: (_ primary: Int, _ secondary: Int) -> Void
    let onDeselect: (_ primary: Int, _ secondary: Int) -> Void   
    
    var diameter: CGFloat = 72 * 0.8
    var overlap: CGFloat  = 24 * 0.8
    var shadowRadius: CGFloat = 8
    var strokeWidth: CGFloat = 1.2
    var badgeOvershoot: CGFloat = 10
    
    private var namesList: [Int: String] {
        commandNames[primary] ?? [:]
    }
     
    
    private func isSelected(_ sec: Int) -> Bool {
        selectedPair?.primary == primary && selectedPair?.secondary == sec
    }

    private func toggle(_ sec: Int) {
        if isSelected(sec) {
            selectedPair = nil                 
            onDeselect(primary, sec)           
        } else {
            selectedPair = (primary, sec)      
            onTap(primary, sec)
        }
    }
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: -overlap) {
                ForEach(secondaries, id: \.self) { sec in
                    Button { toggle(sec) } label: {
                        SecondaryCircle(primary: primary, number: sec, isSelected: isSelected(sec), namesList: namesList)
                    }
                    .buttonStyle(.plain)
                    .frame(width: diameter, height: diameter)
                    .contentShape(Circle())
                    .accessibilityLabel("Primary \(primary), secondary \(sec)")
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: diameter, alignment: .center)

    }
}

private struct PrimaryCell: View {
    let primary: Int
    let secondaryKeys: [Int]
    @Binding var selectedPair: (primary: Int, secondary: Int)?
    let commandNames: [Int: [Int: String]]
    let onTap: (_ primary: Int, _ secondary: Int) -> Void
    let onDeselect: (_ primary: Int, _ secondary: Int) -> Void    
    
    private var namesList: [Int: String] {
        commandNames[primary] ?? [:]
    }
     
    private func isSelected(_ sec: Int) -> Bool {
        selectedPair?.primary == primary && selectedPair?.secondary == sec
    }

    private func toggle(_ sec: Int) {
        if isSelected(sec) {
            selectedPair = nil
            onDeselect(primary, sec)           
        } else {
            selectedPair = (primary, sec)
            onTap(primary, sec)
        }
    }
    
    
    var body: some View {
        VStack(spacing: 8) {
            if secondaryKeys.count == 2 {
                SecondarySplitView(
                    primary: primary,
                    secondaries: secondaryKeys,
                    selectedPair: $selectedPair,
                    commandNames: commandNames,
                    onTap: onTap,
                    onDeselect: onDeselect                 
                
                )
            } else {
                HStack(spacing: 10) {
                    ForEach(secondaryKeys, id: \.self) { sec in
                        Button { toggle(sec) } label: {
                            SecondaryCircle(primary: primary, number: sec, isSelected: isSelected(sec), namesList: namesList)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Primary \(primary), secondary \(sec)")
                        
                        .background(
                            Color.clear
                                .frame(width: 72, height: 72)
                                .anchorPreference(key: KeyButtonFramePref.self, value: .bounds) { anchor in
                                    [ButtonAnchorKey(primary: primary, secondary: sec): anchor]
                                }

                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

struct PreviewPopupTemplate: View {
    @EnvironmentObject var sharedData: SharedData
    @Binding var isVisible: Bool
    let modelName: String
    let modelDescription: String

    @State private var sliderValue: Double = 0.0
    let maxValue: Double = 60.0

    @State private var previewInSeconds: Double = 0.0
    @State private var previewSeconds: Double = 0.0
    @State private var isPlayingPreview = false
    @State private var playbackTimer: Timer? = nil
    @State private var playbackIsPlayed: Bool = false
    @State private var currentPlayers: [CHHapticAdvancedPatternPlayer] = []
    @State private var playbackTapEntries: [Double: [Int: [TapEntry]]] = [:]
    @State private var bucketDurations: [Double: Double] = [:]
    @State private var orderedKeys: [Double] = []
    @State private var nextBucketIndex = 0
    private let epsilon: Double = 0.0005
    @State private var playbackSpeed: Double = 1.0
    @State private var selectedPrimary: Int? = nil
    
    @State private var showFinger = false
    @State private var fingerScale: CGFloat = 1.0
    @State private var fingerOpacity: Double = 0.5
    @State private var keepShowingFinger = false
    @State private var selectedPair: (primary: Int, secondary: Int)?
    private var commandNames: [Int: [Int: String]] {[:]
    }

    
    private var primaryKeys: [Int] {
        Array(sharedData.cachedCommandData[modelName]?.keys
              ?? Dictionary<Int, [Int: [TapEntry]]>().keys)
            .sorted()
    }
    private func secondaryKeys(for primary: Int) -> [Int] {
        guard let dict = sharedData.cachedCommandData[modelName]?[primary] else { return [] }
        return Array(dict.keys).sorted()
    }
    private var gridColumns: [GridItem] {
        
        [GridItem(.adaptive(minimum: 72, maximum: 120), spacing: 12, alignment: .center)]
    }
    
  
    
    private func startFingerDemoIfNeeded() {
        
        guard
            let secs = sharedData.cachedCommandData[modelName]?[1]?.keys,
            (secs.contains(0) || secs.contains(1)),
            selectedPrimary == nil
        else {
            stopFingerDemo()
            return
        }
        keepShowingFinger = true
        triggerFingerTap()
    }

    private func triggerFingerTap() {
        guard keepShowingFinger else { return }
        showFinger = true
        fingerScale = 1.0
        fingerOpacity = 0.5

        let tapDuration = 0.18
        withAnimation(.easeOut(duration: tapDuration)) { fingerScale = 0.88; fingerOpacity = 0.6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + tapDuration) {
            guard keepShowingFinger else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                fingerScale = 1.1
                fingerOpacity = 0.5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard keepShowingFinger else { return }
            withAnimation(.easeOut(duration: 0.25)) { showFinger = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard keepShowingFinger else { return }
            triggerFingerTap()
        }
    }

    private func stopFingerDemo() {
        keepShowingFinger = false
        withAnimation(.easeOut(duration: 0.2)) { showFinger = false }
    }
    private let speeds: [Double] = [1.0, 1.5, 2.0, 5.0]
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @State private var totalDurationOfTaps: Double = 0.0
    var body: some View {
        if isVisible {
            ZStack {
                let secondsRounded = Int(round(totalDurationOfTaps))
                let minutesUp = Int(ceil(totalDurationOfTaps / 60))
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            stopCurrentHapticsImmediately()
                            previewInSeconds = 0.0
                            previewSeconds = 0.0
                            isPlayingPreview = false
                            playbackTimer = nil
                            playbackIsPlayed = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isVisible = false
                            }
                        }
                    }

                
                VStack(spacing: 16) {

                    Text("preview".localized())
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    // Centered Texts below the title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\("description".localized()) \(modelDescription)")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text(
                            totalDurationOfTaps < 60
                            ? "\("duration".localized()): \(secondsRounded) " + (secondsRounded == 1 ? "second".localized() : "seconds".localized())
                            : "\("duration".localized()): \(minutesUp) " + (minutesUp == 1 ? "minute".localized() : "minutes".localized())
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                    }

                    
                    
                    ScrollView {
                        
                        LazyVGrid(columns: gridColumns, alignment: .center, spacing: 12) {
                            ForEach(primaryKeys.filter { $0 != 999 }, id: \.self) { primary in
                                PrimaryCell(
                                    primary: primary,
                                    secondaryKeys: secondaryKeys(for: primary),
                                    selectedPair: $selectedPair,
                                    commandNames: commandNames,
                                    onTap: { p, sec in
                                        stopFingerDemo()
                                        if showFinger {
                                            withAnimation(.easeOut(duration: 0.2)) { showFinger = false }
                                        }
                                        previewInSeconds = 0.0
                                        stopCurrentHapticsImmediately()
                                        buildPlayback(for: p, secondaryKey: sec)
                                    },
                                    onDeselect: { _, _ in
                                        previewInSeconds = 0.0
                                        stopCurrentHapticsImmediately()
                                    }
                                )
                            
                            }
                        }

                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.3)
                    
                    .overlay(
                        Group {
                            if primaryKeys.isEmpty {
                                Text("No data")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 12)
                            }
                        }, alignment: .center
                    )
                    
                    HStack(spacing: 12) {
                        ForEach(speeds, id: \.self) { speed in
                            Button {
                                let current = previewSeconds
                                playbackSpeed = speed
                                if isPlayingPreview {
                                    
                                    pausePlayback()
                                    seek(to: current)
                                    startPlayback()
                                }
                            } label: {
                                Text("x\(speed, specifier: "%.1f")")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(playbackSpeed == speed ? selectedAccent.color : Color.gray.opacity(0.2))
                                    .foregroundStyle(playbackSpeed == speed ? .white : .primary)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .padding(20)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isVisible)
                
                .overlayPreferenceValue(KeyButtonFramePref.self) { anchors in
                    GeometryReader { proxy in
                        Group {
                            if showFinger,
                               let firstPrimary = primaryKeys.filter({ $0 != 999 }).first {
                                let secs = secondaryKeys(for: firstPrimary)
                                if let firstSec = secs.first,
                                   let a = anchors[ButtonAnchorKey(primary: firstPrimary, secondary: firstSec)] {
                                    let rect = proxy[a]
                                    ZStack {
                                        Circle()
                                            .strokeBorder(
                                                selectedAppearance.colorScheme == .dark
                                                    ? Color.white.opacity(0.6)
                                                    : Color.black.opacity(0.6),
                                                lineWidth: 2
                                            )
                                            .frame(width: 64 * fingerScale, height: 64 * fingerScale)
                                            .opacity(fingerOpacity * 0.8)

                                        Image(systemName: "hand.point.up.left.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 40, height: 40)
                                            .foregroundStyle(
                                                selectedAppearance.colorScheme == .dark
                                                    ? Color.white.opacity(0.6)
                                                    : Color.black.opacity(0.6)
                                            )
                                            .opacity(fingerOpacity)
                                            .scaleEffect(fingerScale)
                                            .rotationEffect(.degrees(-20))
                                    }
                                    .position(x: rect.midX, y: rect.midY)
                                }
                            }
                        }
                    }
                }



            }
            .onAppear {
                startFingerDemoIfNeeded()
                
                totalDurationOfTaps = computeTotalDurationAcrossAllTaps()
            }
            .onDisappear {
                stopCurrentHapticsImmediately()
            }
            
        }
    }
    
    
     
    private func nextIndexFor(time: Double) -> Int {
        ensureOrderedKeys()
        let ub = indexAfter(time: time)              
        let i = max(0, ub - 1)                       
        if i < orderedKeys.count {
            let k = orderedKeys[i]
            let dur = bucketDurations[k] ?? 0
            if time + epsilon < k + dur {            
                return i                             
            }
        }
        return ub                                    
    }
    func extractFirstInt(from text: String) -> Int? {
        let digits = text.compactMap { $0.isNumber ? String($0) : nil }.joined()
        return digits.isEmpty ? nil : Int(digits)
    }

    private func stopCurrentHapticsImmediately() {
        currentPlayers.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
        currentPlayers.removeAll()
        playbackIsPlayed = false
    }
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

}
