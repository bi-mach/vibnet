//
//  BuildView.swift
//  Vibro
//
//  Created by lyubcsenko on 16/05/2025.
//

import SwiftUI
import UIKit
import CoreHaptics
import FirebaseAuth
import Network
import QuartzCore   // <- needed for CADisplayLink / CACurrentMediaTime
import FirebaseStorage
extension View {
    @ViewBuilder
    func sheetCornerRadius(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationCornerRadius(radius)
        } else {
            self
        }
    }
}




struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

enum HapticStep {
    case single(TapEntry)                 // play one entry
    case parallel(TapEntry, TapEntry)     // play two at once (m1 + m2)
}

private struct GridHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct CustomAlert: View {
    let title: String
    let message: String
    let buyAction: () -> Void
    let cancelAction: () -> Void
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.headline)
                .lineLimit(50)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary)
            
            Text(title)
                .font(.body)
                .lineLimit(50)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary)
            
            HStack {
                Button("cancel".localized(), action: cancelAction)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(selectedAccent.color.opacity(0.7))
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
                
                Button("buy".localized(), action: buyAction)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
                    .foregroundStyle(selectedAccent.color)
                
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
        .shadow(radius: 10)
        .padding(.horizontal, 40)
    }
}
struct OnboardingPopup: View {
    @State private var expanded = false
    @State private var waveRotation: Double = -20

    @Binding var isPresented: Bool
    
    let isPreviewingModel: Bool
    // Fade config
    @State private var isVisible = false
    private let fadeDuration: Double = 0.35

    private let plainMessage = "welcome_for_new_in_build".localized()

    private var shortMessage: String {
        let count = plainMessage.count
        let take = max(1, Int(Double(count) * 0.25))
        let end = plainMessage.index(plainMessage.startIndex, offsetBy: min(take, count))
        let needsEllipsis = end < plainMessage.endIndex
        return String(plainMessage[..<end]) + (needsEllipsis ? "…" : "")
    }
    

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plainMessage)
                        .font(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(2)
                    
                    HStack(alignment: .top, spacing: 16) {
                        // Left side: durations
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image("line")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 20)
                                    .rotationEffect(.degrees(90))
                                    .foregroundStyle(.primary)
                                    .accessibilityLabel("Single line (I)")
                                
                                Image("2line")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 20)
                                    .rotationEffect(.degrees(90))
                                    .foregroundStyle(.primary)
                                    .accessibilityLabel("Double line (II)")
                            }
                            Text("are_durations".localized())
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity) // ⬅️ take equal space
                        
                        // Right side: delays
                        VStack(spacing: 4) {
                            Image("delay")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 20)
                                .foregroundStyle(.primary)
                                .accessibilityLabel("Delay (O)")
                            
                            Text("are_delays".localized())
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity) // ⬅️ take equal space
                    }
                    .padding(.top, 10)
                }

                HStack(alignment: .center, spacing: 6) {
                    Text("tap_big_plus".localized())
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.15)))
            .contentShape(Rectangle())
            .shadow(radius: 8, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // Fade in/out
            .opacity(isPresented && !isPreviewingModel ? 1 : 0)
            .animation(.easeInOut(duration: fadeDuration), value: isVisible)

            .onAppear { isVisible = true }

            // iOS 14–16: old onChange
            .onChange(of: isPresented) { presented in
                if !presented { fadeOutBeforeRemoval() }
            }
            // iOS 17+: optional nicer signature (kept guarded so it compiles everywhere)
            .modifier(OnChange17Compat(isPresented: $isPresented) { oldValue, newValue in
                if oldValue == true && newValue == false { fadeOutBeforeRemoval() }
            })
        }
    }

    // Call this from inside the popup to close with fade
    private func dismiss() {
        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            isPresented = false
        }
    }

    // Called when parent sets binding to false; we fade but DON'T flip it again.
    private func fadeOutBeforeRemoval() {
        isVisible = false
    }
}

struct OnChange17Compat: ViewModifier {
    @Binding var isPresented: Bool
    let action: (_ oldValue: Bool, _ newValue: Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: isPresented, initial: false, action)
        } else {
            content // no-op; handled by the old .onChange above
        }
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}




struct BuildView: View {
    @EnvironmentObject var sharedData: SharedData
    private let defaults = UserDefaults.standard
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @EnvironmentObject var tapsFunctions: TapsFunctions
    @FocusState private var isTextFieldFocused: Bool

    let model: Model
    let isPreviewingModel: Bool
    let favouriteModels: [String: Model]
    let isInSheet: Bool

    // ✅ OPTIONAL / NOT REQUIRED
    let openModelCard: Bool?   // example additional variable

    // ✅ Custom initializer with default
    init(
        model: Model,
        isPreviewingModel: Bool,
        favouriteModels: [String: Model],
        isInSheet: Bool,
        openModelCard: Bool? = nil   // 👈 default makes it optional to pass
    ) {
        self.model = model
        self.isPreviewingModel = isPreviewingModel
        self.favouriteModels = favouriteModels
        self.isInSheet = isInSheet
        self.openModelCard = openModelCard
    }


    
    @State private var selectedConnectionIds: Set<Double> = []
    @State private var isFavouriteModel: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var previewModelBuild: Bool = false
    @State private var showLine: Bool = false
    @State private var selectedCMND: Int = 0
    @State private var selectedEntryIndices: Set<Int> = []
    @State private var showTAPSModificationLine: Bool = false
    @State private var selectedPart: Int = 0
    @State private var showSetCMNDType = false
    @State private var CMNDType: Int = 1
    @State private var vibrationSetup: Bool = false
    @State private var TapData: [Int: [Int: [TapEntry]]] = [:]
    @State private var initialTapData: [Int: [Int: [TapEntry]]] = [:]
    @State private var selectedCMNDType: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var targetKey: Int? = nil
    @State private var delaySlider: Double = 0.01
    @State private var durationSlider: Double = 0.1 /***/
    @AppStorage("selectedOption") private var selectedOption: Int = 1
    @State private var saveFolder: String = ""
    @State private var pressStartTime: Date?
    @State private var pressDuration: Double = 0.0
    @State private var countdownText: String? = nil
    @State private var countdownTimer: Timer? = nil
    @State private var TapCircleSize: CGFloat = 0.0
    @State private var countdownRemaining: Double = 1.00
    @State private var pressDurations: [(Int, Double)] = []
    @State private var buttons: [Int] = []
    @State private var ColorScheme: Bool = (UserDefaults.standard.object(forKey: "ColorScheme") as? Bool ?? (UITraitCollection.current.userInterfaceStyle == .dark))
    @AppStorage("modelAliasMapJSON") private var modelAliasMapJSON: String = "{}"
    @State private var isManagementView: Bool = false
    @State private var userEmail: String = ""
    @State private var creatorUserName: String = ""
    @State private var userID: String = ""
    @State private var holdDuration: Double = 0.0
    @State private var isIncreasing: Bool = true
    @State private var adjustingDelay = true // track which slider is being updated
    @State private var timer: Timer?
    @State private var IsStructureWrong:Bool = false
    @State private var showStructuralAlert: Bool = false
    @State private var showDeleteBlockConfirmation: Bool = false
    @State private var showDeleteFor2BlockConfirmation: Bool = false
    @State private var groupColors: [Int: [Int: [Int: Color]]] = [:]
    @State private var UsersTaps: [Int: String] = [:]
    @State private var showVibrationsSetup: Bool = false
    @State private var showInControlSpacePowerOptions: Bool = false
    @State private var showInControlSpaceServoOptions: Bool = false
    @State private var suppressNextSetupSwitchTap = false

    @State private var creatingAGroup: Bool = false
    @State private var selectedDevice: Device = .iphone
    @State private var playbackIsPlayed: Bool = false
    @State private var showTapsAreEmpty: Bool = false
    @FocusState private var focusedKey: Int?
    @State private var commandNames: [Int: [Int: String]] = [:]
    @State private var renamingCommand: Int? = nil
    @State private var renamingPart: Int? = nil
    @State private var showPlayView = false
    @State private var playViewShouldOpen = false
    @State private var modelIsEmpty = false
    @State private var showAdSheet = false
    @State private var showedAdSheet = false
    @State private var showControlSelectionDelay = false
    @State private var showControlSelectionVibrations = false
    @AppStorage("controlsForDelay") private var controlsForDelay: String = "drawer"
    @AppStorage("controlsForVibrations") private var controlsForVibrations: String = "drawer"
    @State private var lineColor: Color = .primary
    
    @State private var userDragging = false

    @State private var lastFollowTick: CFTimeInterval = 0
    @State private var lastEndXTapScroll: CGFloat = 0
    @State private var lastFollowedId: Int = -1

    
    @State private var scrollEndWork: DispatchWorkItem?
    @State private var lastScrollX: CGFloat = .zero

    // baseline smoothing per connection id (0...1)
    @State private var connDragBaseS: [Double: Double] = [:]

    
    private let likeSpamThreshold  = 10
    private let likeCooldownWindow: TimeInterval = 30*60
    private let likeSpamWindow:    TimeInterval = 60
    @AppStorage("likingModelCooldownUntil") private var likingCooldownUntil: Double = 0
    @AppStorage("likingModelSpamCount")     private var likingSpamCount: Int = 0
    @AppStorage("likingModelLastTap")       private var likingLastTap: Double = 0
    @State private var showLikeCooldownAlert = false
    @State private var likeCooldownMessage   = ""
    
    @State private var lineColorDuration: Color = .primary
    @State private var inBuildIsPreviewingModel: Bool = false
    @State private var gridContentHeight: CGFloat = 0
    @State private var dataHasBeenSaved: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("tapData") private var tapDataJSON: Data = Data()
    
    @State private var hitDelayMax = false   // prevents repeated buzzes at the edge
    @State private var hitVibrationMax = false   // prevents repeated buzzes at the edge
    @State private var xDirLatch: Int = 0   // -1,0,+1x
    @State private var motorScratch: Double = 0.0
    @State private var pendingDelayValue: Double = 0.01
    @State private var isTapped = false // <-- Add this at the top of your View
    @State private var pendingMotorValue: Double = 0.1 /***/
    let bottomAnchorID = "GRID_BOTTOM"
    @State private var loadingWorkItem: DispatchWorkItem?
    @State private var showLoading: Bool = false
    @State private var showDescriptionKey: Int = 0
    @State private var forTacticleConnectDevice = false
    @AppStorage("lastUsedEntries") private var lastUsedEntriesData: Data = Data()
    @State private var showVibInfo: Bool = false
    @State private var tapFunctionalityJustAppended = false
    @State private var firstTimeInControl: Bool = true
    @State private var tappedTheButton: Bool = false
    @State private var waveHitRanges: [(id: Int, minX: CGFloat, maxX: CGFloat, y: CGFloat)] = []
    @State private var connectionHitRanges: [
        (id: Double,
         start: CGPoint,
         end: CGPoint,
         minX: CGFloat, maxX: CGFloat,
         minY: CGFloat, maxY: CGFloat)
    ] = []
    @State private var liveMotorType: String = "m2"

    private func motorType(forY y: CGFloat, canvasHeight: CGFloat) -> String {
        guard canvasHeight > 0 else { return "m2" }

        // 0.0 at bottom, 1.0 at top
        let normalizedFromBottom = 1.0 - (y / canvasHeight)

        switch normalizedFromBottom {
        case let r where r >= 0.7:
            return "m3"
        case let r where r >= 0.4:
            return "m2"
        case let r where r >= 0.1:
            return "m1"
        default:
            return "m1"
        }
    }

    private var aliasMap: [String:String] {
        (try? JSONDecoder().decode([String:String].self, from: Data(modelAliasMapJSON.utf8))) ?? [:]
    }
    private var displayName: String {
        if let alias = aliasMap[model.name.canonName], !alias.isEmpty {
            return alias
        }
        return model.name
    }
    private var modelAliasMap: [String:String] {
        get {
            guard let data = modelAliasMapJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String:String].self, from: data)
            else { return [:] }
            return dict
        }
        
        nonmutating set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8)
            modelAliasMapJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }
    @State private var connDragAnchorX: CGFloat? = nil
    @State private var connDragBase: [Int: (start: Double, end: Double)] = [:]
    private let controlOrder = ["drawer", "tap", "arrows", "slider"]
    @State private var tapHoldBucket: Double = 0    // accumulates elapsed time between steps
    @State private var tapHoldDir: Int = 0          // -1 (down), +1 (up), 0 (idle)
    @State private var tapHoldHoldDuration: TimeInterval = 0
    @State private var autoScrollEnabledTaps = true
    @State private var lastMaxKeyTaps: Int? = nil
    @AppStorage("motorFirst") private var motorFirst: Bool = true
    @State var autoScrollEnabled: Bool = true // optional guard
    @AppStorage("firstTimerSmilingFaceEmoji") private var firstTimerSmilingFaceEmoji: Bool = false
    @State private var showOnBoardingPopup: Bool = false
    @State private var controlSpaceUUID = UUID()
    @State private var unifiedValue: Double = 0.01
    @State private var modifyingEntryType: String? = nil
    // Keep this state near your view
    @State private var prevAvgAtEdge: Bool = false
    @State private var prevPerItemValues: [Int: Double] = [:]
    @State private var firstSelect: Bool = true
    @State private var didAutoScroll = false
    @State private var shouldHideSparkles: Bool = false
    @State private var suppressHapticsDueTo01Selection = false
    @State private var viewport: CGRect = .zero
    @State private var visibleIds: [Int] = []
    private func effectiveColumnCount(_ columns: [GridItem], containerWidth: CGFloat) -> Int {
        // If you supplied several items (fixed/flexible), the count is explicit
        if columns.count > 1 { return columns.count }
        guard let g = columns.first else { return 1 }

        switch g.size {
        case .fixed:                      return 1
        case let .flexible(min, _):       // one flexible item means 1 column
            return min > 0 ? 1 : 1
        case let .adaptive(min, _):       // compute how many fit
            let spacing = g.spacing ?? 0
            return max(Int((containerWidth + spacing) / (min + spacing)), 1)
        @unknown default:
            return 1
        }
    }
    @State private var yDirAnchorValue: Double? = nil   // value baseline at start of current direction
    @State private var lastXForValueGate: CGFloat? = nil

    @State private var holdingLeft  = false
    @State private var holdingRight = false
    @State private var modifyingValueNow: Int? = nil
    @State private var connectedToNetwork: Bool = true
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @AppStorage("selectedServoSet") private var selectedServoSetData: Data = Data()

    private var selectedServoSetArray: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: selectedServoSetData)) ?? [1,2,3] }
        set { selectedServoSetData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    private var selectedServoSet: Set<Int> {
        Set(selectedServoSetArray)
    }


    @State private var showAdSheet2: Bool = false
    
    enum ModifyMode { case none, delay, motor }
    @State private var modifyMode: ModifyMode = .none
    @State private var showDetails: Model? = nil
    @State private var isFavouriteModel2: Bool = false
    
    @State private var controlLiveKey: Int? = nil
    @State private var controlLiveType: String? = nil   // "delay" or "m1"/"m2"/"m3"
    @State private var controlIsEditing = false         // gates repeated auto-appends

    
    @AppStorage("useMicrophone") private var useMicrophone: Bool = false
    private let modeAnim = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.18)
    private func rebuildButtons() {
        var list = Array(
            TapData.keys
                .filter { (0...9).contains($0) }
                .sorted()
                .prefix(10)
        )
        buttons = list
    }

    
    @State private var globalOriginalIndex: Int = 0
    @State private var itemRectsGlobal: [Int: CGRect] = [:]

    @State private var waveCenters: [(CGPoint, TimeInterval)] = [] // Stores the locations of the taps
    @State private var waveCentersForProcessing: [(CGPoint, TimeInterval)] = []
    @State private var holdData: [(Int, Int, Int)] = []
    @State private var waveValues: [Int] = []
    @State private var lastWaveLocation: CGPoint?
    @State private  var dragDirection: Int = 0
    @State private  var dragHold: TimeInterval = 0.0
    @State private  var lastDragTime: Date?
    @State private  var justJoined: Bool = false

    @State private var dragLocation: CGPoint? = nil // Tracks the finger's location
    @State private var contactLocation: CGPoint? = nil // Tracks the finger's location
    @State private var gestureStartTime: Date? = nil
    //
    //@State private var pressDuration: TimeInterval = 0.0 USED IN OTHER VERSION!!!!
    //
    
    @State private var tapLiveKey: Int? = nil
    @State private var tapLiveFingerCount: Int = 0
    @State private var tapLiveHoldSeconds: Double = 0
    private func updateTapValue(
        TAPS: Binding<[Int: [Int: [TapEntry]]]>,
        selectedCMND: Int,
        selectedPart: Int,
        key: Int,
        to newVal: Double
    ) {
        guard var cmndDict = TAPS.wrappedValue[selectedCMND],
              var arr = cmndDict[selectedPart],
              let idx = arr.firstIndex(where: { $0.key == key }) else { return }

        let clamped = min(60.0, max(0.01, newVal))
        let snapped = (clamped / 0.01).rounded() * 0.01

        arr[idx] = arr[idx].withValue(snapped)
        cmndDict[selectedPart] = arr
        TAPS.wrappedValue[selectedCMND] = cmndDict
    }

    
    @State private var showLoadingIcon: Bool = false // Show or hide the loading icon
    @State private var inactivityTimer: Timer? = nil // Tracks inactivity
    
    @State private var GestureSwitch: Int = 1
    
    @State private var totalScreenWidth: CGFloat = 0.0
    @State private var totalScreenHeight: CGFloat = 0.0
    @State private var sideRectangleWidth: CGFloat = 0.0
    @State private var verticalRectangleHeight: CGFloat = 0.0
    @State private var leaveButtonWidth: CGFloat = 0.0
    @State private var leaveButtonHeight: CGFloat = 0.0
    @State private var StartCounter: Bool = false
    @State private var gestureHoldStartTime: Date? = nil
    @State private var lastHoldEndTime: Date?
    
    @State private var canvasWidth: CGFloat = 0.0
    @State private var canvasHeight: CGFloat = 0.0
    
    @State private var dragRunDistanceX: CGFloat = 0
    @State private var dragRunLastX: CGFloat? = nil
    @State private var dragRunLastY: CGFloat? = nil
    
    @State private var dragBaselineValue: Double = 0   // v₀ at drag start
    @State private var dragBaselineX: CGFloat = 0      // x for v₀ on the canvas

    @State private var dragStartX: CGFloat? = nil
    @State private var dragStartY: CGFloat? = nil
    @State private var dragStartValue: Double = 0

    @State private var waves: [Wave] = []
    @State private var startedWaveIDs = Set<UUID>()
    @State private var animatingCircles = Set<UUID>()

    @State private var lastTouchDate: Date? = nil
    @State private var waveInactivityTimer: Timer? = nil
    @State private var modifyingEntryKey: Int? = nil
    
    @State private var isPillPressing = false
    @State private var addedToFav = false
    @State private var pillFillProgress: CGFloat = 0
    @State private var showBrokenHeart = false
    private func resetWaveInactivityTimer() {
        waveInactivityTimer?.invalidate()
        waveInactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            // If there truly hasn't been touch for >= 1s, clear waves
            let delta = Date().timeIntervalSince(lastTouchDate ?? .distantPast)
            if delta >= 0.5 {
                DispatchQueue.main.async {
                    waveCenters.removeAll()
                    waveValues.removeAll()
                    gestureStartTime = nil
                }
            }
        }
    }

    private func markTouch() {
        lastTouchDate = Date()
        resetWaveInactivityTimer()
    }
    
    @State private var processingLastPoint: CGPoint? = nil
    @State private var didTriggerAnalysisThisGesture = false

    @State private var trajWindow: [CGPoint] = []
    @State private var trajPeakY: CGFloat = .infinity   // remember smallest y (highest point)

    @State private var modifyingValueNowTicks: Int? = nil  // nil => not in modify mode
    @State private var trajBottomY: CGFloat = -.infinity
    
    enum Segment { case none, motor, delay }

    @State private var segment: Segment = .none
    @State private var currentEntryKey: Int? = nil          // key of entry being modified in current segment
    @State private var segmentStartY: CGFloat? = nil

    @State private var motorAvgUp: CGFloat = 0              // running avg up magnitude (px)
    @State private var motorUpSamples: Int = 0


    @State private var motorEntryKey: Int?
    @State private var delayEntryKey: Int?
    @State private var motorValueTicks: Int?
    @State private var delayValueTicks: Int?
    // 2) User override is the ONLY writable value from the UI
    //    (keep your layoutOverride if you want; rename for clarity)
    @State private var userLayoutOverride: Int? = nil
    enum YDir { case up, down, none }

    @State private var yDir: YDir = .none
    @State private var yDirAnchorY: CGFloat? = nil   // where the current direction started
    @State private var lastYForShift: CGFloat? = nil // for dy

    @State private var segAnchorPoint: CGPoint? = nil
    @State private var segAnchorValue: Double? = nil

    @State private var hasTractionThisGesture = false
    @State private var tractionStartPoint: CGPoint? = nil
    @State private var movedRightThisSegment = false
    @State private var nameWidth: CGFloat = 0

    @State private var fillWorkItem: DispatchWorkItem?

    @State private var showFavToast = false
    @State private var layoutOverride: Int? = nil   // nil = follow majority
    @State private var isPressingPill = false

    @State private var showDetailInSheet: Model? = nil
    
    @State private var selectionHaptic = UISelectionFeedbackGenerator()
    
    @State private var itemRects: [Int: CGRect] = [:]
    @State private var itemEnds: [Int: CGFloat] = [:]
    
    @State private var setupSwitchHoldTask: Task<Void, Never>?
    @State private var setupSwitchOpenTask: Task<Void, Never>?

    @State private var isHoldingSetupSwitch = false
    @State private var didLongPressSetupSwitch = false
    @State private var setupSwitchHoldProgress: CGFloat = 0

    @State private var isTappedRight = false
    @State private var isTappedLeft = false
    @State private var isTappedMiddle = false

    @AppStorage("isServoRotateUp") private var isServoRotateUp: Bool = true
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.colorScheme) var scheme
    @State private var blobResetToken: Int = 0
    
    @State private var blobPosition: CGPoint? = nil
    @State private var blobDragOffset: CGSize = .zero
    @State private var isDraggingblob = false
    
    @AppStorage("blobPosX") private var blobPosX: Double = 0
    @AppStorage("blobPosY") private var blobPosY: Double = 0
    @AppStorage("useAICompanion") private var useAICompanion: Bool = false

    let text100 =
    """

    """
    @State private var blobIsPressed = false
    @State private var chatDummy: [ChatMessage] = [
    ]


    @State private var isDockedToEdge: Bool = false
    var body: some View {
        ZStack(alignment: .top) {
            // Accent background behind content, but not responsible for system bars
            let accent: Color = {
                let user = Auth.auth().currentUser
                if let user, !user.isAnonymous, model.creator != "mode123456789"{
                    
                    if let color = sharedData.imageAccentColors[model.name] {
                        return color
                    }
                    if isPreviewingModel,
                       let color = sharedData.publishedAccentColors[model.name] {
                        return color
                    }
                
                }
                if model.creator == "mode123456789"{
                    
                    if let color = sharedData.imageAccentColors[model.name] {
                        return color
                    }
                }
                if isPreviewingModel,
                   let color = sharedData.publishedAccentColors[model.name] {
                    return color
                }
                return selectedAccent.color
            }()
            let isDisabled = isPreviewingModel || isFavouriteModel
            let canUnlike = isFavouriteModel
            let canLike   = isPreviewingModel && !isFavouriteModel
            
            accent.opacity(0.08)
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                let size   = geometry.size
                let base   = min(size.width, size.height)
                let scale  = base / 375.0
                
                // Core metrics (all numbers are "design points" × scale)
                let circleDia      = 72 * scale        // was width * 0.20 ≈ 75 on 375
                let rowGapBase     = 15 * scale
                let badgeLift      = circleDia/2 + 6 * scale
                
                let defaultPos = CGPoint(
                    x: geometry.size.width * 0.85, // right side like now
                    y: geometry.size.height * 0.5
                )
                let currentPos = blobPosition ??
                    (blobPosX == 0 && blobPosY == 0
                        ? defaultPos
                        : CGPoint(x: blobPosX, y: blobPosY))

               
                let blobRectWidth = geometry.size.width * 0.5
                let blobWidth = geometry.size.width * 0.6
                let textWidth = blobRectWidth
                let maxTextHeight: CGFloat = 72 // ~3 lines at 16pt

                let msg = chatDummy.max(by: { $0.date < $1.date }) // most recent

                let textPanel =
                    ZStack(alignment: .top) {

                        // 👇 One continuous background
                        Color.black.opacity(0.2)

                        // 👇 Layout container
                        VStack(spacing: 0) {

                            // Fixed top safe zone (not scrollable)
                            Color.clear
                                .frame(height: maxTextHeight * 0.1)

                            // Scrollable area
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 1) {

                                    Text(msg?.comments ?? "")
                                        .foregroundColor(.primary)
                                        .font(.system(size: 16))
                                        .fixedSize(horizontal: false, vertical: true)

                                    TapDrawingInlineView(
                                        text: msg?.text ?? "",
                                        accent: selectedAccent.color
                                    )
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: maxTextHeight * 0.9)
                        }
                    }
                    .frame(width: blobRectWidth, height: maxTextHeight)



                ZStack {
                    // one place to define sizes so everything matches
                    let diameter: CGFloat   = geometry.size.width * 0.20
                    let badgeLift: CGFloat  = diameter/2 + 6             // your "#n" badge sticks up this much
                    let baseRowGap: CGFloat = geometry.size.width * 0.04 // desired gap between rows
                    
                    let columns = Array(repeating: GridItem(.flexible(),
                                                            spacing: geometry.size.width * 0.04),
                                        count: 3)
                    
                    // rows are farther apart (accounts for badge + base gap)
                    let rowSpacing: CGFloat = baseRowGap + badgeLift
                    let scrollHeight = circleDia + badgeLift



                    
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {

                                    // ✅ exactly ONE row
                                    let rows = [
                                        GridItem(.fixed(circleDia), spacing: 0, alignment: .center)
                                    ]
                                    let orderedButtons: [Int] = {
                                        var arr = buttons
                                        // Move ALL zeros to the end (safe even if 0 appears multiple times)
                                        let zeros = arr.filter { $0 == 0 }
                                        arr.removeAll { $0 == 0 }
                                        return arr + zeros
                                    }()

                                    LazyHGrid(rows: rows, spacing: rowGapBase) {
                                        ForEach(Array(orderedButtons.enumerated()), id: \.element) { index, key in
                                            let cmndType = TapData[key]?.keys.first ?? 0
                                            let secondaryKeys = TapData[key]?.keys.sorted() ?? []

                                            let diameter: CGFloat = circleDia
                                            let overlap: CGFloat = 0.03 * geometry.size.width

                                            Group {


                                                if cmndType == 0 {

                                                    let circleView =
                                                    ZStack {
                                                        Circle()
                                                            .fill(
                                                                selectedCMND == key
                                                                ? Color.secondary.opacity(0.12)
                                                                : accent.opacity(0.16)
                                                            )
                                                            .overlay(
                                                                Circle().stroke(
                                                                    accent.opacity(selectedCMND == key ? 0.45 : 0.9),
                                                                    lineWidth: 1.2
                                                                )
                                                            )

                                                        Text("")
                                                            .font(.headline.monospacedDigit())
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(2)
                                                            .minimumScaleFactor(0.6)
                                                            .multilineTextAlignment(.center)
                                                            .padding(.horizontal, 10)
                                                    }
                                                    .frame(width: diameter, height: diameter)
                                                    .contentShape(Circle())
                                                    .overlay(alignment: .topLeading) {
                                                        Text("#\(key)")
                                                            .font(.caption2).bold()
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(Color.primary.opacity(0.35))
                                                            .foregroundStyle(Color.primary)
                                                            .clipShape(Capsule())
                                                            .offset(x: -6 * scale, y: -10 * scale)
                                                            .allowsHitTesting(false)
                                                    }
                                                    .offset(!isPreviewingModel && isDragging && selectedCMND == key ? dragOffset : .zero)
                                                    .scaleEffect(targetKey == key ? 1.1 : 1.0)
                                                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.2), value: targetKey)
                                                    .zIndex(selectedCMND == key ? 1 : 0)

                                                    circleView
                                                        .onTapGesture {
                                                            if selectedCMND == key {
                                                                selectedCMND = 0
                                                                selectedPart = 0
                                                                selectedCMNDType = 0
                                                                controlSpaceUUID = UUID()
                                                                selectedEntryIndices.removeAll()
                                                                showTAPSModificationLine = false
                                                            } else {
                                                                selectedCMND = key
                                                                selectedCMNDType = 0
                                                                selectedPart = 0
                                                                controlSpaceUUID = UUID()
                                                                showTAPSModificationLine = true
                                                                selectedEntryIndices.removeAll()
                                                            }
                                                        }
                                                        .simultaneousGesture(
                                                            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                                                                .onChanged { value in
                                                                    guard selectedCMND == key else { return }
                                                                    guard !isPreviewingModel else { return }

                                                                    // ✅ If the user is dragging mostly horizontally, let ScrollView scroll.
                                                                    if abs(value.translation.width) > abs(value.translation.height) {
                                                                        return
                                                                    }


                                                                }
                                                                .onEnded { value in
                                                                    guard selectedCMND == key else { return }
                                                                    guard !isPreviewingModel else { return }

                                                                    // If it was mostly horizontal, do nothing (ScrollView handled it)
                                                                    if abs(value.translation.width) > abs(value.translation.height) {
                                                                        return
                                                                    }

                                                                }
                                                        )

                                                        .simultaneousGesture(
                                                            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                                                if isPreviewingModel { return }
                                                                guard !isDragging else { return }
                                                                selectedCMND = key
                                                                selectedEntryIndices.removeAll()
                                                                selectedCMNDType = cmndType
                                                                selectedPart = 0
                                                                showTAPSModificationLine = true
                                                            }
                                                        )
                                                        .contextMenu {
                                                            if !isPreviewingModel {
                                                                Button("delete".localized(), role: .destructive) {
                                                                    selectedPart = 0
                                                                    selectedCMND = key
                                                                    selectedCMNDType = cmndType
                                                                    TapData.removeValue(forKey: selectedCMND)
                                                                    rebuildButtons()
                                                                }
                                                            }
                                                        }

                                                } else {
                                                    Button {
                                                        if let newKey = addButton() {
                                                            // ✅ auto-select the new one
                                                            selectedCMND = newKey
                                                            selectedCMNDType = CMNDType

                                                            // pick a sensible default part
                                                            if CMNDType == 2 {
                                                                selectedPart = 1      // or 2, your choice
                                                            } else {
                                                                selectedPart = 0
                                                            }

                                                            showTAPSModificationLine = true
                                                            selectedEntryIndices.removeAll()

                                                            // Optional: if you keep your end-anchor scroll, this will still scroll to the end.
                                                            // If you want to scroll to the new bubble specifically, see the ScrollViewReader variant below.
                                                        }
                                                    } label: {
                                                        Text("+")
                                                            .font(.largeTitle)
                                                            .foregroundStyle(Color.primary.opacity(0.6))
                                                            .frame(width: diameter, height: diameter)
                                                    }

                                                    .disabled(TapData.keys.count == 9)
                                                    .opacity((TapData.keys.count == 9) ? 0.5 : 1.0)
                                                }
                                            }
                                            .padding(.top, badgeLift) // ✅ keep room for badge (single row)
                                        }

                                        Color.clear.frame(width: 1).id(bottomAnchorID) // anchor at end (horizontal)
                                    }
                                    .padding(.horizontal, rowGapBase)
                                }
                                .frame(height: scrollHeight)         // ✅ lock scroller height
                                .clipped()
                                .onChange(of: TapData.keys.count) { _ in
                                    scrollToEnd(proxy)
                                }

                            }

                            SoftNeonDivider(accent: accent)
                            if showTAPSModificationLine {
                                
                                renderRemoveOrCloseButton2(
                                    TAPS: $TapData,
                                    selectedCMND: selectedCMND,
                                    selectedCMNDType: selectedPart,
                                    selectedAccent: accent,
                                    isPreviewingModel: isPreviewingModel,
                                    playbackIsPlayed: $playbackIsPlayed,
                                    lastMaxKeyTaps: $lastMaxKeyTaps,
                                    showStructuralAlert: $showStructuralAlert,
                                    autoScrollEnabledTaps: $autoScrollEnabledTaps,
                                    selectedEntryIndices: $selectedEntryIndices,
                                    showTAPSModificationLine: $showTAPSModificationLine,
                                    showDeleteBlockConfirmation: $showDeleteBlockConfirmation,
                                    showDeleteFor2BlockConfirmation: $showDeleteFor2BlockConfirmation,
                                    groupColors: $groupColors,
                                    inBuildIsPreviewingModel: $inBuildIsPreviewingModel,
                                    viewport: $viewport,
                                    visibleIds: $visibleIds,
                                    itemRects: $itemRects,
                                    itemEnds: $itemEnds,
                                    geometry: geometry
                                )
                                .offset(y: 24)

                                
                                if !inBuildIsPreviewingModel {
                                    controlsSpace(
                                        TAPS: $TapData,
                                        selectedCMND: selectedCMND,
                                        selectedPart: selectedPart,
                                        delaySlider: $delaySlider,
                                        durationSlider: $durationSlider,
                                        selectedOption: $selectedOption,
                                        selectedEntryIndices: $selectedEntryIndices,
                                        tapFunctionalityJustAppended: $tapFunctionalityJustAppended,
                                        pendingUnifiedValue: $unifiedValue
                                    )
                                    .id(controlSpaceUUID)
                                }
                                
                            }
                            
                            Spacer()
                            
                        }
                        .onPreferenceChange(GridHeightKey.self) { newHeight in
                            gridContentHeight = newHeight * 1.2
                        }
                        .clipped()
                    }
                    
                    .navigationBarHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                    .preferredColorScheme(selectedAppearance.colorScheme) // <- Updates dark/light mode
                    .overlay(
                        Group {
                            if showLoading {
                                ZStack {
                                    let accent: Color = {
                                        let user = Auth.auth().currentUser
                                        if let user, !user.isAnonymous, model.creator != ""{
                                            
                                            if let color = sharedData.imageAccentColors[model.name] {
                                                return color
                                            }
                                            if isPreviewingModel,
                                               let color = sharedData.publishedAccentColors[model.name] {
                                                return color
                                            }
                                        
                                        }
                                        if model.creator == ""{
                                            
                                            if let color = sharedData.imageAccentColors[model.name] {
                                                return color
                                            }
                                        }
                                        if isPreviewingModel,
                                           let color = sharedData.publishedAccentColors[model.name] {
                                            return color
                                        }
                                        return selectedAccent.color
                                    }()
                                    VStack(spacing: 12) {
                                        if selectedDisplayMethod == .sphere {
                                            RotatingSphereView(accent: accent)
                                                .frame(
                                                    width: UIScreen.main.bounds.width * 0.8,
                                                    height: UIScreen.main.bounds.width * 0.8
                                                )
                                        } else {

                                        }
                                        
                                    }
                                    .padding(24)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(radius: 10)
                                }
                            }
                        }
                    )
                    

                    if modelIsEmpty {
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            VStack(spacing: 12) {
                                
                                Text("add_tap_to_model_first".localized())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white)
                                    .padding(.top, 6)
                                
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        
                                        modelIsEmpty = false
                                    }) {
                                        Text("ok".localized())
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 30)
                                            .cornerRadius(8)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .padding(24)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 10)
                        }
                    }
                    
                    
                }



                .ignoresSafeArea(.keyboard, edges: .bottom) // keep FAB above the keyboard
                .zIndex(2) // above other overlays
                .fullScreenCover(item: $showDetails) { selected in
                    ModelCard(
                        isPreviewingModel: isPreviewingModel,
                        nameWidth: nameWidth,
                        isFavouriteModel: $isFavouriteModel2,
                        model: selected
                    )
                    .environmentObject(sharedData)
                }
                .sheet(item: $showDetailInSheet) { selected in
                    ModelCard(
                        isPreviewingModel: isPreviewingModel,
                        nameWidth: nameWidth,
                        isFavouriteModel: $isFavouriteModel2,
                        model: selected
                    )
                    .environmentObject(sharedData)
                }

                
                .onChange(of: isFavouriteModel) { newValue in
                    if newValue {
                        pillFillProgress = 1.0
                    }
                }
                
                .onChange(of: isFavouriteModel2) { newValue in
                    isFavouriteModel = newValue
                    pillFillProgress = newValue ? 1.0 : 0.0
                }
                .onChange(of: selectedEntryIndices) { listEntries in
                    if listEntries.isEmpty {
                        selectedConnectionIds.removeAll()
                    }
                }
                
                .overlay(alignment: .bottomTrailing) {
                    let accent: Color = {
                        let user = Auth.auth().currentUser
                        if let user, !user.isAnonymous, model.creator != "mode123456789"{
                            
                            if let color = sharedData.imageAccentColors[model.name] {
                                return color
                            }
                            if isPreviewingModel,
                               let color = sharedData.publishedAccentColors[model.name] {
                                return color
                            }
                        
                        }
                        if model.creator == "mode123456789"{
                            
                            if let color = sharedData.imageAccentColors[model.name] {
                                return color
                            }
                        }
                        if isPreviewingModel,
                           let color = sharedData.publishedAccentColors[model.name] {
                            return color
                        }
                        return selectedAccent.color
                    }()

                    let symbolName: String = {
                        if #available(iOS 17.0, *) { return "button.angledbottom.horizontal.left.fill" }
                        else { return "rectangle.stack.fill" }
                    }()

                    // Use a plain view as the “button”
                    ZStack {
                        Image(systemName: symbolName)
                            .font(.title)
                            .foregroundStyle(accent.opacity(0.15))

                        GeometryReader { geo in
                            Rectangle()
                                .fill(accent)
                                .frame(height: geo.size.height * setupSwitchHoldProgress)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .mask {
                                    Image(systemName: symbolName)
                                        .font(.title)
                                }
                        }
                    }
                    .frame(
                        width: UIScreen.main.bounds.width * 0.08,
                        height: UIScreen.main.bounds.width * 0.08
                    )
                    .contentShape(Rectangle()) // makes the whole frame tappable
                    .layoutPriority(2)
                    .padding(.trailing, 16)
                    .zIndex(999)
                    .opacity(inBuildIsPreviewingModel || selectedCMND == 0 ? 0.0 : 1.0)
                    .allowsHitTesting(!inBuildIsPreviewingModel || selectedCMND != 0)

                    // Long press: start animating immediately, but only “counts” after 0.5s
                    // Finger down/up tracking (starts immediately, always ends)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Optional: cancel if they drift too far
                                let dist = hypot(value.translation.width, value.translation.height)
                                if dist > 30 {
                                    cancelSetupSwitchHold() // animate down + cancel tasks
                                    return
                                }

                                if !isHoldingSetupSwitch {
                                    suppressNextSetupSwitchTap = false
                                    didLongPressSetupSwitch = false
                                    beginSetupSwitchHold()
                                }

                            }
                            .onEnded { _ in
                                // Always fires, even for quick taps
                                cancelSetupSwitchHold() // animate down + cancel tasks (no open here)
                            }
                    )


                    // Tap: only fires if long-press did NOT happen
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            guard !suppressNextSetupSwitchTap else {
                                suppressNextSetupSwitchTap = false
                                didLongPressSetupSwitch = false
                                return
                            }

                            selectionHaptic.prepare()
                            selectionHaptic.selectionChanged()

                            if let i = controlOrder.firstIndex(of: controlsForDelay) {
                                controlsForDelay = controlOrder[(i + 1) % controlOrder.count]
                            } else {
                                controlsForDelay = controlOrder.first!
                            }
                        }
                    )

                }
                .onChange(of: showInControlSpaceServoOptions) { newValue in
                    if newValue == true {
                        cancelSetupSwitchHold()
                    }
                }



                .overlay(
                    OnboardingPopup(isPresented: $showOnBoardingPopup, isPreviewingModel: isPreviewingModel)
                        .frame(maxWidth: 320) // Optional max width for better layout
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(1)
                    
                )
                
                .safeAreaInset(edge: .top) {
                    let accent: Color = {
                        let user = Auth.auth().currentUser
                        if let user, !user.isAnonymous, model.creator != "mode123456789"{
                            
                            if let color = sharedData.imageAccentColors[model.name] {
                                return color
                            }
                            if isPreviewingModel,
                               let color = sharedData.publishedAccentColors[model.name] {
                                return color
                            }
                        
                        }
                        if model.creator == "mode123456789"{
                            
                            if let color = sharedData.imageAccentColors[model.name] {
                                return color
                            }
                        }
                        if isPreviewingModel,
                           let color = sharedData.publishedAccentColors[model.name] {
                            return color
                        }
                        return selectedAccent.color
                    }()
                    let sideButton: CGFloat = 44            // your button tap target size
                    let horizontalPadding: CGFloat = 16 * 2 // .padding(.horizontal)
                    let gapBetween: CGFloat = 12 * 2        // spacing you effectively have
                    
                    let maxCenterWidth =
                    geometry.size.width - (sideButton * 2) - horizontalPadding - gapBetween
                    
                    if !isInSheet {
                        
                        HStack {
                            Button {
                                // back + save logic
                                if !inBuildIsPreviewingModel,
                                   Auth.auth().currentUser?.isAnonymous == false,
                                   connectedToNetwork {
                                    // allowed
                                

                                    var TapDataForSave = TapData
                                    TapDataForSave.removeValue(forKey: 0)
                                    
                                    let hasAnyTapEntries = TapDataForSave.values.contains { typeDict in
                                        typeDict.values.contains { taps in
                                            taps.contains { $0.value != 0.0 }
                                        }
                                    }
                                    
                                    if hasAnyTapEntries && (TapData != initialTapData) {
                                        personalModelsFunctions.createCustomModelPlaceholder(for: userEmail, named: model.name) { result in
                                            switch result {
                                            case .success:
                                                personalModelsFunctions.appendDataForCustomModel(
                                                    for: userEmail,
                                                    named: model.name,
                                                    taps: TapDataForSave,
                                                    commandNames: commandNames
                                                ) { _ in }
                                            case .failure(let error):
                                                print("❌ Rename failed: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                } else {

                                }
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(accent)
                            }
                            
                            Spacer()
                            
                            HStack {
                                ZStack(alignment: .top) {
                                    VStack(spacing: 6) {
                                        
                                        // NAME
                                        Text(isPreviewingModel || !connectedToNetwork ? model.name : displayName)
                                            .font(.title2.weight(.bold))
                                            .lineLimit(1)
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear
                                                        .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                                                }
                                            )
                                        
                                        let pillWidth = nameWidth   // already clamped to maxCenterWidth
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(accent.opacity(0.15))
                                            
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(accent)
                                                .frame(width: pillWidth * pillFillProgress)
                                                .clipped()
                                                .animation(
                                                    (!isPressingPill && isFavouriteModel && pillFillProgress == 1.0)
                                                        ? nil
                                                        : .linear(duration: 1.0),
                                                    value: pillFillProgress
                                                )

                                        }
                                        .frame(width: pillWidth, height: 14)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    // ✅ make BOTH name + pill tappable/holdable
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    
 
                                    .onTapGesture {
                                        showDetails = model
                                    }
                                    
                                    // hold = add/remove fav with 0.5s delay + 1s fill
                                    .onLongPressGesture(
                                        minimumDuration: 1.5,
                                        maximumDistance: 12,
                                        pressing: { pressing in
                                            guard canLike || canUnlike else { return }
                                            isPressingPill = pressing
                                            if pressing {
                                                fillWorkItem?.cancel()
                                                
                                                let target: CGFloat = isFavouriteModel ? 0.0 : 1.0
                                                let work = DispatchWorkItem {
                                                    guard (canLike || canUnlike) else { return }
                                                    pillFillProgress = target
                                                }
                                                
                                                fillWorkItem = work
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                                            } else {
                                                fillWorkItem?.cancel()
                                                if Auth.auth().currentUser?.isAnonymous == false {
                                                    pillFillProgress = isFavouriteModel ? 1.0 : 0.0
                                                }
                                            }
                                        },
                                        perform: {
                                            
                                            if let user = Auth.auth().currentUser, !user.isAnonymous {
                                                
                                                
                                                
                                                if isFavouriteModel {
                                                    pillFillProgress = 0.0
                                                    // icon
                                                    showBrokenHeart = true
                                                    
                                                    // ✅ favourite state
                                                    isFavouriteModel = false
                                                    
                                                    // ✅ cancel any in-flight hold animation
                                                    fillWorkItem?.cancel()
                                                    
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                        showFavToast = true
                                                    }
                                                    
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                        withAnimation(.easeOut(duration: 0.2)) {
                                                            showFavToast = false
                                                        }
                                                    }
                                                    
                                                    
                                                    handleLikeTap()
                                                } else {
                                                    pillFillProgress = 1.0
                                                    // icon
                                                    showBrokenHeart = false
                                                    
                                                    // ✅ favourite state
                                                    isFavouriteModel = true
                                                    
                                                    // ✅ cancel any in-flight hold animation
                                                    fillWorkItem?.cancel()
                                                    
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                        showFavToast = true
                                                    }
                                                    
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                        withAnimation(.easeOut(duration: 0.2)) {
                                                            showFavToast = false
                                                        }
                                                    }
                                                    
                                                    
                                                    handleLikeTap()
                                                }
                                                
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            } else {
                                                pillFillProgress = 0.0
                                                fillWorkItem?.cancel()
                 
                                            }
                                        }
                                    )
                                    
                                    .frame(maxWidth: maxCenterWidth)
                                    

                                }
                            }
                            .onPreferenceChange(WidthPreferenceKey.self) { value in
                                nameWidth = min(value, maxCenterWidth)
                            }
                            
                            Spacer()
                            
                            Button {
                                // play logic
                                if !inBuildIsPreviewingModel,
                                   Auth.auth().currentUser?.isAnonymous == false,
                                   connectedToNetwork {
                                    
                                    print("trying to save")
                                    
                                    var TapDataForSave = TapData
                                    TapDataForSave.removeValue(forKey: 0)
                                    
                                    let hasAnyTapEntries = TapDataForSave.values.contains { typeDict in
                                        typeDict.values.contains { taps in
                                            taps.contains { $0.value != 0.0 }
                                        }
                                    }
                                    
                                    if hasAnyTapEntries && (TapData != initialTapData) {
                                        personalModelsFunctions.createCustomModelPlaceholder(for: userEmail, named: model.name) { result in
                                            switch result {
                                            case .success:
                                                personalModelsFunctions.appendDataForCustomModel(
                                                    for: userEmail,
                                                    named: model.name,
                                                    taps: TapDataForSave,
                                                    commandNames: commandNames
                                                ) { _ in }
                                            case .failure(let error):
                                                print("❌ Rename failed: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                showPlayView = true
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        .background(Color(.systemBackground))   // neutral backing, no accent tint
                        .overlay(Divider(), alignment: .bottom)
                    } else{
                        HStack {
                            HStack {
                                ZStack(alignment: .top) {
                                    VStack(spacing: 6) {
                                        
                                        // NAME
                                        Text(isPreviewingModel || !connectedToNetwork ? model.name : displayName)
                                            .font(.title2.weight(.bold))
                                            .lineLimit(1)
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear
                                                        .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                                                }
                                            )
                                        
                                        let pillWidth = nameWidth   // already clamped to maxCenterWidth
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(accent.opacity(0.15))
                                            
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(accent)
                                                .frame(width: pillWidth * pillFillProgress)
                                                .clipped()
                                                .animation(
                                                    (!isPressingPill && isFavouriteModel && pillFillProgress == 1.0)
                                                        ? nil
                                                        : .linear(duration: 1.0),
                                                    value: pillFillProgress
                                                )
                                        }
                                        .frame(width: pillWidth, height: 14)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    // ✅ make BOTH name + pill tappable/holdable
                                    .contentShape(     RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    
                                    // tap = details
                                    .onTapGesture {
                                        showDetailInSheet = model
                                    }
                                    
                                    // hold = add/remove fav with 0.5s delay + 1s fill
                                    .onLongPressGesture(
                                        minimumDuration: 1.5,
                                        maximumDistance: 12,
                                        pressing: { pressing in
                                            guard canLike || canUnlike else { return }
                                            print("started hold")
                                            isPressingPill = pressing
                                            if pressing {
                                                fillWorkItem?.cancel()
                                                
                                                let target: CGFloat = isFavouriteModel ? 0.0 : 1.0
                                                let work = DispatchWorkItem {
                                                    guard (canLike || canUnlike) else { return }
                                                    pillFillProgress = target
                                                }
                                                
                                                fillWorkItem = work
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                                            } else {
                                                fillWorkItem?.cancel()
                                                if Auth.auth().currentUser?.isAnonymous == false {
                                                    pillFillProgress = isFavouriteModel ? 1.0 : 0.0
                                                }
                                            }
                                        },
                                        perform: {
                                            if let user = Auth.auth().currentUser, !user.isAnonymous {
                                                if isFavouriteModel {
                                                    pillFillProgress = 0.0
                                                    // icon
                                                    showBrokenHeart = true
                                                    
                                                    // ✅ favourite state
                                                    isFavouriteModel = false
                                                    
                                                    // ✅ cancel any in-flight hold animation
                                                    fillWorkItem?.cancel()
                                                    
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                        showFavToast = true
                                                    }
                                                    
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                        withAnimation(.easeOut(duration: 0.2)) {
                                                            showFavToast = false
                                                        }
                                                    }
                                                    
                                                    handleLikeTap()
                                                } else {
                                                    pillFillProgress = 1.0
                                                    // icon
                                                    showBrokenHeart = false
                                                    
                                                    // ✅ favourite state
                                                    isFavouriteModel = true
                                                    
                                                    // ✅ cancel any in-flight hold animation
                                                    fillWorkItem?.cancel()
                                                    
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                        showFavToast = true
                                                    }
                                                    
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                        withAnimation(.easeOut(duration: 0.2)) {
                                                            showFavToast = false
                                                        }
                                                    }
                                                    
                                                    handleLikeTap()
                                                }
                                                
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            } else {
                                                pillFillProgress = 0.0
                                                fillWorkItem?.cancel()
                 
                                            }
                                        }
                                    )
                                    

                                }
                            }
                            .onPreferenceChange(WidthPreferenceKey.self) { value in
                                nameWidth = value
                            }
                            
                            Spacer()
                            
                            Button {
                                // play logic
                                if !inBuildIsPreviewingModel,
                                   Auth.auth().currentUser?.isAnonymous == false,
                                   connectedToNetwork {
                                    
                                    var TapDataForSave = TapData
                                    TapDataForSave.removeValue(forKey: 0)
                                    
                                    let hasAnyTapEntries = TapDataForSave.values.contains { typeDict in
                                        typeDict.values.contains { taps in
                                            taps.contains { $0.value != 0.0 }
                                        }
                                    }
                                    
                                    if hasAnyTapEntries && (TapData != initialTapData) {
                                        personalModelsFunctions.createCustomModelPlaceholder(for: userEmail, named: model.name) { result in
                                            switch result {
                                            case .success:
                                                personalModelsFunctions.appendDataForCustomModel(
                                                    for: userEmail,
                                                    named: model.name,
                                                    taps: TapDataForSave,
                                                    commandNames: commandNames
                                                ) { _ in }
                                            case .failure(let error):
                                                print("❌ Rename failed: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                showPlayView = true
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 44, height: 44)              // ✅ bigger tap target
                                    .contentShape(Rectangle())                 // ✅ whole frame tappable
                            }
                            
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)            // 👈 move down (adjust value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                    }
                }
                .onDisappear { waveInactivityTimer?.invalidate() }
                .animation(.easeInOut(duration: 0.3), value: showOnBoardingPopup)
                .sheet(isPresented: $showPlayView, onDismiss: {
                    

                    
                }) {
                    PlayView(UsersTaps: $UsersTaps, model: model, TapData: TapData, isPreviewingModel: isPreviewingModel, accent: accent)
                        .ignoresSafeArea(.all)          // ← THIS is the key
                        .presentationDetents([.large])
                        .presentationDragIndicator(.hidden) // optional
                        .sheetCornerRadius(0)
                }
                
                
                .overlay {
                    Group {
                        let accent: Color = {
                            let user = Auth.auth().currentUser
                            if let user, !user.isAnonymous, model.creator != "mode123456789"{
                                
                                if let color = sharedData.imageAccentColors[model.name] {
                                    return color
                                }
                                if isPreviewingModel,
                                   let color = sharedData.publishedAccentColors[model.name] {
                                    return color
                                }
                            
                            }
                            if model.creator == "mode123456789"{
                                
                                if let color = sharedData.imageAccentColors[model.name] {
                                    return color
                                }
                            }
                            if isPreviewingModel,
                               let color = sharedData.publishedAccentColors[model.name] {
                                return color
                            }
                            return selectedAccent.color
                        }()
                        if showAdSheet {
                            Color.black.opacity(0.4) // dim background
                                .ignoresSafeArea()
                                .onTapGesture { showAdSheet = false }
                            
                            CustomAlert(
                                title: "enjoyed_the_play".localized(),
                                message: "experience_more_with_Vibro".localized(),
                                buyAction: {
                                    if let url = URL(string: "https://bi-mach.com/shop/p/vib") {
                                        UIApplication.shared.open(url)
                                    }
                                    showAdSheet = false
                                },
                                cancelAction: { showAdSheet = false }
                            )
                        }
                        if showAdSheet2 {
                            Color.black.opacity(0.4) // dim background
                                .ignoresSafeArea()
                                .onTapGesture { showAdSheet = false }
                            
                            CustomAlert(
                                title: "connect_vib_to_use_tacticle_hf".localized(),
                                message: "experience_more_with_Vibro".localized(),
                                buyAction: {
                                    if let url = URL(string: "https://bi-mach.com/shop/p/vib") {
                                        UIApplication.shared.open(url)
                                    }
                                    showAdSheet2 = false
                                },
                                cancelAction: { showAdSheet2 = false }
                            )
                        }
                        if showInControlSpacePowerOptions || showInControlSpaceServoOptions {
                            let accent: Color = {
                                let user = Auth.auth().currentUser
                                if let user, !user.isAnonymous, model.creator != "mode123456789"{
                                    
                                    if let color = sharedData.imageAccentColors[model.name] {
                                        return color
                                    }
                                    if isPreviewingModel,
                                       let color = sharedData.publishedAccentColors[model.name] {
                                        return color
                                    }
                                
                                }
                                if model.creator == "mode123456789"{
                                    
                                    if let color = sharedData.imageAccentColors[model.name] {
                                        return color
                                    }
                                }
                                if isPreviewingModel,
                                   let color = sharedData.publishedAccentColors[model.name] {
                                    return color
                                }
                                return selectedAccent.color
                            }()

                            
                        }
                    }
                }
                .onChange(of: selectedEntryIndices) { _ in
                    userLayoutOverride = nil   // or keep it if you want “sticky” behavior
                }
                .onChange(of: selectedCMND) { _ in
                    userLayoutOverride = nil
                }
                .onChange(of: selectedPart) { _ in
                    userLayoutOverride = nil
                }
                .onAppear {

                    // MARK: - Loader helpers (reset on every load)
                    func resetLoadingTimer() {
                        loadingWorkItem?.cancel()
                        showLoading = false

                        let wi = DispatchWorkItem {
                            DispatchQueue.main.async {
                                if !model.justCreated { showLoading = true }
                            }
                        }
                        loadingWorkItem = wi
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: wi)
                    }
                    
                    ensurePublishedAccentIfPreviewing()

                    func stopLoadingTimer() {
                        loadingWorkItem?.cancel()
                        loadingWorkItem = nil
                        showLoading = false
                    }

                    // MARK: - Tap helpers (keeps your selection logic consistent)
                    func ensureDummy999IfNeeded() {
                        if TapData[0]?[999] == nil {
                            let dummyTapEntry = TapEntry(key: 999, modelName: "999", entryType: "999", value: 0.0)
                            if TapData[0] == nil { TapData[0] = [:] }
                            TapData[0]![999] = [dummyTapEntry]
                        }
                    }

                    func removeDummy999IfExists() {
                        if TapData[0]?[999] != nil {
                            TapData[0]?.removeValue(forKey: 999)
                        }
                    }

                    func updateSelectionFromTapData() {
                        if let firstPrimary = TapData.keys.filter({ $0 > 0 }).sorted().first,
                           let inner = TapData[firstPrimary], !inner.isEmpty {

                            selectedCMND = firstPrimary
                            selectedPart = inner.keys.sorted().first ?? 0
                            selectedCMNDType = inner.keys.first ?? 0
                            showTAPSModificationLine = true
                        } else {
                            selectedCMND = 0
                            selectedPart = 0
                            selectedCMNDType = 0
                            showTAPSModificationLine = false
                        }
                    }

                    func applyTapDataAndRebuild() {
                        initialTapData = TapData
                        rebuildButtons()
                        updateSelectionFromTapData()
                    }

                    // MARK: - Your original setup
                    if userLayoutOverride == nil {
                        userLayoutOverride = selectedOption
                    }

                    justJoined = true

                    if let name = sharedData.ALLUSERNAMES[model.creator]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        creatorUserName = name
                    }

                    print("model.creator: \(model.creator)")

                    if isFavouriteModel {
                        pillFillProgress = 1.0
                    }
                    print("GUUGGA")
                    if isInSheet {
                        isFavouriteModel = sharedData.publishedFavModels.keys.contains(model.name)
                    } else {
                        isFavouriteModel = sharedData.publishedFavModels.values.contains { $0.id == model.id }
                    }
                    isFavouriteModel2 = isFavouriteModel

                    // Start loader for the first load on appear
                    resetLoadingTimer()

                    print("GUUGG2A")
                    // MARK: - Auth branching
                    if let user = Auth.auth().currentUser, !user.isAnonymous {
                        
                        inBuildIsPreviewingModel = isPreviewingModel
                        userEmail = user.email ?? ""
                        userID = user.uid
                        
                        let favouriteIDs = Set(sharedData.publishedFavModels.values.map(\.id))
                        if favouriteIDs.contains(model.id) {
                            inBuildIsPreviewingModel = true
                            isFavouriteModel2 = true
                            pillFillProgress = isFavouriteModel ? 1.0 : 0.0
                        }
  
                        if !inBuildIsPreviewingModel && !model.justCreated {
                            resetLoadingTimer()
                            personalModelsFunctions.fetchConfigForMyModel(userEmail: userEmail, modelName: model.name) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success(let payload):
                                        TapData = payload.taps
                                        
                                        commandNames = payload.names
                                        ensureDummy999IfNeeded()
                                        
                                        if !tapDataJSON.isEmpty {
                                            let decoder = JSONDecoder()

                                            do {
                                                let decoded = try decoder.decode(
                                                    [String: [Int: [Int: [TapEntry]]]].self,
                                                    from: tapDataJSON
                                                )

                                                if let modelData = decoded[model.name], !modelData.isEmpty {
                                                    TapData = modelData
                                                } else {
                                                    print("AAA CLASS WWE")
                                                }
                                            } catch {
                                                print("AAA CLASS WWE")
                                            }

                                            ensureDummy999IfNeeded()
                                        }                                        
                                        applyTapDataAndRebuild()
                                        
                                        stopLoadingTimer()
                                        
                                    case .failure(let error):
                                        ensureDummy999IfNeeded()
                                        addButton()
                                        applyTapDataAndRebuild()
                                        
                                        stopLoadingTimer()
                                        print("❌ Fetch failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                            
                        } else if inBuildIsPreviewingModel {
                            // MARK: - Published model (preview path) -> fetch published config
                            
                            resetLoadingTimer()
                            
                            publishFunctionality.fetchConfigForPublishedModel(modelName: model.name) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success(let payload):
                                        TapData = payload.taps
                                        removeDummy999IfExists()
                                        
                                        commandNames = payload.names
                                        applyTapDataAndRebuild()
                                        
                                        stopLoadingTimer()
                                        
                                    case .failure(let error):
                                        stopLoadingTimer()
                                        dismiss()
                                        print("❌ Fetch failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                        } else if model.justCreated {
                            

                            
                            if TapData[0]?[999] == nil {
                                ensureDummy999IfNeeded()
                                addButton()
                                applyTapDataAndRebuild()
                            }
                            
                            stopLoadingTimer()
                            return
                    
                        }

                    } else {
                        
                        inBuildIsPreviewingModel = isPreviewingModel
                        if isPreviewingModel {
                            resetLoadingTimer()
                            
                            publishFunctionality.fetchConfigForPublishedModel(modelName: model.name) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success(let payload):
                                        TapData = payload.taps
                                        removeDummy999IfExists()
                                        
                                        commandNames = payload.names
                                        applyTapDataAndRebuild()
                                        
                                        stopLoadingTimer()
                                        
                                    case .failure(let error):
                                        stopLoadingTimer()
                                        dismiss()
                                        print("❌ Fetch failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                        } else if model.creator == "mode123456789", !tapDataJSON.isEmpty {
                            
                            resetLoadingTimer()
                            
                            let decoder = JSONDecoder()
                            if let decoded = try? decoder.decode([String: [Int: [Int: [TapEntry]]]].self, from: tapDataJSON) {
                                if let modelData = decoded[model.name] {
                                    TapData = modelData
                                } else {
                                    TapData = decoded.values.first ?? [:]
                                }
                            }
                            
                            ensureDummy999IfNeeded()
                            applyTapDataAndRebuild()
                            
                            stopLoadingTimer()
                        
                        } else {
                            // Otherwise default dummy setup
                            ensureDummy999IfNeeded()
                            addButton()
                            applyTapDataAndRebuild()

                            stopLoadingTimer()
                        }
                    }
                }

                .onChange(of: showPlayView) { playView in
                    playbackIsPlayed = false
                    if !playView && !UsersTaps.isEmpty{
                        guard
                            let user = Auth.auth().currentUser,
                            let uid = user.uid as String?,
                            let email = user.email
                        else {
                            return
                        }
                        if !inBuildIsPreviewingModel {
                            tapsFunctions.SaveTAPS(for: email, selectedModel: model.name, SaveToFolder: "", UsersTaps: UsersTaps) { success in
                                if success {
                                    UsersTaps = [:]
                                    print("SUCCESS")
                                } else {
                                    print("Error")
                                }
                            }
                        } else {
                            tapsFunctions.SaveTAPSForFav(for: email, selectedModel: model.name, SaveToFolder: "", UsersTaps: UsersTaps) { success in
                                if success {
                                    UsersTaps = [:]
                                    print("SUCCESS")
                                } else {
                                    print("Error")
                                }
                            }
                        }
                    }
                }
                
                .onChange(of: renamingCommand) { newValue in
                    focusedKey = newValue
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .inactive || phase == .background {
                        saveIfNeeded()
                    }
                }
                
                .onChange(of: TapData) { newValue in

                    if !inBuildIsPreviewingModel,
                       !model.justCreated,
                       Auth.auth().currentUser != nil ,
                       Auth.auth().currentUser?.isAnonymous == false {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let wrapper = [model.name: newValue]
                        
                        if let encoded = try? encoder.encode(wrapper) {
                            tapDataJSON = encoded
                        }
                    } else if model.creator == "mode123456789" {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let wrapper = [model.name: newValue]
                        
                        if let encoded = try? encoder.encode(wrapper) {
                            tapDataJSON = encoded
                        }
                        
                    }
                }
                .onChange(of: showDeleteBlockConfirmation) { newVlaue in
                    
                    if !newVlaue {
                        rebuildButtons()
                    }
                }
                .onDisappear {

                    playbackIsPlayed = false
                    
                    let hasAnyTapEntries = TapData.values.contains { typeDict in
                        typeDict.values.contains { taps in
                            taps.contains { $0.value != 0.0 }
                        }
                    }

                    if !isPreviewingModel && model.justCreated && !hasAnyTapEntries {
                        DispatchQueue.main.async {

                            sharedData.personalModelsData.remove(model) // or by id/name
                        }
                    }
                    model.justCreated = false

                    
                }
                .onChange(of: controlsForDelay) { new in
                    waveCenters.removeAll()
                    waveValues.removeAll()
                    print("controlsForDelay changed to:", new)
                }
                .alert("warning".localized(),
                       isPresented: Binding(
                        get: { showStructuralAlert || showTapsAreEmpty },
                        set: { if !$0 { showStructuralAlert = false; showTapsAreEmpty = false } }
                       )
                ) {
                    Button("cancel".localized(), role: .cancel) {
                        showStructuralAlert = false
                        showTapsAreEmpty = false
                    }
                } message: {
                    Text(showStructuralAlert
                         ? "structure_incorrect_alert".localized()
                         : "model_must_contain_commands".localized())
                }
                
                .alert("cooldown".localized(), isPresented: $showLikeCooldownAlert) {
                    Button("ok".localized(), role: .cancel) { }
                } message: {
                    Text(likeCooldownMessage)
                }
                .onChange(of: controlsForDelay) { _ in
                    controlLiveKey = nil
                    controlLiveType = nil
                    controlIsEditing = false
                }
                .onChange(of: selectedEntryIndices) { newSel in
                    if !newSel.isEmpty {
                        controlLiveKey = nil
                        controlLiveType = nil
                        controlIsEditing = false
                    }
                }


                
            }
        }
        
        .overlay {
            if showFavToast {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: showBrokenHeart ? "minus" : "plus")
                            .font(.system(size: 44, weight: .semibold))
                    )
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(10_000) // ✅ make sure nothing covers it
            }
        }
    }
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchorID, anchor: .trailing)
            }
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
    private func ensurePublishedAccentIfPreviewing() {
        guard isPreviewingModel else { return }
        // Already have it? done.
        if sharedData.publishedAccentColors[model.name] != nil { return }

        let id = "PublishedModels/\(sharedData.appLanguage)/\(model.name)/ModelImage.jpg"

        // 1) Try disk cache first
        if let img = ImageDiskCache.shared.load(identifier: id) {
            setAccent(from: img)
            return
        }
        let ref = Storage.storage().reference()
            .child("PublishedModels")
            .child("\(sharedData.appLanguage)")
            .child(model.name)
            .child("ModelImage.jpg")

        ref.downloadURL { url, error in
            if let error = error as NSError? {
                // Ignore missing files; log others if you want
                if error.domain == StorageErrorDomain,
                   StorageErrorCode(rawValue: error.code) == .objectNotFound {
                    return
                } else {
                    print("Image lookup error for \(model.name):", error.localizedDescription)
                    return
                }
            }
            if let url = url {
                DispatchQueue.main.async {
                    print("FETCEHD")
                    sharedData.publishedModelImageURLs[model.name] = url
                }
            }
        }
    }
    private func beginSetupSwitchHold() {
        cancelSetupSwitchHoldTasksOnly()

        isHoldingSetupSwitch = true

        // Fill up over exactly 0.5s while finger is down
        startSetupSwitchHoldFill(duration: 0.1)

        // After 0.5s of continuous hold, open options (only once)
        setupSwitchOpenTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)

            guard isHoldingSetupSwitch else { return } // finger must still be down

            suppressNextSetupSwitchTap = true
            didLongPressSetupSwitch = true

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showInControlSpaceServoOptions = true

            cancelSetupSwitchHold()


        }
    }


    private func cancelSetupSwitchHold() {
        cancelSetupSwitchHoldTasksOnly()
        isHoldingSetupSwitch = false

        // Animate back down when finger lifts/cancels
        withAnimation(.easeOut(duration: 0.18)) {
            setupSwitchHoldProgress = 0
        }
    }

    private func cancelSetupSwitchHoldTasksOnly() {
        setupSwitchHoldTask?.cancel()
        setupSwitchHoldTask = nil
        setupSwitchOpenTask?.cancel()
        setupSwitchOpenTask = nil
    }

    private func startSetupSwitchHoldFill(duration: TimeInterval) {
        setupSwitchHoldProgress = 0

        let start = Date()
        setupSwitchHoldTask = Task { @MainActor in
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / duration
                setupSwitchHoldProgress = min(1, CGFloat(t))
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
            }
        }
    }


    func hasNetworkConnection(completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied &&
                (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.cellular))
            completion(connected)
            
            // Stop monitoring after we get the status
            monitor.cancel()
        }
        
        monitor.start(queue: queue)
    }
    func saveLastUsedEntry(for model: Model, listOfFavModels: [String]) {
        var currentDict: [String: [String]] = [:]
        
        // Decode existing data if available
        if let decoded = try? JSONDecoder().decode([String: [String]].self, from: lastUsedEntriesData) {
            currentDict = decoded
        }
        
        // Update or insert the value for this model.name
        currentDict[model.name] = listOfFavModels
        
        // Encode and save back into AppStorage
        do {
            let data = try JSONEncoder().encode(currentDict)
            lastUsedEntriesData = data
        } catch {
            print("❌ Failed to save last used entries:", error)
        }
    }
    
    private func nextKey(in arr: [TapEntry]) -> Int {
        (arr.map { $0.key }.max() ?? 0) + 1
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
    
    func getLastUsedEntries() -> [String: [String]] {
        do {
            return try JSONDecoder().decode([String: [String]].self, from: lastUsedEntriesData)
        } catch {
            print("❌ Failed to decode last used entries:", error)
            return [:]
        }
    }
    
    func clearAllLastUsedEntries() {
        // make an empty payload, even if encoding somehow fails
        let emptyData = (try? JSONEncoder().encode([String: [String]]())) ?? Data()
        DispatchQueue.main.async {
            lastUsedEntriesData = emptyData
        }
    }
    
    @MainActor
    private func performFavouriteToggle() {
        if !isFavouriteModel2 {
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
                    publishFunctionality.increaseModelRate(publishName: model.name) { result in
                        switch result {
                        case .success:
                            print("")
                        case .failure(let error):
                            print("")
                        }
                    }
                    isFavouriteModel2 = true
 
                    
                    sharedData.publishedFavModels[model.name] = model
                    sharedData.favouriteModels.insert(model)


                    if model.creator != userID {
                        publishFunctionality.notifyAboutLikingModel(
                            recepient_uid: model.creator,
                            author_uid: userID,
                            model_name: model.name,
                            author_name: creatorUserName
                        ) { result in
                            switch result {
                            case .success():
                                print("")
                            case .failure(let error):
                                print("")
                            }
                        }
                    }

                case .failure(let error):
                    isFavouriteModel2 = false

                    
                }
            }

        } else {
            personalModelsFunctions.deleteFavouriteModel(named: model.name) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        publishFunctionality.decreaseModelRate(publishName: model.name) { _ in }

                        // 1️⃣ Remove all cached images for this model (personal, favourite, published)
                        removeCachedImagesForModel(model.name)

                        // 2️⃣ Clear any in-memory or URL mappings
                        sharedData.favouriteModelImageURLs[model.name] = nil
                        // 3️⃣ Remove favourite model references
                        sharedData.publishedFavModels.removeValue(forKey: model.name)
                        sharedData.favouriteModels.remove(model)

                        
                        isFavouriteModel2 = false

                    case .failure(let error):
                        isFavouriteModel2 = true
                    }
                }
            }
        }
    }


    private func handleLikeTap() {
        
        let now = Date().timeIntervalSince1970

        
        if likingCooldownUntil > now {
            showLikeCooldown(remaining: likingCooldownUntil - now)
            return
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

    private func removeCachedImagesForModel(_ modelName: String) {
        guard let email = Auth.auth().currentUser?.email else { return }

        // These identifiers mirror how you save/load images elsewhere
        let personalID  = "\(email)/Models/\(modelName)/ModelImage.jpg"
        let favouriteID = "\(email)/FavouriteModels/\(modelName)/ModelImage.jpg"

        ImageDiskCache.shared.remove(identifier: personalID)
        ImageDiskCache.shared.remove(identifier: favouriteID)
    }
    private func removeDisplayName(for model: Model) {
        var dict = modelAliasMap
        dict.removeValue(forKey: model.name.canonName)
        modelAliasMap = dict
    }
    private func showLikeCooldown(remaining: TimeInterval, justStarted: Bool = false) {
        let minutesLeft = Int(ceil(max(remaining, 0) / 60))
        let leftText = minutesLeft == 1 ? "1_minute".localized() : "\(minutesLeft) \("minutes".localized())"
        likeCooldownMessage = "\("cooldown_30_minutes".localized()) \(leftText) \("left".localized())."
        showLikeCooldownAlert = true
    }
    
    private func saveIfNeeded() {
        guard
            !inBuildIsPreviewingModel,
            let currentUser = Auth.auth().currentUser,
            !currentUser.isAnonymous,
            !dataHasBeenSaved
        else { return }
        
        var tapDataForSave = TapData
        tapDataForSave.removeValue(forKey: 0)
        
        let hasAnyTapEntries = tapDataForSave.values.contains { typeDict in
            typeDict.values.contains { taps in
                taps.contains { $0.value != 0.0 }
            }
        }
        
        guard hasAnyTapEntries, TapData != initialTapData else { return }
        
        // Ask iOS for a little extra time if we’re backgrounding
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "SaveTapData") {
            // Expiration handler: we’re out of time. End the task.
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        func finish() {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            // prevent duplicate attempts
            dataHasBeenSaved = true
        }
        
        personalModelsFunctions.createCustomModelPlaceholder(for: userEmail, named: model.name) { result in
            switch result {
            case .success:
                personalModelsFunctions.appendDataForCustomModel(
                    for: userEmail,
                    named: model.name,
                    taps: tapDataForSave,
                    commandNames: commandNames
                ) { result in
                    switch result {
                    case .success:
                        print("✅ Saved taps")
                    case .failure(let error):
                        print("❌ Append failed: \(error.localizedDescription)")
                    }
                    finish()
                }
                
            case .failure(let error):
                print("❌ Placeholder failed: \(error.localizedDescription)")
                finish()
            }
        }
    }
    
    private func startPlayFlow() {
        playViewShouldOpen = true
        var TapDataForSave = TapData
        TapDataForSave.removeValue(forKey: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let hasAnyStructureWrong = TapDataForSave.values.contains { typeDict in
                typeDict.values.contains { taps in
                    hasConsecutives(tapsToModify: taps)
                }
            }
            let hasAnyTapEntries = TapData.values.contains { typeDict in
                typeDict.values.contains { taps in
                    taps.contains { $0.value != 0.0 }
                }
            }
            if hasAnyTapEntries {
                if !hasAnyStructureWrong {
                    showPlayView = true
                    playViewShouldOpen = false
                } else {
                    showStructuralAlert = true
                    playViewShouldOpen = false
                }
            } else {
                playViewShouldOpen = false
                showTapsAreEmpty = true
            }
        }
    }
    
    func addButton() -> Int? {
        // Only consider command keys 1...9 (ignore 0 which is the "+" button)
        let uniqueCMNDs = Set(TapData.keys.filter { $0 > 0 })

        guard uniqueCMNDs.count < 9 else { return nil }

        let allCMNDs = Set(1...9)
        let missingCMNDs = allCMNDs.subtracting(uniqueCMNDs)
        let newCMND = missingCMNDs.min() ?? 0
        guard newCMND != 0 else { return nil }

        var newTaps: [Int: [TapEntry]] = [:]
        if CMNDType == 2 {
            let tap1 = TapEntry(key: 0, modelName: sharedData.originalModelName, entryType: "none", value: 0)
            let tap2 = TapEntry(key: 0, modelName: sharedData.originalModelName, entryType: "none", value: 0)
            newTaps[1] = [tap1]
            newTaps[2] = [tap2]
        } else {
            let tap = TapEntry(key: 0, modelName: sharedData.originalModelName, entryType: "none", value: 0)
            newTaps[0] = [tap]
        }

        TapData[newCMND] = newTaps
        showSetCMNDType = false
        rebuildButtons()   // refresh

        return newCMND
    }


    private func updatePosition(for key: Int) {
        print("Update position")
        guard let currentIndex = buttons.firstIndex(of: key) else { return }
        
        let columnCount = 3
        let columnWidth: CGFloat = UIScreen.main.bounds.width / CGFloat(columnCount) - 16
        let rowHeight: CGFloat = 50 + 16
        
        let colChange = Int(dragOffset.width / columnWidth)
        let rowChange = Int(dragOffset.height / rowHeight)
        let newIndex = currentIndex + colChange + rowChange * columnCount
        let clampedIndex = max(0, min(newIndex, buttons.count - 1))
        
        if currentIndex == clampedIndex {
            return
        }
        
        let targetKeyAtIndex = buttons[clampedIndex]
        
        // 🚫 Don’t allow dropping onto the "+" button (999)
        if targetKeyAtIndex == 0 {
            print("Ignoring drop on + button")
            return
        }
        
        // ✅ Copy only (keep original AND add to new position)
        if let draggedContent = TapData[key] {
            TapData[targetKeyAtIndex] = draggedContent
        }
        
        targetKey = targetKeyAtIndex
        selectedCMND = targetKeyAtIndex
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            targetKey = nil
        }
    }


    
    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            showLoadingIcon = true
           
            if !waveCenters.isEmpty {

                showLoadingIcon = false
            } else {
                showLoadingIcon = false
            }
        }
    }

    
    @ViewBuilder
    private func col<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center) // equal-width column
    }

    private enum HalfSide { case left, right }

    @ViewBuilder
    private func halfHighlight(
        side: HalfSide,
        width: CGFloat,
        height: CGFloat,
        color: Color,
        active: Bool
    ) -> some View {
        let opacity = active ? 0.6 : 0
        if #available(iOS 17.0, *) {
            let r = height / 2
            let radii = side == .left
                ? RectangleCornerRadii(topLeading: r, bottomLeading: r)
                : RectangleCornerRadii( bottomTrailing: r, topTrailing: r)

            UnevenRoundedRectangle(cornerRadii: radii)
                .fill(color)
                .frame(width: width, height: height)
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.12), value: active)
        } else {
            // Fallback for iOS < 17
            HalfCapsule(side: side)
                .fill(color)
                .frame(width: width, height: height)
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.12), value: active)
        }
    }
    // Helper


    private struct HalfCapsule: Shape {
        let side: HalfSide
        func path(in rect: CGRect) -> Path {
            let r = rect.height / 2
            let corners: UIRectCorner = (side == .left) ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight]
            let bez = UIBezierPath(roundedRect: rect,
                                   byRoundingCorners: corners,
                                   cornerRadii: CGSize(width: r, height: r))
            return Path(bez.cgPath)
        }
    }

    private func endHold() {
        holdingLeft = false
        holdingRight = false
        stopAdjusting()
    }

    func controlsSpace(
        TAPS: Binding<[Int: [Int: [TapEntry]]]>,
        selectedCMND: Int,
        selectedPart: Int,
        delaySlider: Binding<Double>,
        durationSlider: Binding<Double>,
        selectedOption: Binding<Int>,
        selectedEntryIndices: Binding<Set<Int>>,
        tapFunctionalityJustAppended: Binding<Bool>,
        pendingUnifiedValue: Binding<Double>
    ) -> some View {
        let tapEntriesForSelectedPart = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
        let lastEntryType: String? = tapEntriesForSelectedPart
            .filter { $0.groupId == 0 }
            .max(by: { $0.key < $1.key })?
            .entryType
        @inline(__always)
        func newestGroupZeroKey() -> Int? {
            let updated = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
            return updated.filter { $0.groupId == 0 }.max(by: { $0.key < $1.key })?.key
        }

        let (justAppendedVibration, justAppendedDelays, LimitReached) = checkTapEntries(
            TapEntries: tapEntriesForSelectedPart,
            selectedCMND: selectedCMND
        )

        var textForegroundStyle: Color {
            ColorScheme ? Color.white : Color.black
        }
        
        func ensureControlLiveEntry(lastEntryType: String?) {
            guard controlLiveKey == nil else { return }
            guard !LimitReached else { return }

            let next = nextTypeToShow(lastEntryType: lastEntryType, selectedOption: selectedOption.wrappedValue)
            let seed = 0.01

            if next == "delay" {
                addDelay(value: 0.01, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                tapFunctionalityJustAppended.wrappedValue = true
                controlLiveType = "delay"
            } else {
                addMotors(value: 0.1 /***/, type: next, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                tapFunctionalityJustAppended.wrappedValue = false
                controlLiveType = next
            }

            // Capture newest key (groupId == 0, max key)
            let updated = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
            controlLiveKey = updated.filter { $0.groupId == 0 }.max(by: { $0.key < $1.key })?.key

        }


        
        func nextTypeToShow(lastEntryType: String?, selectedOption: Int) -> String {

            // Helper: map selectedOption → motor type
            func motorType(from option: Int) -> String {
                switch option {
                case 1: return "m1"
                case 2: return "m2"
                case 3: return "m3"
                default: return "m2" // safe fallback
                }
            }

            switch lastEntryType {
            case "m1", "m2", "m3":
                // After any motor → go to delay
                return "delay"

            case "delay":
                // After delay → go to selected motor
                return motorType(from: selectedOption)

            default:
                // Initial / unknown state
                return motorFirst
                    ? motorType(from: selectedOption)
                    : "delay"
            }
        }

    
        @ViewBuilder
        func controlsRow(
            gutter: CGFloat,
            button: CGFloat,
            valueWidth: CGFloat,
            presentTypes: [String],
            lastEntryType: String?
        ) -> some View {
            HStack(spacing: gutter) {
                // 1) Icons cluster — hugs content
                IconsBlock(
                    presentTypes: presentTypes,
                    lastEntryType: lastEntryType,
                    selectedOption: selectedOption.wrappedValue,
                    iconView: iconView
                )
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)




                // 3) Controls — MUST absorb leftover width
                Group {
                    if controlsForDelay == "slider" {
                        Slider(value: functionValue, in: controlMin...controlMax, step: controlStep)

                            .tint(accent)
                            .frame(maxWidth: .infinity)  // ← flexible column
                            .opacity(controlsForDelay == "slider" ? 1 : 0) // ← fade in
                            .animation(.easeIn(duration: 0.5), value: controlsForDelay == "slider")
                            .onChange(of: functionValue.wrappedValue) { new in
                                // keep only your edge haptic for selection mode if you want:
                                guard !selectedEntryIndices.wrappedValue.isEmpty else { return }
                                
                                let tol = unionStep / 2
                                let atEdge = (new >= unionMax - tol) || (new <= unionMin + tol)
                                if atEdge && !hitVibrationMax {
                                    let gen = UIImpactFeedbackGenerator(style: .rigid)
                                    gen.prepare(); gen.impactOccurred()
                                    hitVibrationMax = true
                                } else if !atEdge {
                                    hitVibrationMax = false
                                }
                            }
                        
                        
                    } else {
                        let rowH = max(28, button)
                        
                        GeometryReader { gr in
                            let h = gr.size.height
                            let sidePad: CGFloat = max(8, gutter * 0.6)
                            
                            // ✅ Use basically all available width
                            let innerWidth: CGFloat = gr.size.width
                            
                            // ✅ Button size derived from half width (two halves), but clamped
                            let half = innerWidth / 2
                            let btn: CGFloat = min(button, max(26, half * 0.55))   // adjust 0.55 to taste
                            
                            ZStack {
                                // Base capsule fills available width
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(width: innerWidth, height: h)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay(alignment: .leading) {
                                        halfHighlight(side: .left,
                                                      width: innerWidth / 2,
                                                      height: h,
                                                      color: accent,
                                                      active: holdingLeft)
                                    }
                                    .overlay(alignment: .trailing) {
                                        halfHighlight(side: .right,
                                                      width: innerWidth / 2,
                                                      height: h,
                                                      color: accent,
                                                      active: holdingRight)
                                    }
                                    .overlay {
                                        Rectangle()
                                            .frame(width: 1, height: h - 6)
                                            .foregroundStyle(.secondary.opacity(0.28))
                                    }
                                

                                
                                // Full-half tap layers (real interaction)
                                HStack(spacing: 0) {
                                    
                                    // LEFT half
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { _ in
                                                    if !holdingLeft && !holdingRight { beginHold(left: true) }
                                                    
                                                    if selectedEntryIndices.wrappedValue.isEmpty && !controlIsEditing {
                                                        controlIsEditing = true
                                                        ensureControlLiveEntry(lastEntryType: lastEntryType)
                                                    }
                                                    
                                                    functionValue.wrappedValue = max(controlMin, functionValue.wrappedValue - controlStep)

                                                }
                                                .onEnded { _ in endHold() }
                                        )
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.1).onEnded { _ in
                                                startAdjusting(
                                                    up: false,
                                                    forDelay: !tapFunctionalityJustAppended.wrappedValue,
                                                    value: functionValue,
                                                    lowerBound: controlMin,
                                                    upperBound: controlMax,
                                                    step: controlStep
                                                )

                                            }
                                        )
                                        .onLongPressGesture(minimumDuration: .infinity,
                                                            pressing: { p in if !p { stopAdjusting() } },
                                                            perform: {})
                                    
                                    // RIGHT half
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { _ in
                                                    if !holdingLeft && !holdingRight { beginHold(left: false) }
                                                    
                                                    if selectedEntryIndices.wrappedValue.isEmpty && !controlIsEditing {
                                                        controlIsEditing = true
                                                        ensureControlLiveEntry(lastEntryType: lastEntryType)
                                                    }
                                                    
                                                    functionValue.wrappedValue = min(controlMax, functionValue.wrappedValue + controlStep)

                                                }
                                                .onEnded { _ in endHold() }
                                        )
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.1).onEnded { _ in
                                                startAdjusting(
                                                    up: true,
                                                    forDelay: !tapFunctionalityJustAppended.wrappedValue,
                                                    value: functionValue,
                                                    lowerBound: controlMin,
                                                    upperBound: controlMax,
                                                    step: controlStep
                                                )

                                            }
                                        )
                                        .onLongPressGesture(minimumDuration: .infinity,
                                                            pressing: { p in if !p { stopAdjusting() } },
                                                            perform: {})
                                }
                                .frame(width: innerWidth, height: h)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: rowH)
                        .layoutPriority(0.5)
                    }
                
                }
                .layoutPriority(1) // flexible area grows/shrinks before buttons

                Button {
                    guard !LimitReached else { return }

                    func motorType(from option: Int) -> String {
                        switch option {
                        case 1: return "m1"
                        case 2: return "m2"
                        case 3: return "m3"
                        default: return "m2"
                        }
                    }

                    let addType = motorType(from: selectedOption.wrappedValue)
                    let v = functionValue.wrappedValue

                    let lastIsMotor = (lastEntryType == "m1" || lastEntryType == "m2" || lastEntryType == "m3")

                    // --- Append ---
                    if lastIsMotor {
                        addDelay(value: v, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                        tapFunctionalityJustAppended.wrappedValue = true
                        controlLiveType = "delay"                 // ✅ live edit this delay
                    } else if lastEntryType == "delay" {
                        addMotors(value: v, type: addType, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                        tapFunctionalityJustAppended.wrappedValue = false
                        controlLiveType = addType                 // ✅ live edit this motor
                    } else {
                        // first item / unknown
                        if motorFirst {
                            addMotors(value: v, type: addType, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                            tapFunctionalityJustAppended.wrappedValue = false
                            controlLiveType = addType
                        } else {
                            addDelay(value: v, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
                            tapFunctionalityJustAppended.wrappedValue = true
                            controlLiveType = "delay"
                        }
                    }

                    // --- ✅ IMPORTANT: capture the thing we just appended and keep editing it ---
                    controlLiveKey = newestGroupZeroKey()
                    controlIsEditing = true

                    // baseline should match what we appended
                    pendingUnifiedValue.wrappedValue = v

                    // no selection
                    selectedEntryIndices.wrappedValue.removeAll()

                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: button, height: button)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }

                .disabled(LimitReached)
                .layoutPriority(2) // keep this size
                .padding(.trailing, gutter)   // ✅ pushes plus away from right edge
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        
        @ViewBuilder
        // Generic + escaping so it can be captured by ForEach
        func IconsBlock<Icon: View>(
            presentTypes: [String],
            lastEntryType: String?,
            selectedOption: Int,
            iconView: @escaping (_ name: String) -> Icon
        ) -> some View {
            Group {
                if presentTypes.isEmpty {
                    let next = nextTypeToShow(lastEntryType: lastEntryType, selectedOption: selectedOption)
                    iconView(imageName(for: next))
                } else if presentTypes == ["servo"] {
     
                    VStack {
                        iconView(imageName(for: "servo"))
                    }

                } else if Set(presentTypes) == Set(["delay","m1","m2","m3"]) {
                    VStack(spacing: 6) {
                        iconView(imageName(for: "delay"))
                    }
                } else {
                    VStack(spacing: 6) {
                        iconView(imageName(for: "delay"))
                    }
                }
            }
        }

        
        // --- Limits & steps ----------------------------------------------------------
        let delayMin: Double  = 0.01
        let delayMax: Double  = 1.0
        let delayStep: Double = 0.01

        let motorMin: Double  = 0.1 /***/
        let motorMax: Double  = 1.0
        let motorStep: Double = 0.01

        // Unified UI range/step so mixed selections always work
        let unionMin  = min(delayMin, motorMin)     // 0.1
        let unionMax  = max(delayMax, motorMax)     // 60.0
        let unionStep = min(delayStep, motorStep)   // 0.1
        
        let isConnMode = !selectedConnectionIds.isEmpty
        let controlMin: Double = isConnMode ? 0.0 : unionMin
        let controlMax: Double = isConnMode ? 1.0 : unionMax
        let controlStep: Double = isConnMode ? 0.01 : unionStep   // pick taste; 0.01 feels good for smoothing


        // --- Index map for the selected part ----------------------------------------
        let indexForKey: [Int:Int] = Dictionary(
            uniqueKeysWithValues: tapEntriesForSelectedPart.enumerated().map { ($0.element.key, $0.offset) }
        )

        // --- Partition selection into delays vs motors -------------------------------
        let selectedDelayKeys: [Int] = selectedEntryIndices.wrappedValue.compactMap { key in
            guard let idx = indexForKey[key],
                  tapEntriesForSelectedPart[idx].entryType == "delay" else { return nil }
            return key
        }
        @inline(__always) func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

        func connectionNeighbors(_ connId: Double) -> (left: Int, right: Int)? {
            let left = Int(floor(connId))
            let frac = connId - Double(left)
            guard abs(frac - 0.5) < 0.0001 else { return nil }
            return (left, left + 1)
        }

        let selectedMotorKeys: [Int] = selectedEntryIndices.wrappedValue.compactMap { key in
            guard let idx = indexForKey[key] else { return nil }
            let t = tapEntriesForSelectedPart[idx].entryType.lowercased()
            return (t == "m1" || t == "m2" || t == "m3") ? key : nil
        }
        var functionValue = 0.0
        func beginHold(left: Bool) {
            if left {
                holdingLeft = true
                startAdjusting(
                    up: false,
                    forDelay: !tapFunctionalityJustAppended.wrappedValue,
                    value: functionValue,
                    lowerBound: controlMin,
                    upperBound: controlMax,
                    step: controlStep
                )

            } else {
                holdingRight = true
                startAdjusting(
                    up: true,
                    forDelay: !tapFunctionalityJustAppended.wrappedValue,
                    value: functionValue,
                    lowerBound: controlMin,
                    upperBound: controlMax,
                    step: controlStep
                )

            }
        }
        let presentTypesUnordered: [String] = selectedEntryIndices.wrappedValue.compactMap { key in
            guard let idx = indexForKey[key] else { return nil }
            return tapEntriesForSelectedPart[idx].entryType    // "m1", "m2", or "delay"
        }

        // Unique & ordered (delay first, then m1, then m2)
        let order = ["delay", "m1", "m2", "m3"]
        let presentTypes: [String] = Array(Set(presentTypesUnordered))
            .sorted { (lhs, rhs) in
                (order.firstIndex(of: lhs) ?? 999) < (order.firstIndex(of: rhs) ?? 999)

            }

        func imageName(for entryType: String) -> String {
            switch entryType {
            case "m1":   return "line"
            case "m2":   return "2line"
            case "m3": return "3menu"
            case "delay":return "delay"
            case "servo":return "servo"
            default:     return "questionmark" // fallback if ever needed
            }
        }
        let accent: Color = {
            let user = Auth.auth().currentUser
            if let user, !user.isAnonymous, model.creator != "mode123456789"{
                
                if let color = sharedData.imageAccentColors[model.name] {
                    return color
                }
                if isPreviewingModel,
                   let color = sharedData.publishedAccentColors[model.name] {
                    return color
                }
            
            }
            if model.creator == "mode123456789"{
                
                if let color = sharedData.imageAccentColors[model.name] {
                    return color
                }
            }
            if isPreviewingModel,
               let color = sharedData.publishedAccentColors[model.name] {
                return color
            }
            return selectedAccent.color
        }()

        func nudgeFromVisibleBaseline(direction dir: Int) {
            guard dir != 0 else { return }
            // Snap baseline to the slider grid to avoid tiny float drift
            let baseline = (functionValue.wrappedValue / unionStep).rounded() * unionStep
            let target   = min(unionMax, max(unionMin, baseline + Double(dir) * unionStep))
            functionValue.wrappedValue = target   // → your Binding setter applies per-item ±0.1 with clamp/snap
        }



        @ViewBuilder
        func iconView(_ name: String) -> some View {
            let finalName = (name == "servo")
                ? servoImageName(for: selectedServoSet)   // ✅ HERE
                : name

            Image(finalName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .tint(selectedEntryIndices.wrappedValue.isEmpty ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .rotationEffect(
                    name == "servo"
                    ? .degrees(0)
                    : .degrees(90)
                )
        }


        @ViewBuilder
        func holdButton(scale: CGFloat, isTapped: Binding<Bool>, motorType: String) -> some View {
            
            let baseStepsPerSecond = 20.0
            let accel: Double = 2.0
            let growthHzPerSec: Double = 4.0
            let maxStepsPerSecond = 1200.0

            let circleSize = UIScreen.main.bounds.width * 0.4 * scale
            let catcherSize: CGFloat = 240 * scale
            let plusSize = UIScreen.main.bounds.width * 0.1 * scale

            ZStack {
                Circle()
                    .fill(isTapped.wrappedValue ? Color(.systemGray6) : Color(.systemGray5))
                    .overlay(
                        Circle().fill(accent.opacity(isTapped.wrappedValue ? 0.18 : 0.0))
                    )
                    .frame(width: circleSize, height: circleSize)
                    .transition(.controlModeSwap)


                Circle()
                    .fill(LimitReached ? Color(.systemGray4) : Color(.systemGray6))
                    .frame(width: plusSize, height: plusSize)


            }
        }



        return Group {
            if selectedCMND != 0 {
                GeometryReader { geometry in
                    VStack {
                        if controlsForDelay == "slider" || controlsForDelay == "arrows"{
                            
                            VStack(spacing: 20) {
                                // Get the existing entries for the selected part
                                let tapEntriesForSelectedPart = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
                                
                                // Find the entry in groupId == 0 with the highest key
                                let lastGroupZeroEntry = tapEntriesForSelectedPart
                                    .filter { $0.groupId == 0 }
                                    .max(by: { $0.key < $1.key })   // <-- pick the highest key
                                
                                // Get its entry type, if any
                                let lastEntryType = lastGroupZeroEntry?.entryType
                                
                                
                                let displayOption: String = {
                                    if !selectedDelayKeys.isEmpty { return "delay" }
                                    // otherwise show the motor icon for the currently chosen option
                                    return selectedOption.wrappedValue == 1 ? "line" : "2line"
                                }()
                                
                                
                                ViewThatFits(in: .horizontal) {
                                    controlsRow(gutter: 12, button: 36, valueWidth: 68,
                                                presentTypes: presentTypes, lastEntryType: lastEntryType)
                                    controlsRow(gutter: 8,  button: 30, valueWidth: 60,
                                                presentTypes: presentTypes, lastEntryType: lastEntryType)
                                    controlsRow(gutter: 6,  button: 26, valueWidth: 54,
                                                presentTypes: presentTypes, lastEntryType: lastEntryType)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)   // ← was centered before
                                .padding(.horizontal, 0)

                                
                            }
                            .onTapGesture {
                                isTextFieldFocused = false
                            }
                            .padding(.top, 10)
                            
                            
                        } else if controlsForDelay == "tap" {
                            HStack(spacing: 0) {
                                
                                Spacer()

                                // your original size in the center
                                holdButton(scale: 0.4, isTapped: $isTappedLeft, motorType: "m1")
                                
                                Spacer()
                                
                                holdButton(scale: 0.7, isTapped: $isTappedMiddle, motorType: "m2")

                                Spacer()

                                // your original size in the center
                                holdButton(scale: 1.0, isTapped: $isTappedRight, motorType: "m3")

                                Spacer()
                            }
                            .frame(maxWidth: .infinity)

                            
                        }  else if controlsForDelay == "drawer" {
                            if justJoined {
                                MiniDissolvingLinesWithWave(accent: accent)
                            }

                   
                            
                        }
                    }

                    .onAppear {
                        totalScreenWidth = geometry.size.width
                        totalScreenHeight = geometry.size.height
                    }
                    .onChange(of: selectedEntryIndices.wrappedValue) { _ in
                        if !selectedEntryIndices.wrappedValue.isEmpty {
                            // user entered selection mode, stop "auto append" mode
                            controlLiveKey = nil
                            controlLiveType = nil
                            controlIsEditing = false
                        }
                        if let arr = TAPS.wrappedValue[selectedCMND]?[selectedPart] {
                            let indexForKey = Dictionary(uniqueKeysWithValues: arr.enumerated().map { ($0.element.key, $0.offset) })
                            let vals = selectedEntryIndices.wrappedValue.compactMap { key in
                                indexForKey[key].map { arr[$0].value }
                            }
                            guard !vals.isEmpty else { return }
                            let avg = vals.reduce(0, +) / Double(vals.count)
                            let clamped = min(unionMax, max(unionMin, avg))
                            let snapped = (clamped / unionStep).rounded() * unionStep
                            pendingUnifiedValue.wrappedValue = snapped
                            
                            let newestSelected: TapEntry? = selectedEntryIndices.wrappedValue
                                .compactMap { key in indexForKey[key].map { arr[$0] } }
                                .max(by: { $0.key < $1.key })   // "newest" by highest key
                            
                            if let newest = newestSelected {
                                // snap before comparing to be robust against float drift
                                let snappedNewest = (min(unionMax, max(unionMin, newest.value)) / unionStep).rounded() * unionStep
                                suppressHapticsDueTo01Selection = abs(snappedNewest - unionMin) < 1e-9   // unionMin == 0.1
                            } else {
                                suppressHapticsDueTo01Selection = false
                            }
                        }
                        
                        if selectedEntryIndices.wrappedValue.isEmpty {
                            waveCenters.removeAll()
                            waveValues.removeAll()
                        }
                        
                    }
                    
                    
                    .onChange(of: selectedOption.wrappedValue) { newValue in
                        let newType: String = {
                            switch newValue {
                            case 1: return "m1"
                            case 2: return "m2"
                            case 3: return "m3"
                            default: return "m2"
                            }
                        }()

                        guard var cmndDict = TAPS.wrappedValue[selectedCMND],
                              var arr = cmndDict[selectedPart],
                              !selectedEntryIndices.wrappedValue.isEmpty else { return }

                        let indexForKey = Dictionary(uniqueKeysWithValues: arr.enumerated().map { ($0.element.key, $0.offset) })

                        var changed = false
                        for key in selectedEntryIndices.wrappedValue {
                            guard let idx = indexForKey[key] else { continue }
                            let t = arr[idx].entryType.lowercased()

                            // only rewrite motor entries, and only if different
                            if (t == "m1" || t == "m2" || t == "m3"), t != newType {
                                arr[idx] = arr[idx].withType(newType)
                                changed = true
                            }
                        }

                        if changed {
                            cmndDict[selectedPart] = arr
                            TAPS.wrappedValue[selectedCMND] = cmndDict
                        }
                    }

                }
            } else {
                EmptyView()
            }
        }

        .confirmationDialog("controls".localized(),
                            isPresented: $showControlSelectionDelay,
                            titleVisibility: .visible) {
            Button("Tap") { controlsForDelay = "tap" }
            Button("slider".localized()) { controlsForDelay = "slider" }
            Button("arrows".localized()) { controlsForDelay = "arrows" }
        }
        .tint(selectedAccent.color)
    }
    
    func startHold() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let location = contactLocation {
                let xPosition = location.x
                let yPosition = location.y
                
                waveValues.append(1)
                waveCenters.append((location, 1000.0))
                holdData.append((globalOriginalIndex, 1, 1))
                
                globalOriginalIndex += 1
            
            } else {
                print("contactLocation is nil. Cannot append to waveCenters.")
            }
        }
    }
    func durationAdjustedForAcceleration_INCREASING(
        fixedDuration: Double,
        baseStepsPerSecond: Double = 10.0,
        accel: Double = 1.3,            // was 2.0
        growthHzPerSec: Double = 1.3,    // was 2.0
        maxStepsPerSecond: Double = 50.0
    ) -> Double {
        if fixedDuration <= 0 { return 0 }

        // rate(t) = base * accel^(growthHzPerSec * t) = base * e^(k t)
        let k = log(accel) * growthHzPerSec

        // cap time
        let tCap = log(maxStepsPerSecond / baseStepsPerSecond) / k

        // steps accrued until cap
        let stepsToCap = (baseStepsPerSecond / k) * (exp(k * tCap) - 1.0)

        // steps accrued during the actual hold
        let steps: Double
        if fixedDuration <= tCap {
            steps = (baseStepsPerSecond / k) * (exp(k * fixedDuration) - 1.0)
        } else {
            steps = stepsToCap + maxStepsPerSecond * (fixedDuration - tCap)
        }

        // If your stored "duration" is steps/base (old encoding), this is the new stored duration:
        return steps / baseStepsPerSecond
    }

    func stopHold() {
        timer?.invalidate() // Stop the timer
        timer = nil
    }
    
    @inline(__always) func toTicks(_ x: Double) -> Int {
        Int((x / 0.01).rounded(.toNearestOrAwayFromZero))
    }
    @inline(__always) func fromTicks(_ t: Int) -> Double {
        Double(t) * 0.01
    }
    
    

    func activeGesture() -> AnyGesture<Void> {
        // Only handle the drawer drag when GestureSwitch == 1
        guard GestureSwitch == 1 else {
            // Fallback: no-op gesture (adjust if you have other modes)
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        GestureSwitch = 1
                    }
                    .map { _ in }
            )
        }

        // --- Limits & steps ----------------------------------------------------------
        // --- Limits & steps ----------------------------------------------------------
        let delayMin: Double  = 0.01
        let delayMax: Double  = 60.0
        let delayStep: Double = 0.01

        let motorMin: Double  = 0.1 /***/
        let motorMax: Double  = 60.0
        let motorStep: Double = 0.01

        // Unified UI range/step so mixed selections always work
        let unionMin  = min(delayMin, motorMin)     // 0.1
        let unionMax  = max(delayMax, motorMax)     // 60.0
        let unionStep = min(delayStep, motorStep)   // 0.1

        // How much 1pt of movement changes the value
        // (no longer used for live update, but keep if you use it elsewhere)
        let unitsPerPoint: Double = 0.01

        var functionalValue = 0.0
        @inline(__always)
        func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

        /// Returns the index of the entry with `key` in TapData[selectedCMND]?[selectedPart]
        func indexForKey(_ key: Int) -> Int? {
            guard let cmndDict = TapData[selectedCMND],
                  let arr = cmndDict[selectedPart],
                  let idx = arr.firstIndex(where: { $0.key == key })
            else { return nil }
            return idx
        }
        @inline(__always)
        func smoothstep01(_ x: Double) -> Double {
            let t = max(0.0, min(1.0, x))
            return t * t * (3.0 - 2.0 * t)
        }

        /// Read current smoothing for a column (safe defaults if missing)
        func smoothingForColumn(_ columnId: Int) -> (start: Double, end: Double) {
            guard let cmndDict = TapData[selectedCMND],
                  let arr = cmndDict[selectedPart],
                  let i = arr.firstIndex(where: { $0.key == columnId })
            else { return (0, 0) }

            return (arr[i].smoothFactorStart, arr[i].smoothFactorEnd)
        }


        /// Writes smoothing factors for a key (safe no-op if key missing)
        func setSmoothing(key: Int, start: Double? = nil, end: Double? = nil) {
            guard var cmndDict = TapData[selectedCMND],
                  var arr = cmndDict[selectedPart],
                  let idx = arr.firstIndex(where: { $0.key == key })
            else { return }

            if let start { arr[idx].smoothFactorStart = start }
            if let end   { arr[idx].smoothFactorEnd   = end }

            cmndDict[selectedPart] = arr
            TapData[selectedCMND] = cmndDict
        }

        func connectionNeighbors(_ connId: Double) -> (left: Int, right: Int)? {
            let left = Int(floor(connId))
            let frac = connId - Double(left)
            guard abs(frac - 0.5) < 0.0001 else { return nil }
            return (left, left + 1)
        }
        func setSmoothingForColumn(
            columnId: Int,
            start: Double? = nil,
            end: Double? = nil
        ) {
            guard var cmndDict = TapData[selectedCMND],
                  var arr = cmndDict[selectedPart]
            else { return }

            for i in arr.indices {
                guard arr[i].key == columnId else { continue }

                if let start { arr[i].smoothFactorStart = start }
                if let end   { arr[i].smoothFactorEnd   = end }
            }

            cmndDict[selectedPart] = arr
            TapData[selectedCMND] = cmndDict
        }
        // If your canvas splits motor types into 3 equal vertical zones:
        let bandH = canvasHeight / 3.0

        
        @inline(__always)
        func motorTypeFromDrag(startY: CGFloat, currentY: CGFloat, canvasHeight: CGFloat) -> String {
            // Positive when dragging UP
            let dragUp = max(0, startY - currentY)

            // Use the same heights you use to "set" m1/m2/m3
            let bandH = canvasHeight / 3.0
            let m2DragUp: CGFloat = bandH
            let m3DragUp: CGFloat = bandH * 2.0 * 0.8

            // IMPORTANT: If user starts near the top, max possible dragUp is small,
            // so they naturally may never reach these thresholds (exactly what you want).
            if dragUp >= m3DragUp { return "m3" }
            if dragUp >= m2DragUp { return "m2" }
            return "m1"
        }

        
        let drag = DragGesture(minimumDistance: 3)
            .onChanged { value in
                markTouch()
                let location = value.location
                if location.y > 0 {
                    dragLocation = location
                    if gestureStartTime == nil {
                        gestureStartTime = Date()
                    }
                    justJoined = false


                    if canvasWidth > 0, canvasHeight > 0 {
                        if !selectedConnectionIds.isEmpty {

                            let clampedX = min(max(location.x, 0), canvasWidth)
                            let clampedY = min(max(location.y, 0), canvasHeight)
                            let clamped = CGPoint(x: clampedX, y: clampedY)


                            guard let anchorX = connDragAnchorX else { return }

                            // Δx drives the change
                            let dx = clamped.x - anchorX

                            // Soft deadzone (keep yours)
                            let deadPx: CGFloat = 6
                            let rampPx: CGFloat = 22

                            @inline(__always)
                            func softDeadzone(_ v: CGFloat, dead: CGFloat, ramp: CGFloat) -> CGFloat {
                                let a = abs(v)
                                guard a > dead else { return 0 }
                                let x = min(a - dead, ramp) / ramp            // 0...1
                                let s = x * x * (3 - 2 * x)                   // smoothstep
                                let eased = s * ramp + max(0, (a - dead - ramp))
                                return v >= 0 ? eased : -eased
                            }

                            let dzDx = softDeadzone(dx, dead: deadPx, ramp: rampPx)

                            // Map drag distance to smoothing delta.
                            // Pick a "full travel" span; this makes the gesture feel consistent.
                            // Here: drag ~half canvas to go from base -> base+/-1.
                            let fullSpan = max(1, canvasWidth * 0.5)
                            let delta = Double(dzDx / fullSpan)              // roughly -1...+1
                            // Optional easing (matches your smoothstep vibe)
                            let easedDelta: Double = {
                                let sign = delta >= 0 ? 1.0 : -1.0
                                let t = smoothstep01(clamp01(abs(delta)))
                                return sign * t
                            }()

                            // Optional snapping step (feels like your unionStep logic)
                            let smoothingStep = 0.01
                            @inline(__always) func snap01(_ x: Double) -> Double {
                                let c = clamp01(x)
                                return (c / smoothingStep).rounded() * smoothingStep
                            }

                            // Apply SAME write tactic as functionValue.set:
                            // s -> left.end AND right.start
                            for connId in selectedConnectionIds {
                                guard let (leftCol, rightCol) = connectionNeighbors(connId) else { continue }
                                let base = connDragBaseS[connId] ?? 0.0
                                let s = snap01(base + easedDelta)

                                setSmoothingForColumn(columnId: leftCol,  end: s)
                                setSmoothingForColumn(columnId: rightCol, start: s)
                            }
                        
                        
                        } else if !selectedEntryIndices.isEmpty {

                            // --- Clamp ---
                            let epsilon: CGFloat = 100
                            let clampedX = min(max(location.x, 0), canvasWidth)
                            let clampedY = min(max(location.y, 0), canvasHeight)

                            let clamped = CGPoint(x: clampedX, y: clampedY)

                            // --- LIVE motor type from Y (m1/m2/m3) ---
                            let newType = motorType(forY: clamped.y, canvasHeight: canvasHeight)
                            if newType != liveMotorType {
                                liveMotorType = newType
                            }

                            // Helper: read current entryType for a key (so we only retag motor entries)
                            @inline(__always)
                            func entryTypeForKey(_ key: Int) -> String? {
                                guard let cmndDict = TapData[selectedCMND],
                                      let arr = cmndDict[selectedPart],
                                      let idx = arr.firstIndex(where: { $0.key == key })
                                else { return nil }
                                return arr[idx].entryType
                            }

                            @inline(__always)
                            func isMotorType(_ t: String?) -> Bool {
                                guard let t else { return false }
                                return t == "m1" || t == "m2" || t == "m3"
                            }



                            dragRunLastX = clampedX
                            dragRunLastY = clampedY

                            if let startX = dragStartX {
                                let v0 = dragStartValue
                                let dx = clampedX - startX

                                // increase (right)
                                let dxInc = max(0, dx)
                                let hSpanInc = max(1.0, canvasWidth - startX)
                                let nxInc = min(1.0, Double(dxInc / hSpanInc))   // 0…1

                                // decrease (left)
                                let dxDec = max(0, -dx)
                                let hSpanDec = max(1.0, startX)                  // distance to left edge
                                let nxDec = min(1.0, Double(dxDec / hSpanDec))   // 0…1

                                // Signed horizontal progress: right => +, left => -
                                let signedLinear: Double
                                if nxInc > 0 {
                                    signedLinear = nxInc
                                } else if nxDec > 0 {
                                    signedLinear = -nxDec
                                } else {
                                    signedLinear = 0
                                }

                                // Curve magnitude
                                let tLinear = max(-1.0, min(1.0, signedLinear))
                                let gamma = 2.0
                                let mag = pow(abs(tLinear), gamma)
                                let sign = tLinear >= 0 ? 1.0 : -1.0

                                let maxDeltaPerRun: Double = 60.0
                                let runMin = max(unionMin, v0 - maxDeltaPerRun)
                                let runMax = min(unionMax, v0 + maxDeltaPerRun)

                                let rawValue: Double
                                if sign >= 0 {
                                    rawValue = v0 + mag * (runMax - v0)
                                } else {
                                    rawValue = v0 - mag * (v0 - runMin)
                                }

                                // Clamp & snap (now clamp to run range)
                                let clampedGesture = min(runMax, max(runMin, rawValue))
                                let snapped = (clampedGesture / unionStep).rounded() * unionStep
                                
                                for key in selectedEntryIndices {
                                    updateEntryValue(
                                        TAPS: $TapData,
                                        selectedCMND: selectedCMND,
                                        selectedPart: selectedPart,
                                        key: key,
                                        to: snapped
                                    )
                                }
                                functionValue.wrappedValue = snapped
                            }
                        } else {
                            @inline(__always)
                            func snap01(_ x: Double) -> Double {
                                let step = 0.01
                                return (x / step).rounded() * step
                            }

                            @inline(__always)
                            func smoothingFromAngle(dx: CGFloat, dy: CGFloat) -> Double {
                                let adx = abs(dx)
                                let ady = abs(dy)

                                // Avoid NaN / noise when barely moving
                                if adx < 0.0001 && ady < 0.0001 { return 0.0 }

                                // Angle vs horizontal: 0° = horizontal, 90° = vertical
                                let angleRad = atan2(ady, adx)
                                let angleDeg = Double(angleRad * 180.0 / .pi)

                                // ✅ HARD RULES
                                if angleDeg <= 60.0 {
                                    return 1.0
                                }
                                if angleDeg >= 90.0 {
                                    return 0.0
                                }

                                // Linear falloff: 60° → 90°
                                let t = (angleDeg - 60.0) / 30.0   // 0…1
                                let s = 1.0 - t

                                return snap01(s)


                                return snap01(max(0.0, min(1.0, s)))
                            }

                            /// Writes BOTH start/end for the entry key (safe no-op if missing)
                            func setSmoothingBoth(key: Int?, value: Double) {
                                guard let key,
                                      var cmndDict = TapData[selectedCMND],
                                      var arr = cmndDict[selectedPart],
                                      let idx = arr.firstIndex(where: { $0.key == key })
                                else { return }

                                arr[idx].smoothFactorStart = value
                                arr[idx].smoothFactorEnd   = value

                                // optional: keep legacy in sync (handy for older code paths)
                                arr[idx].smoothFactor      = value

                                cmndDict[selectedPart] = arr
                                TapData[selectedCMND] = cmndDict
                            }

                            let epsilonUpFromDelay: CGFloat = 20      // upward distance (px) to flip delay ->
                            let minMotorAvg: CGFloat = 20             // prevents tiny avg making flip too easy
                            let downFactor: CGFloat = 0.01            // flip motor -> delay if down distance >
                            let yDeadband: CGFloat = 1                // treat tiny jitter as straight
                            let minPointsToWrite = 4                  // avoid writing baseline over and over
                            
                            let clamped = CGPoint(
                                x: min(max(location.x, 0), canvasWidth),
                                y: min(max(location.y, 0), canvasHeight)
                            )


                            if segment == .motor, let sY = segmentStartY {
                                let newType = motorTypeFromDrag(startY: sY, currentY: clamped.y, canvasHeight: canvasHeight)

                                if newType != liveMotorType {
                                    liveMotorType = newType
                                    setEntryType(key: motorEntryKey, to: liveMotorType)   // update immediately when tier changes
                                }
                            }



                            // keep your existing last point if you need it elsewhere
                            processingLastPoint = clamped
                            if segment == .none {

                                if tractionStartPoint == nil { tractionStartPoint = clamped }

                                let tractionPx: CGFloat = 10
                                if let p0 = tractionStartPoint, !hasTractionThisGesture {
                                    let d = hypot(clamped.x - p0.x, clamped.y - p0.y)
                                    if d >= tractionPx {
                                        hasTractionThisGesture = true
                                    }
                                }

                                // ✅ DO NOT APPEND ANYTHING until traction is seen
                                guard hasTractionThisGesture else {
                                    firstTimeInControl = false
                                    return
                                }

                                // from here, it's safe to append the first entry
                                let tapEntriesForSelectedPart = TapData[selectedCMND]?[selectedPart] ?? []
                                let (justAppendedVibration, _, _) = checkTapEntries(
                                    TapEntries: tapEntriesForSelectedPart,
                                    selectedCMND: selectedCMND
                                )

                                let entries = TapData[selectedCMND]?[selectedPart] ?? []
                                let lastGroupZeroEntry = entries.filter { $0.groupId == 0 }.max(by: { $0.key < $1.key })
                                let lastType = lastGroupZeroEntry?.entryType

                                let seed = 0.01

                                if lastType == "m1" || lastType == "m2" || lastType == "m3" {
                                    addDelay(value: seed, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)
                                    
                                    tapFunctionalityJustAppended = true
                                    segment = .delay
                                    segAnchorPoint = clamped
                                    segAnchorValue = seed

                                } else if lastType == "delay" {
                                    let mType = liveMotorType
                                    addMotors(value: seed, type: mType, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)

                                    tapFunctionalityJustAppended = false
                                    segment = .motor
                                    segAnchorPoint = clamped
                                    segAnchorValue = seed

                                } else {
                                    if justAppendedVibration {
                                        addDelay(value: seed, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)
                                        tapFunctionalityJustAppended = true
                                        segment = .delay
                                    } else {
                                        let mType = liveMotorType
                                        addMotors(value: seed, type: mType, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)
                                        tapFunctionalityJustAppended = false
                                        segment = .motor
                                    }
                                    segAnchorPoint = clamped
                                    segAnchorValue = seed
                                }

                                firstTimeInControl = false
                                segmentStartY = clamped.y
                                yDir = .none
                                yDirAnchorY = clamped.y
                                lastYForShift = clamped.y
                                return
                            }

                            
                            // --- SHIFT DETECTION (direction-change based) ---
                            
                            let prevShiftY = lastYForShift
                            lastYForShift = clamped.y
                            
                            guard let prevShiftYUnwrapped = prevShiftY else {
                                yDir = .none
                                yDirAnchorY = clamped.y
                                return
                            }
                            
                            let shiftDy = clamped.y - prevShiftYUnwrapped   // down positive

                            
                            var newDir: YDir? = nil
                            if shiftDy > yDeadband { newDir = .down }
                            else if shiftDy < -yDeadband { newDir = .up }

                            // only update direction anchors when we have a real direction
                            if let nd = newDir {
                                if yDirAnchorY == nil { yDirAnchorY = prevShiftYUnwrapped }
                                if nd != yDir {
                                    yDir = nd
                                    yDirAnchorY = prevShiftYUnwrapped
                                }
                            }

                            let anchor = yDirAnchorY ?? clamped.y
                            let travelDown = clamped.y - anchor
                            let travelUp   = anchor - clamped.y

                            
                            // thresholds
                            let avg = max(motorAvgUp, minMotorAvg)
                            let motorToDelayThreshold = downFactor * avg
                            let delayToMotorThreshold = epsilonUpFromDelay
                            // helper: snap + clamp
                            @inline(__always)
                            func snap(_ v: Double, minV: Double, maxV: Double, step: Double) -> Double {
                                let c = min(maxV, max(minV, v))
                                return (c / step).rounded() * step
                            }

                            @inline(__always)
                            func setEntryValue(key: Int?, value: Double) {
                                guard let key,
                                      var cmndDict = TapData[selectedCMND],
                                      var arr = cmndDict[selectedPart] else { return }

                                if let idx = arr.firstIndex(where: { $0.key == key }) {
                                    arr[idx] = arr[idx].withValue(value)
                                    cmndDict[selectedPart] = arr
                                    TapData[selectedCMND] = cmndDict
                                }
                            }

                            guard let p0 = segAnchorPoint else { return }
                            // ✅ Angle-based smoothing (no selection + no connection selection)
                            // Use the direction from the segment anchor to current point.
                            let dxAngle = clamped.x - p0.x
                            let dyAngle = clamped.y - p0.y

                            let sAngle = smoothingFromAngle(dx: dxAngle, dy: dyAngle)

                            // Apply to current segment's active entry (motor or delay)
                            // (for now: same value for start + end)
                            if segment == .motor {
                                setSmoothingBoth(key: motorEntryKey, value: sAngle)
                            } else if segment == .delay {
                                setSmoothingBoth(key: delayEntryKey, value: sAngle)
                            }

                            if segAnchorValue == nil {
                                // baseline once per segment
                                if segment == .motor, let t = motorValueTicks ?? modifyingValueNowTicks {
                                    setEntryType(key: motorEntryKey, to: liveMotorType)
                                    segAnchorValue = fromTicks(t)
                                } else if segment == .delay, let t = delayValueTicks ?? modifyingValueNowTicks {
                                    segAnchorValue = fromTicks(t)
                                } else {
                                    segAnchorValue = 0.01
                                }
                            }
                            let v0 = segAnchorValue ?? 0.01

                            // --- Raw deltas ---
                            let dx = clamped.x - p0.x

                            let rawDy: CGFloat
                            switch segment {
                            case .motor:
                                rawDy = p0.y - clamped.y      // up positive
                            case .delay:
                                rawDy = clamped.y - p0.y      // down positive
                            default:
                                rawDy = 0
                            }

                            // --- Soft deadzone (no step jump at deadPx) ---
                            let deadPx: CGFloat = 6
                            let rampPx: CGFloat = 20   // how gently it comes out of the deadzone

                            @inline(__always)
                            func softDeadzone(_ v: CGFloat, dead: CGFloat, ramp: CGFloat) -> CGFloat {
                                let a = abs(v)
                                guard a > dead else { return 0 }
                                // maps [dead ... dead+ramp] -> [0 ... ramp] smoothly, then continues linearly
                                let x = min(a - dead, ramp) / ramp              // 0...1
                                let s = x * x * (3 - 2 * x)                     // smoothstep
                                let eased = s * ramp + max(0, (a - dead - ramp))// smooth ramp + linear tail
                                return v >= 0 ? eased : -eased
                            }

                            let dy = softDeadzone(rawDy, dead: deadPx, ramp: rampPx)

                            // --- Fixed calibration (prevents edge booms) ---
                            let yCal: CGFloat = 250
                            let xCal: CGFloat = 250

                            // Positive direction = "increase value" axis for this segment
                            let nyInc = min(1.0, Double(max(0, dy) / yCal))
                            let nyDec = min(1.0, Double(max(0, -dy) / yCal))

                            let nxInc = min(1.0, Double(max(0, dx) / xCal))
                            let nxDec = min(1.0, Double(max(0, -dx) / xCal))

                            // Optional extra smoothing so it ramps gently near 0 and near 1
                            @inline(__always)
                            func smoothstep01(_ x: Double) -> Double {
                                let t = max(0.0, min(1.0, x))
                                return t * t * (3.0 - 2.0 * t)
                            }

                            // X-only magnitude (no Y requirement)
                            let xMagInc = smoothstep01(nxInc)   // 0...1
                            let xMagDec = smoothstep01(nxDec)   // 0...1

                            // --- X direction (THIS decides sign) ---
                            let xDeadband: CGFloat = 2
                            let dxFromAnchor = clamped.x - p0.x

                            let xDirNow: Int
                            if dxFromAnchor > xDeadband { xDirNow =  1 }
                            else if dxFromAnchor < -xDeadband { xDirNow = -1 }
                            else { xDirNow = 0 }

                            // latch (optional)
                            if xDirNow != 0 { xDirLatch = xDirNow }
                            let effectiveXDir = xDirLatch

                            var signedCornerProgress: Double = 0
                            if effectiveXDir == 1 {
                                signedCornerProgress = xMagInc          // right => increase only
                            } else if effectiveXDir == -1 {
                                signedCornerProgress = -xMagDec         // left  => decrease only
                            } else {
                                signedCornerProgress = 0
                            }


                            // final t in [-1, 1]
                            let sensitivity: Double = 1.0
                            var t = max(-1.0, min(1.0, signedCornerProgress * sensitivity))



                            // --- Curve + apply to value ---
                            let gamma: Double = 2.5
                            let mag = pow(abs(t), gamma)
                            let sign = t >= 0 ? 1.0 : -1.0

                            let maxDeltaPerRun: Double = 15.0
                            let runMin = max(unionMin, v0 - maxDeltaPerRun)
                            let runMax = min(unionMax, v0 + maxDeltaPerRun)

                            let liveRaw: Double
                            if sign >= 0 { liveRaw = v0 + mag * (runMax - v0) }
                            else         { liveRaw = v0 - mag * (v0 - runMin) }


                            switch segment {

                            case .motor:
                                let clampedToRun = min(runMax, max(runMin, liveRaw))
                                let live = snap(clampedToRun, minV: motorMin, maxV: motorMax, step: motorStep)

                                setEntryValue(key: motorEntryKey, value: live)
                                motorValueTicks = toTicks(live)
                                modifyingValueNowTicks = motorValueTicks

                                // FLIP: down far enough => start delay segment
                                if yDir == .down, travelDown > motorToDelayThreshold {
                                    let seed = snap(0.01, minV: delayMin, maxV: delayMax, step: delayStep)

                                    addDelay(value: seed, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)
                                    segment = .delay

                                    segAnchorPoint = clamped
                                    segAnchorValue = seed
                                    movedRightThisSegment = false
                                    lastXForValueGate = clamped.x
                                    xDirLatch = 0
                                    yDir = .none
                                    yDirAnchorY = clamped.y
                                    lastYForShift = clamped.y
                                    segmentStartY = clamped.y

                                    delayValueTicks = toTicks(seed)
                                    modifyingValueNowTicks = delayValueTicks
                                    return
                                }


                            case .delay:
                                let clampedToRun = min(runMax, max(runMin, liveRaw))
                                let live = snap(clampedToRun, minV: delayMin, maxV: delayMax, step: delayStep)


                                setEntryValue(key: delayEntryKey, value: live)
                                delayValueTicks = toTicks(live)
                                modifyingValueNowTicks = delayValueTicks

                                // FLIP: up far enough => start motor segment
                                if yDir == .up, travelUp > delayToMotorThreshold {
                                    let seed = snap(0.1 /***/, minV: motorMin, maxV: motorMax, step: motorStep)
                                    let mType = liveMotorType
                                    addMotors(value: seed, type: mType, TAPS: $TapData, selectedCMND: selectedCMND, selectedPart: selectedPart)
                                    segment = .motor

                                    segAnchorPoint = clamped
                                    segAnchorValue = seed
                                    movedRightThisSegment = false
                                    lastXForValueGate = clamped.x
                                    xDirLatch = 0
                                    yDir = .none
                                    yDirAnchorY = clamped.y
                                    lastYForShift = clamped.y
                                    segmentStartY = clamped.y

                                    motorValueTicks = toTicks(seed)
                                    modifyingValueNowTicks = motorValueTicks
                                    return
                                }


                            default:
                                break
                            }


                        

                    
                        }
                    }

                    lastWaveLocation = location
                }
            }
            .onEnded { _ in
                connDragAnchorX = nil
                connDragBaseS.removeAll()
            
                connDragAnchorX = nil
                connDragBase.removeAll()
                trajWindow.removeAll()
                trajPeakY = .infinity
                processingLastPoint = nil
                segment = .none
                segmentStartY = nil
                motorUpSamples = 0
                motorAvgUp = 0
                xDirLatch = 0
                // If you want each gesture to create new entries:
                motorEntryKey = nil
                delayEntryKey = nil
                motorValueTicks = nil
                delayValueTicks = nil
                
                segAnchorPoint = nil
                segAnchorValue = nil
                hasTractionThisGesture = false
                tractionStartPoint = nil

                lastXForValueGate = nil

                lastWaveLocation = nil
                dragRunLastX     = nil
                dragRunLastY     = nil
                dragRunDistanceX = 0
                dragStartX       = nil
                dragStartY       = nil
                markTouch() 
            }
            .map { _ in }
        return AnyGesture(drag)
    }
    @inline(__always)
    private func setEntryType(keys: [Int], to newType: String) {
        for k in keys {
            setEntryType(key: k, to: newType)
        }
    }

    private func setEntryType(key: Int?, to newType: String) {
        guard let key,
              var cmndDict = TapData[selectedCMND],
              var arr = cmndDict[selectedPart],
              let idx = arr.firstIndex(where: { $0.key == key })
        else { return }

        let current = arr[idx]
        guard current.entryType != newType else { return } // avoids churn

        arr[idx] = current.withType(newType)

        cmndDict[selectedPart] = arr
        TapData[selectedCMND] = cmndDict
    }



    func updateEntryValue(
        TAPS: Binding<[Int: [Int: [TapEntry]]]>,
        selectedCMND: Int,
        selectedPart: Int,
        key: Int,
        to newValue: Double
    ) {
        guard var cmndDict = TAPS.wrappedValue[selectedCMND],
              var arr = cmndDict[selectedPart],
              let idx = arr.firstIndex(where: { $0.key == key }),
              idx < arr.count else { return }

        arr[idx] = arr[idx].withValue(newValue)
        cmndDict[selectedPart] = arr
        TAPS.wrappedValue[selectedCMND] = cmndDict
    }


    func renderRemoveOrCloseButton2(
        TAPS: Binding<[Int: [Int: [TapEntry]]]>,
        selectedCMND: Int,
        selectedCMNDType: Int,
        selectedAccent: Color,
        isPreviewingModel: Bool,
        playbackIsPlayed: Binding<Bool>,
        lastMaxKeyTaps: Binding<Int?>,
        showStructuralAlert: Binding<Bool>,
        autoScrollEnabledTaps: Binding<Bool>,
        selectedEntryIndices: Binding<Set<Int>>,
        showTAPSModificationLine: Binding<Bool>,
        showDeleteBlockConfirmation: Binding<Bool>,
        showDeleteFor2BlockConfirmation: Binding<Bool>,
        groupColors: Binding<[Int: [Int: [Int: Color]]]>,
        inBuildIsPreviewingModel: Binding<Bool>,
        viewport: Binding<CGRect>,
        visibleIds: Binding<[Int]>,
        itemRects: Binding<[Int: CGRect]>,
        itemEnds: Binding<[Int: CGFloat]>,
        geometry: GeometryProxy
    ) -> some View {

        // ----------------------------
        // Snapshot data used in view
        // ----------------------------
        let selected = selectedEntryIndices.wrappedValue
        let tapEntries = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType] ?? []
        let entriesByKey = Dictionary(uniqueKeysWithValues: tapEntries.map { ($0.key, $0) })

        // non-nil → every selected row has the same non-zero gid
        let commonGroupId: Int? = {
            guard !selected.isEmpty else { return nil }
            var id: Int? = nil
            for key in selected {
                guard let entry = entriesByKey[key] else { return nil }
                let gid = entry.groupId
                if gid == 0 { return nil }
                id = (id == nil) ? gid : (id == gid ? id : nil)
                if id == nil { return nil }
            }
            return id
        }()

        let isGroupedSelection = (commonGroupId != nil)
        let selectionCount = selected.count

        let uniqueTypes: Set<EntryType> = Set(
            selected.compactMap { key -> EntryType? in
                guard let e = entriesByKey[key],
                      let type = EntryType(rawValue: e.entryType),
                      type != .delay
                else { return nil }
                return type
            }
        )

        let actionIsEnabled =
            (2...3).contains(selectionCount) &&
            uniqueTypes.count == selectionCount

        let actionIsUngroup = isGroupedSelection

        // Your existing limit checker
        let (_, _, LimitReached) = checkTapEntries(
            TapEntries: tapEntries,
            selectedCMND: selectedCMND
        )

        // ----------------------------
        // Grouping into columns
        // ----------------------------
        let bundles: [[Int]] = {
            guard !tapEntries.isEmpty else { return [] }
            var grouped: [Int: [Int]] = [:]
            var singles: [[Int]] = []

            for i in tapEntries.indices {
                let gid = tapEntries[i].groupId
                if gid > 0 { grouped[gid, default: []].append(i) }
                else { singles.append([i]) }
            }

            let groupedArrays = grouped.values.map { g in
                g.sorted { tapEntries[$0].key < tapEntries[$1].key }
            }

            var result = singles + groupedArrays
            result.sort { ($0.min() ?? 0) < ($1.min() ?? 0) }
            return result
        }()

        let columns: [[Int]] = bundles.compactMap { group in
            let v = group.filter { tapEntries[$0].value > 0 }
            return v.isEmpty ? nil : v.sorted { tapEntries[$0].key < tapEntries[$1].key }
        }

        let isEmpty = columns.isEmpty

        // ----------------------------
        // Build overlay inputs
        // ----------------------------
        let overlayOrder: [Int] = columns.compactMap { col in
            let sorted = col.sorted { tapEntries[$0].key < tapEntries[$1].key }
            guard let last = sorted.last else { return nil }
            return tapEntries[last].key
        }

        let entriesByColumnId: [Int: [TapEntry]] = Dictionary(
            uniqueKeysWithValues: columns.compactMap { col -> (Int, [TapEntry])? in
                let sorted = col.sorted { tapEntries[$0].key < tapEntries[$1].key }
                guard let last = sorted.last else { return nil }
                let id = tapEntries[last].key
                let entries = sorted.map { tapEntries[$0] }
                return (id, entries)
            }
        )

        // ----------------------------
        @inline(__always)
        func clamp<T: Comparable>(_ x: T, _ a: T, _ b: T) -> T { min(max(x, a), b) }

        func dist2(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return dx*dx + dy*dy
        }

        // distance^2 from point P to line segment AB
        func distanceToSegmentSquared(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)

            let abLen2 = ab.x*ab.x + ab.y*ab.y
            if abLen2 < 0.0001 { return dist2(p, a) }

            let t = clamp((ap.x*ab.x + ap.y*ab.y) / abLen2, 0, 1)
            let proj = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
            return dist2(p, proj)
        }

        func hitTest(
            _ p: CGPoint,
            in hitRanges: [(id: Int, minX: CGFloat, maxX: CGFloat, y: CGFloat)]
        ) -> Int? {

            // Smaller = more precise. Tune these.
            let maxDist: CGFloat = 12          // finger “radius” tolerance
            let xPad: CGFloat = 8              // slight grace outside segment ends

            var best: (id: Int, d2: CGFloat)? = nil

            for r in hitRanges {
                // quick reject (cheap)
                if p.x < r.minX - xPad || p.x > r.maxX + xPad { continue }

                // distance to horizontal segment at y=r.y, clamped to [minX,maxX]
                let cx = clamp(p.x, r.minX, r.maxX)
                let closest = CGPoint(x: cx, y: r.y)
                let d2 = dist2(p, closest)

                if d2 <= maxDist*maxDist {
                    if best == nil || d2 < best!.d2 {
                        best = (r.id, d2)
                    }
                }
            }

            return best?.id
        }

        func hitTestConnection(
            _ p: CGPoint,
            in ranges: [
                (id: Double,
                 start: CGPoint,
                 end: CGPoint,
                 minX: CGFloat, maxX: CGFloat,
                 minY: CGFloat, maxY: CGFloat)
            ]
        ) -> Double? {

            // Smaller = more precise. Tune these.
            let maxDist: CGFloat = 14

            var best: (id: Double, d2: CGFloat)? = nil

            for r in ranges {
                // cheap reject using bbox first
                if p.x < r.minX || p.x > r.maxX || p.y < r.minY || p.y > r.maxY {
                    continue
                }

                // precise distance to the connector segment
                let d2 = distanceToSegmentSquared(p: p, a: r.start, b: r.end)

                if d2 <= maxDist*maxDist {
                    if best == nil || d2 < best!.d2 {
                        best = (r.id, d2)
                    }
                }
            }

            return best?.id
        }


        func toggleColumn(_ colId: Int) {
            guard let column = columns.first(where: { col in
                let sorted = col.sorted { tapEntries[$0].key < tapEntries[$1].key }
                return tapEntries[sorted.last!].key == colId
            }) else { return }

            let groupKeys = Set(column.map { tapEntries[$0].key })
            if selectedEntryIndices.wrappedValue.isSuperset(of: groupKeys) {
                selectedEntryIndices.wrappedValue.subtract(groupKeys)
            } else {
                selectedEntryIndices.wrappedValue.formUnion(groupKeys)
            }
        }
        func hitTestConnection(
            _ p: CGPoint,
            in ranges: [(id: Double, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)]
        ) -> Double? {
            // Match your column hitTest feel
            let xPadding: CGFloat = 18
            let yPadding: CGFloat = 18

            // (Optional) prioritize the closest vertically if multiple match
            let candidates = ranges
                .filter { p.x >= ($0.minX - xPadding) && p.x <= ($0.maxX + xPadding) }
                .map { r -> (r: (id: Double, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat), dist: CGFloat) in
                    // distance to the vertical span (0 if inside)
                    let dy: CGFloat
                    if p.y < r.minY { dy = r.minY - p.y }
                    else if p.y > r.maxY { dy = p.y - r.maxY }
                    else { dy = 0 }
                    return (r, dy)
                }
                .filter { $0.dist <= yPadding }
                .sorted { $0.dist < $1.dist }

            return candidates.first?.r.id
        }

        func toggleConnection(_ connId: Double) {
            if selectedConnectionIds.contains(connId) {
                selectedConnectionIds.remove(connId)
            } else {
                selectedConnectionIds.insert(connId)
                if let n = connectionNeighbors(connId) {
                    let leftEntries  = entriesByColumnId[n.left] ?? []
                    let rightEntries = entriesByColumnId[n.right] ?? []
                    
                    print("Selected connection \(connId) between \(n.left) -> \(n.right)")
                    
                    for e in leftEntries  { print("L[\(n.left)]", e) }
                    for e in rightEntries { print("R[\(n.right)]", e) }

                }
                
            }
        }

        func connectionNeighbors(_ connId: Double) -> (left: Int, right: Int)? {
            // connId should be x.5
            // Example: 12.5 -> left 12, right 13
            let left = Int(floor(connId))
            let frac = connId - Double(left)
            guard abs(frac - 0.5) < 0.0001 else { return nil }
            return (left, left + 1)
        }

        func canToggleConnection(_ connId: Double, selectedColumnIds: Set<Int>) -> Bool {
            guard let n = connectionNeighbors(connId) else { return false }
            return selectedColumnIds.contains(n.left) || selectedColumnIds.contains(n.right)
        }

        return VStack(spacing: 0) {

            let maxValue: CGFloat = 60
            GeometryReader { outerG in
                let availableWidth = outerG.size.width
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {

                        let selectedColumnIds: Set<Int> = Set(
                            overlayOrder.filter { colId in
                                guard let entries = entriesByColumnId[colId] else { return false }
                                return entries.contains(where: { selectedEntryIndices.wrappedValue.contains($0.key) })
                            }
                        )

                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {

                                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                                        let sorted = column.sorted { tapEntries[$0].key < tapEntries[$1].key }
                                        let columnId = tapEntries[sorted.last!].key

                                        let rawValue: CGFloat = {
                                            guard let entries = entriesByColumnId[columnId] else { return 0 }
                                            return entries
                                                .filter { $0.entryType.lowercased() != "servo" }
                                                .map { CGFloat($0.value) }
                                                .max() ?? 0
                                        }()

                                        let t = max(0, min(1, rawValue / maxValue))
                                        let minW = availableWidth * 0.01
                                        let w = max(minW, availableWidth * t)

                                        ZStack(alignment: .leading) {
                                            Color.clear.frame(height: 1)

                                            // 🔴 TRUE END MARKER — GLOBAL SPACE (AUTOSCROLL)
                                            Color.clear
                                                .frame(width: 100, height: 1)
                                                .offset(x: max(0, w - 1))
                                                .id("end-\(columnId)")
                                                .background(
                                                    GeometryReader { g in
                                                        Color.clear.preference(
                                                            key: ItemEndsKey.self,
                                                            value: [columnId: g.frame(in: .global).maxX]
                                                        )
                                                    }
                                                )
                                        }
                                        .frame(width: w * 0.8, height: availableWidth * 0.3)
                                        .id(columnId)

                                        // 🔵 COLUMN RECT — TAPSCROLL SPACE (OVERLAY DRAWING)
                                        .background(
                                            GeometryReader { g in
                                                Color.clear.preference(
                                                    key: ItemRectsKey.self,
                                                    value: [columnId: g.frame(in: .named("tapScroll"))]
                                                )
                                            }
                                        )
                                    }

                                    Color.clear
                                        .frame(width: outerG.size.width * 0.5, height: 1)
                                        .id("scrollTail")
                                }
                                .padding(.horizontal, 12)
                                .background(
                                    GeometryReader { g in
                                        // This minX changes while scrolling (dragging + deceleration)
                                        Color.clear.preference(
                                            key: ScrollXKey.self,
                                            value: g.frame(in: .named("tapScroll")).minX
                                        )
                                    }
                                )
                            }
                            .coordinateSpace(name: "tapScroll")

                            .simultaneousGesture(
                                SpatialTapGesture(coordinateSpace: .named("tapScroll"))
                                    .onEnded { value in
                                        // 1) try connections first
                                        if let connId = hitTestConnection(value.location, in: connectionHitRanges) {
                                            // Only allow if the connection is adjacent to an already selected column
                                            if canToggleConnection(connId, selectedColumnIds: selectedColumnIds) {
                                                toggleConnection(connId)
                                                return
                                            }
  
                                        }


                                        // 2) fallback to columns
                                        if let id = hitTest(value.location, in: waveHitRanges) {
                                            toggleColumn(id)
                                        }
                                    }
                            )

                            // 🟢 GLOBAL VIEWPORT (AUTOSCROLL)
                            .overlay {
                                GeometryReader { g in
                                    Color.clear
                                        .allowsHitTesting(false)
                                        .onAppear { viewport.wrappedValue = g.frame(in: .global) }
                                        .onChange(of: g.frame(in: .global)) { viewport.wrappedValue = $0 }
                                }
                            }
                            // ✅ detect user dragging so autoscroll doesn't fight
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { _ in userDragging = true
                 
                                    }
                            )

                            // ✅ overlay draws only
                            .overlay(alignment: .topLeading) {
                                ConnectedWaveOverlay(
                                    order: overlayOrder,
                                    rects: itemRects.wrappedValue,
                                    entriesByColumnId: entriesByColumnId,
                                    colorForColumnId: { _ in .primary },
                                    selectedColumnIds: selectedColumnIds,
                                    selectedConnectionIds: selectedConnectionIds,
                                    availableWidth: availableWidth * 1.2,
                                    onToggleColumn: { _ in },
                                    onToggleConnection: {_ in},
                                    hitRanges: $waveHitRanges,
                                    connectionHitRanges: $connectionHitRanges,
                                    accentedColor: selectedAccent
                                )
                                .frame(height: availableWidth * 0.30)
                                .allowsHitTesting(false)
                            }

                            // 🔥 AUTOSCROLL — THIS IS THE MONEY
                            .onPreferenceChange(ItemEndsKey.self) { ends in
                                guard autoScrollEnabledTaps.wrappedValue else { return }
                                guard !userDragging else { return }   // ✅ don’t fight the user
                                guard let lastId = overlayOrder.last else { return }
                                guard let endX = ends[lastId] else { return }

                                let vp = viewport.wrappedValue
                                guard vp.width > 0 else { return }

                                let margin = max(24, vp.width * 0.15)
                                guard endX > vp.maxX - margin else { return }

                                let now = CACurrentMediaTime()
                                if now - lastFollowTick < 0.08 { return }
                                lastFollowTick = now

                                DispatchQueue.main.async {
                                    var txn = Transaction()
                                    txn.disablesAnimations = true
                                    withTransaction(txn) {
                                        proxy.scrollTo("end-\(lastId)", anchor: .trailing)
                                    }
                                }
                            }
                            .onPreferenceChange(ScrollXKey.self) { x in
                                // If x is changing, we are scrolling (includes deceleration)
                                if abs(x - lastScrollX) > 0.5 {
                                    userDragging = true
                                    lastScrollX = x

                                    // Cancel any pending "stop" event
                                    scrollEndWork?.cancel()

                                    // Schedule stop shortly AFTER motion truly ends
                                    let work = DispatchWorkItem {
                                        userDragging = false
                                    }
                                    scrollEndWork = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                                }
                            }

                            // 🧠 KEEP RECTS UPDATED FOR OVERLAY
                            .onPreferenceChange(ItemRectsKey.self) { rects in
                                itemRects.wrappedValue = rects
                            }

                            .frame(height: availableWidth * 0.30)
                            .scrollIndicators(.hidden)
                        }
                    }

                    // (rest unchanged)
                    ViewThatFits(in: .horizontal) {
                        actionsRow(side: 40, spacing: 12, horizontalPad: 12)
                        actionsRow(side: 34, spacing: 10, horizontalPad: 10)
                        actionsRow(side: 28, spacing: 8,  horizontalPad: 8)
                    }
                    .padding(.top, 12)
                    .allowsHitTesting(!selected.isEmpty && !inBuildIsPreviewingModel.wrappedValue)
                    .opacity((!selected.isEmpty && !inBuildIsPreviewingModel.wrappedValue) ? 1.0 : 0.0)

                    ViewThatFits(in: .horizontal) {
                        PreviewActionsRow(side: 44, spacing: 12, horizontalPad: 12)
                    }
                    .allowsHitTesting(!selected.isEmpty && inBuildIsPreviewingModel.wrappedValue)
                    .opacity(inBuildIsPreviewingModel.wrappedValue ? 1.0 : 0.0)
                }
                // ✅ keep this GeometryReader from pushing the rest of the UI away
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: geometry.size.width * 0.30 + 16 + 12 + 60) // pick a sensible total, see note below
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: TAPS.wrappedValue) { _ in
            if selectedEntryIndices.wrappedValue.isEmpty {
                userDragging = false
            }
        }
        .onChange(of: selectedCMND) { _ in
            autoSelectAllIfPreviewing()
            userDragging = false
        
        }
        .onChange(of: selectedEntryIndices.wrappedValue) {_ in
            if selectedEntryIndices.wrappedValue.isEmpty {
                selectedConnectionIds.removeAll()
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                autoSelectAllIfPreviewing()
            
                if let bucket = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType] {
                    let groups = Dictionary(grouping: bucket) { $0.key }
                    for (key, entries) in groups where entries.count > 1 {
                        var colors = groupColors.wrappedValue
                        if colors[selectedCMND] == nil { colors[selectedCMND] = [:] }
                        if colors[selectedCMND]![selectedCMNDType] == nil { colors[selectedCMND]![selectedCMNDType] = [:] }
                        if colors[selectedCMND]![selectedCMNDType]![key] == nil {
                            colors[selectedCMND]![selectedCMNDType]![key] = Color(
                                red: .random(in: 0...1),
                                green: .random(in: 0...1),
                                blue: .random(in: 0...1)
                            )
                        }
                        groupColors.wrappedValue = colors
                    }
                }
            }
        }
        .confirmationDialog(
            "are_you_sure_you_want_to_delete_this_block".localized(),
            isPresented: showDeleteBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("yes".localized(), role: .destructive) {
                TAPS.wrappedValue.removeValue(forKey: selectedCMND)
                showDeleteBlockConfirmation.wrappedValue = false
                showTAPSModificationLine.wrappedValue = false
            }
            Button("cancel".localized(), role: .cancel) {
                showDeleteBlockConfirmation.wrappedValue = false
            }
        }
        .confirmationDialog(
            "are_you_sure_you_want_to_delete_these_2_blocks".localized(),
            isPresented: showDeleteFor2BlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("yes".localized(), role: .destructive) {
                TAPS.wrappedValue.removeValue(forKey: selectedCMND)
                showDeleteFor2BlockConfirmation.wrappedValue = false
                showTAPSModificationLine.wrappedValue = false
            }
            Button("cancel".localized(), role: .cancel) {
                showDeleteFor2BlockConfirmation.wrappedValue = false
            }
        }
        
        // ----------------------------
        @ViewBuilder
        func actionButton(
            _ system: String,
            enabled: Bool,
            side: CGFloat,
            accent: Color,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: system)
                    .font(.title2)
                    .foregroundStyle(enabled ? accent : .gray)
                    .frame(width: side, height: side)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
            }
            .disabled(!enabled)
        }

        @inline(__always)
        func selectAllKeysForCurrentBucket() {
            guard inBuildIsPreviewingModel.wrappedValue else { return }
            if let bucket = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType] {
                let keys = Set(bucket.map(\.key))
                DispatchQueue.main.async { selectedEntryIndices.wrappedValue = keys }
            } else {
                DispatchQueue.main.async { selectedEntryIndices.wrappedValue.removeAll() }
            }
        }
        
        func keepLastVisible(_ proxy: ScrollViewProxy, lastId: Int) {
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                proxy.scrollTo("end-\(lastId)", anchor: .leading)

            }
        }

        func scrollLastIntoView(_ proxy: ScrollViewProxy, lastId: Int) {
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                proxy.scrollTo("end-\(lastId)", anchor: .leading)

            }
        }

        func deleteEntriesWithValidation() {
            let before = TAPS.wrappedValue
            var working = before

            guard var bucket = working[selectedCMND]?[selectedCMNDType] else { return }

            // Use your original selection source
            guard !selected.isEmpty else { return }

            logBucket("CURRENT (before delete)", bucket)

            // 1) Delete selected keys
            bucket.removeAll { selected.contains($0.key) }

            // If bucket is empty -> remove it and commit
            if bucket.isEmpty {
                working[selectedCMND]?[selectedCMNDType] = nil
                TAPS.wrappedValue = working
                selectedEntryIndices.wrappedValue.removeAll()
                return
            }

            // 2) Normalize keys after the user's deletion
            bucket.sort { $0.key < $1.key }
            bucket = rebuildBucketWithSequentialKeys(bucket)

            logBucket("AFTER DELETE (before fix)", bucket)

            // 3) 🚑 Auto-fix by DELETING around the offending pair
            var safety = 0
            while hasConsecutives(tapsToModify: bucket), safety < 25 {

                let sorted = bucket.sorted { $0.key < $1.key }
                guard let (a, b) = findInvalidPair(sortedBucket: sorted) else { break }

                // Delete everything BETWEEN a and b (by key), and delete b itself ("after")
                let leftKey = min(a.key, b.key)
                let rightKey = max(a.key, b.key)

                print("🗑️ FIXING by deleting between key \(leftKey) and key \(rightKey), and deleting key \(rightKey) (\(b.entryType))")

                bucket.removeAll { e in
                    // remove in-between (exclusive) OR remove b (rightKey)
                    (e.key > leftKey && e.key < rightKey) || (e.key == rightKey)
                }

                // If that emptied the bucket, commit removal
                if bucket.isEmpty {
                    working[selectedCMND]?[selectedCMNDType] = nil
                    TAPS.wrappedValue = working
                    selectedEntryIndices.wrappedValue.removeAll()
                    return
                }

                bucket.sort { $0.key < $1.key }
                bucket = rebuildBucketWithSequentialKeys(bucket)

                safety += 1
            }

            // 4) Still invalid? revert + alert
            if hasConsecutives(tapsToModify: bucket) {
                print("❌ STRUCTURE STILL INVALID AFTER DELETE-FIX — REVERTING")
                logBucket("REVERTED TO", before[selectedCMND]?[selectedCMNDType] ?? [])
                TAPS.wrappedValue = before
                showStructuralAlert.wrappedValue = true
                return
            }

            logBucket("FINAL (committed after delete)", bucket)

            working[selectedCMND]?[selectedCMNDType] = bucket
            TAPS.wrappedValue = working
            selectedEntryIndices.wrappedValue.removeAll()
        }

        func rebuildBucketWithSequentialKeys(_ bucket: [TapEntry]) -> [TapEntry] {
            let sorted = bucket.sorted { $0.key < $1.key }

            return sorted.enumerated().map { idx, e in
                TapEntry(
                    key: idx + 1,
                    modelName: e.modelName,
                    entryType: e.entryType,
                    value: e.value,
                    groupId: e.groupId,
                    smoothFactor: e.smoothFactor,
                    smoothFactorStart: e.smoothFactorStart,
                    smoothFactorEnd: e.smoothFactorEnd,
                    id: e.id
                )
            }
        }


         func logBucket(_ title: String, _ bucket: [TapEntry]) {
            print("---- \(title) ----")
            for e in bucket.sorted(by: { $0.key < $1.key }) {
                print("key:\(e.key) type:\(e.entryType) value:\(e.value)")
            }
            print("------------------")
        }
         func findInvalidPair(sortedBucket: [TapEntry]) -> (TapEntry, TapEntry)? {
            let filtered = sortedBucket.filter { $0.value != 0.0 }
            guard filtered.count >= 2 else { return nil }

            for i in 0..<(filtered.count - 1) {
                let a = filtered[i]
                let b = filtered[i + 1]
                let isMotorA = ["m1", "m2", "m3"].contains(a.entryType)
                let isMotorB = ["m1", "m2", "m3"].contains(b.entryType)

                let invalid =
                    // delay next to delay
                    (a.entryType == "delay" && b.entryType == "delay") ||
                    // motor next to motor (any tier)
                    (isMotorA && isMotorB)

                if invalid { return (a, b) }

            }
            return nil
        }

        func copyEntriesWithValidation() {
            let before = TAPS.wrappedValue
            var working = before

            guard var bucket = working[selectedCMND]?[selectedCMNDType] else { return }
            let selectedKeys = selectedEntryIndices.wrappedValue
            guard !selectedKeys.isEmpty else { return }
            if LimitReached { return }

            logBucket("CURRENT (before copy)", bucket)

            let byKey = Dictionary(uniqueKeysWithValues: bucket.map { ($0.key, $0) })

            let nonZeroEntries: [TapEntry] = selectedKeys
                .compactMap { byKey[$0] }
                .filter { $0.value != 0 }
                .sorted { $0.key < $1.key }
            
            

            guard !nonZeroEntries.isEmpty else {
                print("❌ No non-zero entries to copy")
                return
            }
            
            let m1Count = nonZeroEntries.filter { $0.entryType == "m1" }.count
            let m2Count = nonZeroEntries.filter { $0.entryType == "m2" }.count
            let m3Count = nonZeroEntries.filter { $0.entryType == "m3" }.count

            // Choose majority; tie or none → stable default (m2 is a good middle)
            let preferredMotorType: String = {
                let maxCount = max(m1Count, m2Count, m3Count)

                let winners = [
                    ("m1", m1Count),
                    ("m2", m2Count),
                    ("m3", m3Count)
                ].filter { $0.1 == maxCount }

                guard maxCount > 0, winners.count == 1 else {
                    return "m2"   // stable default (middle tier)
                }

                return winners[0].0
            }()


            print("📋 COPIED ENTRIES:")
            for e in nonZeroEntries {
                print("key:\(e.key) type:\(e.entryType) value:\(e.value)")
            }

            var nextKey = (bucket.map(\.key).max() ?? -1) + 1
            var newEntries: [TapEntry] = []

            for e in nonZeroEntries {
                newEntries.append(
                    TapEntry(
                        key: nextKey,
                        modelName: e.modelName,
                        entryType: e.entryType,
                        value: e.value,
                        groupId: 0,
                        smoothFactor: e.smoothFactor,
                        smoothFactorStart: e.smoothFactorStart,
                        smoothFactorEnd: e.smoothFactorEnd
                    )
                )
                nextKey += 1
            }

            bucket.append(contentsOf: newEntries)
            bucket.sort { $0.key < $1.key }

            logBucket("AFTER APPEND (before fix)", bucket)


            var safety = 0
            while hasConsecutives(tapsToModify: bucket), safety < 25 {

                let sorted = bucket.sorted { $0.key < $1.key }
                guard let (a, b) = findInvalidPair(sortedBucket: sorted) else { break }

                let insertKey = b.key

                // Make room at insertKey
                bucket = bucket.map { e in
                    if e.key >= insertKey {
                        return TapEntry(
                            key: e.key + 1,
                            modelName: e.modelName,
                            entryType: e.entryType,
                            value: e.value,
                            groupId: e.groupId,
                            smoothFactor: e.smoothFactor,
                            smoothFactorStart: e.smoothFactorStart,
                            smoothFactorEnd: e.smoothFactorEnd,
                            id: e.id
                        )

                    } else {
                        return e
                    }
                }

                // ✅ Decide what to insert
                let insertType: String
                let insertValue: Double = 0.01

                if a.entryType == "delay" && b.entryType == "delay" {
                    insertType = preferredMotorType   // <-- choose m1 or m2 based on selection
                } else {
                    insertType = "delay"
                }


                let insertedEntry = TapEntry(
                    key: insertKey,
                    modelName: a.modelName,
                    entryType: insertType,
                    value: insertValue,
                    groupId: 0,
                    smoothFactor: a.smoothFactor,
                    smoothFactorStart: a.smoothFactorStart,
                    smoothFactorEnd: a.smoothFactorEnd
                )


                print("➕ INSERTING \(insertType) between key \(a.key) (\(a.entryType)) and key \(b.key) (\(b.entryType))")
                print("   → \(insertType).key:\(insertedEntry.key) value:\(insertedEntry.value)")

                bucket.append(insertedEntry)
                bucket.sort { $0.key < $1.key }

                bucket = rebuildBucketWithSequentialKeys(bucket)

                safety += 1
            }


            if hasConsecutives(tapsToModify: bucket) {
                print("❌ STRUCTURE STILL INVALID — REVERTING")
                logBucket("REVERTED TO", before[selectedCMND]?[selectedCMNDType] ?? [])
                TAPS.wrappedValue = before
                return
            }

            logBucket("FINAL (committed)", bucket)

            working[selectedCMND]?[selectedCMNDType] = bucket
            TAPS.wrappedValue = working
            selectedEntryIndices.wrappedValue.removeAll()
        }

         func findIndexToInsertDelay(bucket: [TapEntry]) -> Int? {
            let nonZero = bucket.filter { $0.value != 0.0 }
            guard nonZero.count >= 2 else { return nil }

            for i in 0..<(nonZero.count - 1) {
                let a = nonZero[i]
                let b = nonZero[i + 1]

                let isMotorA = ["m1", "m2", "m3"].contains(a.entryType)
                let isMotorB = ["m1", "m2", "m3"].contains(b.entryType)

                let invalid =
                    (a.entryType == "delay" && b.entryType == "delay") ||
                    (isMotorA && isMotorB)

                if invalid,
                   let indexOfB = bucket.firstIndex(where: { $0.key == b.key }) {
                    return indexOfB
                }

            }

            return nil
        }

        @MainActor
        func autoSelectAllIfPreviewing() {
            guard inBuildIsPreviewingModel.wrappedValue else { return }
            guard let bucket = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType] else {
                selectedEntryIndices.wrappedValue.removeAll()
                return
            }

            // Select only what the UI actually renders (match your columns rule)
            let keys = bucket
                .filter { $0.value > 0 }
                .map(\.key)

            selectedEntryIndices.wrappedValue = Set(keys)
        }

        @ViewBuilder
        func actionsRow(side: CGFloat, spacing: CGFloat, horizontalPad: CGFloat) -> some View {
            HStack(spacing: spacing) {
                actionButton("trash",
                             enabled: !selected.isEmpty,
                             side: side, accent: selectedAccent) {
                    withAnimation(.none) { deleteEntriesWithValidation() }
                }
                /*
                actionButton(actionIsUngroup ? "rectangle.3.group" : "rectangle.3.group.fill",
                             enabled: actionIsEnabled,
                             side: side, accent: selectedAccent) {
                    var taps = TAPS.wrappedValue
                    guard var entries = taps[selectedCMND]?[selectedCMNDType] else { return }

                    if isGroupedSelection {
                        for key in selected {
                            if let idx = entries.firstIndex(where: { $0.key == key }) {
                                entries[idx] = entries[idx].with(groupId: 0)
                            }
                        }
                    } else {
                        let nextGid = (entries.map(\.groupId).max() ?? 0) + 1
                        for key in selected {
                            if let idx = entries.firstIndex(where: { $0.key == key }) {
                                entries[idx] = entries[idx].with(groupId: nextGid)
                            }
                        }
                    }

                    taps[selectedCMND]?[selectedCMNDType] = entries
                    TAPS.wrappedValue = taps
                    selectedEntryIndices.wrappedValue.removeAll()
                }
                 */
                actionButton("plus.square.fill.on.square.fill",
                             enabled: !selected.isEmpty && !LimitReached,
                             side: side, accent: selectedAccent) {
                    copyEntriesWithValidation()
                }

                Button {
                    let sel = selectedEntryIndices.wrappedValue
                    guard let typeEntries = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType],
                          !sel.isEmpty else { return }

                    let filtered = typeEntries
                        .filter { sel.contains($0.key) }
                        .sorted { $0.key < $1.key }

                    if !playbackIsPlayed.wrappedValue {
                        playHapticSequence(for: filtered)
                    } else {
                        playbackIsPlayed.wrappedValue = false
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: side * 0.6, weight: .regular))   // ← smaller eye
                        .foregroundStyle(!playbackIsPlayed.wrappedValue ? selectedAccent : .gray)
                        .frame(width: side, height: side)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    selectedEntryIndices.wrappedValue.removeAll()
                    
                    playbackIsPlayed.wrappedValue = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: side * 0.6, weight: .regular))   // ← smaller eye
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .frame(width: side, height: side)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, horizontalPad)
            .frame(maxWidth: .infinity, alignment: .center)
        }

        @ViewBuilder
        func PreviewActionsRow(side: CGFloat, spacing: CGFloat, horizontalPad: CGFloat) -> some View {
            HStack(spacing: spacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("preview_only".localized()).font(.headline.weight(.semibold))
                    Text("actions_are_hidden_in_previews".localized())
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Button {
                    let sel = selectedEntryIndices.wrappedValue
                    guard let typeEntries = TAPS.wrappedValue[selectedCMND]?[selectedCMNDType],
                          !sel.isEmpty else { return }

                    let filtered = typeEntries
                        .filter { sel.contains($0.key) }
                        .sorted { $0.key < $1.key }

                    if !playbackIsPlayed.wrappedValue {
                        playHapticSequence(for: filtered)
                    } else {
                        playbackIsPlayed.wrappedValue = false
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.title)
                        .foregroundStyle(!playbackIsPlayed.wrappedValue ? selectedAccent : .gray)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, horizontalPad)
            .frame(maxWidth: .infinity, alignment: .center)
        }



        @MainActor
        func followLastIfNeeded(_ proxy: ScrollViewProxy, lastId: Int) {
            guard autoScrollEnabledTaps.wrappedValue else { return }

            let vp = viewport.wrappedValue
            guard vp.width > 0 else { return }

            // “true drawn end” in tapScroll space
            guard let endX = itemEnds.wrappedValue[lastId] else { return }

            let margin: CGFloat = max(24, vp.width * 0.15)
            if endX <= vp.maxX - margin { return }

            // throttle
            let now = CACurrentMediaTime()
            if lastId == lastFollowedId, now - lastFollowTick < 0.08 { return }
            lastFollowTick = now
            lastFollowedId = lastId

            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                // ✅ stable: keeps the end visible without “drifting”
                proxy.scrollTo(lastId, anchor: .center)
            }
        }


    }



    private func startAdjusting(
        up: Bool,
        forDelay: Bool,
        value: Binding<Double>,
        lowerBound: Double = 0.01,
        upperBound: Double = 60.0,
        step: Double = 0.01,
        tick: TimeInterval = 0.01,
        accel: Double = 2.0,
        maxStep: Double = 10.0
    ) {
        isIncreasing   = up
        adjustingDelay = forDelay
        holdDuration   = 0.0
        stopAdjusting()
        
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
            holdDuration += tick
            let accelerated = min(step * pow(accel, holdDuration * 2.0), maxStep)
            
            let rawNext = isIncreasing
            ? value.wrappedValue + accelerated
            : value.wrappedValue - accelerated
            
            let clamped = max(lowerBound, min(upperBound, rawNext))
            let snapped = (clamped / step).rounded() * step
            value.wrappedValue = snapped
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }
    
    private func stopAdjusting() {
        timer?.invalidate()
        timer = nil
    }
     
    
    func addMotors(value: Double, smoothingRadius: Double? = nil, type: String,
                   TAPS: Binding<[Int: [Int: [TapEntry]]]>,
                   selectedCMND: Int, selectedPart: Int) {

        let adjusted = minDuration(value)

        var entries = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
        let currentMax = entries.map { $0.key }.max() ?? -1
        entries.append(TapEntry(key: currentMax + 1,
                                modelName: model.name,
                                entryType: type,
                                value: adjusted))               // ← use adjusted
        entries.removeAll { $0.entryType == "none" }
        setEntries(entries, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
        modifyingEntryKey = currentMax + 1
        motorEntryKey = currentMax + 1
    }
    func setEntries(_ entries: [TapEntry],
                    TAPS: Binding<[Int: [Int: [TapEntry]]]>,
                    selectedCMND: Int,
                    selectedPart: Int) {
        var cmndDict = TAPS.wrappedValue[selectedCMND] ?? [:]
        cmndDict[selectedPart] = entries
        TAPS.wrappedValue[selectedCMND] = cmndDict
    }

    func addDelay(value: Double,
                  smoothingRadius: Double? = nil,
                  TAPS: Binding<[Int: [Int: [TapEntry]]]>,
                  selectedCMND: Int, selectedPart: Int) {

        let adjusted = minDuration(value)        // ← ensure 0.1 minimum

        var entries = TAPS.wrappedValue[selectedCMND]?[selectedPart] ?? []
        let currentMax = entries.map { $0.key }.max() ?? -1
        entries.append(TapEntry(key: currentMax + 1,
                                modelName: model.name,
                                entryType: "delay",
                                value: adjusted))              
        entries.removeAll { $0.entryType == "none" }
        modifyingEntryKey = currentMax + 1
        delayEntryKey = currentMax + 1
        setEntries(entries, TAPS: TAPS, selectedCMND: selectedCMND, selectedPart: selectedPart)
    }
    
    func addServo(TapEntries: [TapEntry]) -> [TapEntry] {
        var updatedEntries = TapEntries
        let currentMax = updatedEntries.map { $0.key }.max() ?? -1
        let newKey = currentMax + 1
        let StypeEntry = TapEntry(key:newKey, modelName: model.name, entryType: "servo", value: 1)
        updatedEntries.append(StypeEntry)
        updatedEntries.removeAll { $0.entryType == "none" }
        
        return updatedEntries
    }
    private func minDuration(_ v: Double) -> Double { max(0.01, v) }
}


extension AnyTransition {
    static var controlModeSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .trailing))
                .combined(with: .scale(scale: 0.98, anchor: .trailing)),
            removal:   .opacity
                .combined(with: .move(edge: .leading))
                .combined(with: .scale(scale: 0.98, anchor: .leading))
        )
    }
}

