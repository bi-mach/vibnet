import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Firebase
import FirebaseFirestore
import Foundation
import FirebaseAppCheck
import Speech
import GoogleSignIn
import CoreHaptics
import PhotosUI
import CoreBluetooth
import FirebaseAuth
import SceneKit
import simd
import UIKit
import FirebaseStorage
import Network
import NaturalLanguage

extension Animation {
    static var Scrolldown: Animation { .easeInOut(duration: 0.5) } // tweak as you like
}
// Favourites
extension PersonalModelsFunctions {
    func fetchAllFavouriteModelsAsync() async -> [String: Model]? {
        await withCheckedContinuation { cont in
            fetchAllFavouriteModels { result in
                switch result {
                case .success(let dict): cont.resume(returning: dict)
                case .failure:           cont.resume(returning: nil)
                }
            }
        }
    }
}

// Published models
extension PublishFunctionality {
    func fetchAllPublishedModelsAsync() async -> [String: Model]? {
        await withCheckedContinuation { cont in
            fetchAllPublishedModels { result in
                switch result {
                case .success(let dict): cont.resume(returning: dict)
                case .failure:           cont.resume(returning: nil)
                }
            }
        }
    }
}

final class ActiveFlag: ObservableObject {
    @Published var value: Bool = false
}



private struct TopBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}


enum DisplayMethod: String, CaseIterable {
    case sphere, plane
}
struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    @EnvironmentObject var notifService: NotificationsService
    @State private var GlobalModelsData: [Int:String] = [:]
    @State private var showForum: Bool = false
    @State private var showingModelsView: Bool = false
    @State private var showAccountView: Bool = false
    @State private var showSettingsView: Bool = false
    private let defaults = UserDefaults.standard
    @EnvironmentObject var functions: Functions
    @State private var selectedNodeName: Int? = nil
    @State private var searchedNode: Int? = nil
    @State private var isSignedIn: Bool = false
    @State private var showSignInAlert = false
    @State private var pendingAction: PendingAction? = nil
    @State private var navigationPath = NavigationPath()
    var isPreview: Bool {
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    @State private var isMenuOpen = false
    @State private var showConnectionAlert = false
    @State private var userEmail: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var nodes: [String: [Double]] = [:]
    @State private var nodeSizes: [String: Int] = [:]
    @State private var animationProgress: CGFloat = 0.0
    @State private var animationTimer: Timer?
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    @State private var showLoading: Bool = false
    @State private var selectedModelCard: Model? = nil
    @State private var notifications: [AppNotification] = []
    @State private var notifListener: ListenerRegistration?
    @State private var showOtherPersonSheet = false
    @State private var selectedAuthorID: String? = nil
    private var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }
    @AppStorage("hasDismissedWelcomeLogin") private var hasDismissedWelcomeLogin: Int = 0
    @State private var isPreviewingModel: Bool = false
    @State private var publishedModels: [String: Model] = [:]
    @State private var favouriteModels: [String: Model] = [:]
    @State private var isFavouriteModel: Bool = false
    @State private var openModelCard: Bool = false
    @State private var ALLUSERSNAMES: [String: String] = [:]
    @State private var showUpdateTheAppMessage = false
    @State private var forceUpdateGateActive = false
    @State private var connections: [Int] = []
    @Environment(\.openURL) private var openURL
    private let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id6751784487")!
    private let firstRunKey = "HasCompletedWelcomeGate"
    private let signedInKey = "IsSignedIn"
    @State private var showWelcomeGate = false
    @State private var orderForConnections: [Int: [Int: Int]] = [:]
    @State private var rateForConnections: [Int: [Int: Double]] = [:]
    @State private var largestShellValue: Int = 0
    @State private var isPreviewVisible: Bool = false
    @State private var previewingName: String = ""
    @State private var previewingDescription: String = ""
    @State private var finallyDisplayPreview: Bool = false
    @State private var additionalIsShowing: Bool = false
    @State private var accountRefreshKey = UUID()
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @State private var sphereRefreshKey = UUID()
    @State private var prevAppearance: AppearanceOption?
    @State private var prevAccent: AccentColorOption?
    @Environment(\.scenePhase) private var scenePhase
    @State private var specificRefreshTask: Task<Void, Never>? = nil
    @State private var isAutoRefreshing = false
    private let appleHelper = AppleSignInHelper()
    @State private var isSigningIn: Bool = false
    @State private var selectedModel: Model? = nil
    @State private var GameStarted: Bool = false
    @State private var isScrolldownActive = false
    @State private var starred: Set<Model.ID> = []
    @AppStorage("selectedFilter") private var selectedFilter: String = "mix".localized()
    @State private var totalModelCount: Int = 0
    @State private var clickCounter: Int = 0
    @State private var globalRefreshKey = UUID()
    @State private var playbackIsPlayed: Bool = false
    
    @State private var selectedUser: SelectedUser? = nil
    @State private var speedingUpPause: Bool = false
    @State private var cachedEntries: [TapEntry] = []
    @State private var currentStepIndex: Int = 0  // where we are in the sequence
    @State private var currentPlayers: [CHHapticAdvancedPatternPlayer] = []
    @State private var lastTapDate: Date = .distantPast   // Track last click time
    @State private var isRollViewClosed: Bool = false   // Track last click time
    
    @State private var iconURLCache: [String: URL] = [:]       // key: model.id.uuidString
    @State private var iconFetchFailures: Set<String> = []
    @State private var selectedImage: UIImage? = nil
    @State private var isAccountViewSelected: Bool = false
    
    @State private var sortedModels: [Model] = []
    @State private var showBlockedSkipAlert: Bool = false
    @State private var BGoverLimit: Bool = false
    @StateObject private var nav = NavigationModel()
    
    @State private var showForumOverlay = false
    @State private var topSafeInset: CGFloat = 0
    @State private var topBarHeight: CGFloat = 0

    private func isPageActive() -> Bool {
        scenePhase == .active
        && !isScrolldownActive
        && !showForum
        && !showLoading
        && !forceUpdateGateActive
        && !showAccountView
        && !showModelsOverlay
    }
    
    // 2) In your parent view:
    @StateObject private var listState = ModelsListState()
    
    // Cache values so we don't rebuild them every render
    private var overLimit: Bool {
        let limit = 50
        return (favouriteModels.count + sharedData.personalModelsData.count) >= limit
    }
    
    private var blockedSet: Set<String> {
        Set(sharedData.blockedUserIDs)
    }
    
    private var H: CGFloat { UIScreen.main.bounds.height } // real device height
    
    private struct SortDeps: Hashable {
        let sortedCount: Int
        let blockedCount: Int
        let globalCount: Int       // <- was globalVersion
        let orderCount: Int
    }
    

    fileprivate func sortVisibleModels(
        _ models: [Model],
        blocked: Set<String>,
        globalModelsData: [Int: String],          // unused now, can be removed
        orderForConnections: [Int: [Int: Int]]    // unused now, can be removed
    ) -> [Model] {

        if selectedFilter == "mix".localized() {
            return models.shuffled()
        }

        let enumeratedVisible = models.enumerated()
            .filter { !blocked.contains($0.element.creator) }

        let sorted = enumeratedVisible.sorted { lhs, rhs in
            if lhs.element.rate != rhs.element.rate {
                return lhs.element.rate > rhs.element.rate
            }
            return lhs.offset < rhs.offset // stable fallback
        }

        return sorted.map { $0.element }
    }



    
    final class ModelsListState: ObservableObject {
        @Published var sortedVisible: [Model] = []
        
        func refresh(
            sortedModels: [Model],
            blocked: Set<String>,
            globalModelsData: [Int: String],
            orderForConnections: [Int: [Int: Int]],
            sorter: @escaping (_ models: [Model],
                               _ blocked: Set<String>,
                               _ globalModelsData: [Int: String],
                               _ orderForConnections: [Int: [Int: Int]]) -> [Model]
        ) {
            // Snapshot inputs to keep capture lists tiny and predictable
            let models = sortedModels
            let blockedSnap = blocked
            let globalSnap = globalModelsData
            let orderSnap = orderForConnections
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result = sorter(models, blockedSnap, globalSnap, orderSnap)
                DispatchQueue.main.async { [weak self] in
                    self?.sortedVisible = result
                }
            }
        }
    }
    
    @State private var bottomOverlayHeight: CGFloat = 0
    @State private var showGameMenu = false
    

    
    private final class HapticOwner {}
    @State private var hOwner = HapticOwner()
    @State private var showModelsOverlay = false
    @State private var showGestureGame: Bool = false
    @State private var SphereIsReady: Bool = false
    @State private var dataPreparationLoding: Bool = false
    @State private var hideTopInset = false
    @State private var showSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var showSuggestions = false
    @State private var committedQuery = ""   // <- only changes on tap/submit
    @FocusState private var focused: Bool
    @State private var leftWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var selectedGroup: [Int] = []
    @State private var didRunInitialLayout: Bool = false
    @State private var hideTheView: Bool = false
    
    @Environment(\.colorScheme) private var systemColorScheme   // device scheme

    @State private var lastSystemScheme: ColorScheme = .light
    @State private var lastEffectiveScheme: ColorScheme = .light
    private var effectiveScheme: ColorScheme {
        switch selectedAppearance {
        case .system: return systemColorScheme      // follow device
        case .dark:   return .dark
        case .light:  return .light
        }
    }
    @State private var pagerReloadToken = UUID()
    @State private var hasUserLoggedIn: Bool = false
    @State private var showAllMessages: Bool = false
    @State private var userName: String = ""
    @State private var isDropDownMenuOpen: Bool = false
    @State private var quickOpen: Bool = false
    private let usdzItems: [(title: String, file: String)] = [
        ("iPhone", "Box"),
        ("Other", "other_model")
    ]
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }


    private func setAccent(for modelName: String, from image: UIImage) {
        let picked: UIColor? = image.vibrantAverageColor ?? image.averageColor
        guard let picked else { return }
        sharedData.publishedAccentColors[modelName] = Color(picked)
    }
    @MainActor
    private func ensurePublishedImageURL(modelName: String) async -> URL? {
        if let url = sharedData.publishedModelImageURLs[modelName] { return url }
        let language = sharedData.appLanguage
        let ref = Storage.storage().reference()
            .child("PublishedModels")
            .child("\(language)")
            .child(modelName)
            .child("ModelImage.jpg")

        do {
            let url: URL = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<URL, Error>) in

                ref.downloadURL { url, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        cont.resume(throwing: URLError(.badURL))
                        return
                    }
                    cont.resume(returning: url)
                }
            }

            sharedData.publishedModelImageURLs[modelName] = url
            return url
        } catch {
            print("downloadURL error for \(modelName):", error.localizedDescription)
            return nil
        }
    }

    @MainActor
    private func prefetchModelImageAndAccentIfNeeded(modelName: String) async {
        // ✅ 1) Always ensure URL first (so AsyncImage can render)
        guard let url = await ensurePublishedImageURL(modelName: modelName) else { return }

        // ✅ 2) If accent already exists, we can stop here
        if sharedData.publishedAccentColors[modelName] != nil { return }
        let language = sharedData.appLanguage
        let id = "PublishedModels/\(language)/\(modelName)/ModelImage.jpg"

        // 3) Disk cache for accent extraction
        if let cached = ImageDiskCache.shared.load(identifier: id) {
            setAccent(for: modelName, from: cached)
            return
        }

        // 4) Download once, cache, set accent
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return }
            ImageDiskCache.shared.save(uiImage, identifier: id)
            setAccent(for: modelName, from: uiImage)
        } catch {
            print("Image download error for \(modelName):", error.localizedDescription)
        }
    }



    @MainActor
    private func prefetchAhead(from currentModel: Model, in models: [Model], count: Int = 5) async {
        guard let i = models.firstIndex(where: { $0.id == currentModel.id }) else { return }
        let end = min(models.count - 1, i + count)
        guard end > i else { return }

        let names = (i+1...end).map { models[$0].name }

        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    await prefetchModelImageAndAccentIfNeeded(modelName: name)

                }
            }
        }
    }


    @AppStorage("onAppModelDescription") private var onAppModelDescription: Data = Data()
    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let overlayBackgroundColor: Color = {
                if selectedAppearance == .system {
                    return systemColorScheme == .dark ? Color.black : Color.white
                } else {
                    return selectedAppearance == .dark ? Color.black : Color.white
                }
            }()
            ZStack {

                ZStack {

                    let totalFavourites = favouriteModels.count
                    let totalPersonal   = sharedData.personalModelsData.count
                    let limit           = 50
                    let overLimit       = (totalFavourites + totalPersonal) >= limit
                    
                    Group {
                        if isScrolldownActive {
                            GeometryReader { geo in
                                VerticalPager(data: listState.sortedVisible) { model, cellIsActive in
                                    ModelRow(
                                        playbackIsPlayed: $playbackIsPlayed,
                                        isScrolldownActive: isRollViewClosed,
                                        model: model,
                                        overLimit: overLimit,
                                        isStarred: starred.contains(model.id),
                                        isActive: cellIsActive,                   // <- let the row gate haptics
                                        selectedFilter: $selectedFilter,
                                        iconURLCache: $iconURLCache,
                                        onTap: {
                                            selectedModelCard = model
                                            isPreviewingModel = true
                                        },
                                        onFilterSelected: { selectedFilter = $0 },
                                        onCreatorTap: { selectedUser = SelectedUser(id: model.creator) },
                                        onChevronUp: {
                                            playbackIsPlayed = false
                                            isRollViewClosed = true
                                            isScrolldownActive = false
                                        },
                                        onEditNote: {},
                                        onReport: {
                                            forumFunctionality.sendUserReport(
                                                forumTag: "scroll",
                                                reason: model.name,
                                                reportedUserUID: model.creator
                                            ) { result in
                                                switch result {
                                                case .success(let id): print("Report filed: \(id)")
                                                case .failure(let error): print("Report failed: \(error.localizedDescription)")
                                                }
                                            }
                                        }
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .ignoresSafeArea()
                                    .id(model.id)                          // keeps lifecycle edges
                                    .transaction { $0.animation = nil }    // no implicit anims on cell updates
                                    .onChange(of: cellIsActive.wrappedValue) { active in
                                        if active {
                                            HapticsManager.shared.activate(for: hOwner)
                                        } else {
                                            HapticsManager.shared.deactivate(for: hOwner)
                                            // optional (usually not needed; uncomment only if you truly want a hard kill):
                                            // HapticsManager.shared.cancelAll()
                                        }
                                    }
                                    .onAppear {
                                        if cellIsActive.wrappedValue {
                                            HapticsManager.shared.activate(for: hOwner)
                                        }
                                    }
                                    .onDisappear {
                                        HapticsManager.shared.deactivate(for: hOwner)
                                    }
                                    
                                    .task(id: model.id) {
                                        fetchIconIfNeeded(model: model)

                                        if cellIsActive.wrappedValue {
                                            // current
                                            await prefetchModelImageAndAccentIfNeeded(modelName: model.name)


                                            // ahead
                                            await prefetchAhead(from: model, in: listState.sortedVisible, count: 5)
                                        }
                                    }


                                }
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(pagerReloadToken) // <— remount on filter change
                                
                            }
                        }
                    }
                    // 3) Recompute the visible list only when inputs change — and off the main thread
                    .task(id: SortDeps(
                        sortedCount: sortedModels.count,
                        blockedCount: blockedSet.count,
                        globalCount: sharedData.GlobalModelsData.count,          // <- use your @State dictionary count
                        orderCount: sharedData.orderForConnections.count
                    )) {
                        listState.refresh(
                            sortedModels: sortedModels,
                            blocked: blockedSet,
                            globalModelsData: sharedData.GlobalModelsData,       // <- your @State var
                            orderForConnections: sharedData.orderForConnections, // [Int: [Int: Int]]
                            sorter: sortVisibleModels                 // <- pass the closure living in ContentView
                        )
                    }
                    
                    .onChange(of: selectedFilter) { _ in
                        // Recompute immediately (optional if you already do it in the .task above)
                        listState.refresh(
                            sortedModels: sortedModels,
                            blocked: blockedSet,
                            globalModelsData: sharedData.GlobalModelsData,
                            orderForConnections: sharedData.orderForConnections,
                            sorter: sortVisibleModels
                        )
                        // Force-recreate pager so it jumps to the first cell
                        pagerReloadToken = UUID()
                    }
                    
                    NavigationStack {
                        ZStack {


                            if !sharedData.GlobalModelsData.isEmpty && !hideTheView{
                                
                                SphereSceneView(
                                    isReady: $SphereIsReady,
                                    largestShellValue: largestShellValue,
                                    rateForConnections: sharedData.rateForConnections,
                                    orderForConnections: sharedData.orderForConnections,
                                    GlobalModelsData: sharedData.GlobalModelsData,
                                    selectedGroup: $selectedGroup,
                                    selectedName: $selectedNodeName,
                                    openModelCard: $openModelCard,
                                    isPreviewVisible: $isPreviewVisible,
                                    hideTopInset: $hideTopInset,
                                    didRunInitialLayout: $didRunInitialLayout,
                                    searchedNode: $searchedNode,
                                    onActivity: { },
                                    onInactivity: { }
                                )
                                .id(sphereRefreshKey)
                                .allowsHitTesting(!showSuggestions)
                                .ignoresSafeArea(.keyboard)

                            } else {
                                if selectedDisplayMethod == .sphere {
                                    RotatingSphereView()
                                        .frame(width: UIScreen.main.bounds.width * 0.8,
                                               height: UIScreen.main.bounds.width * 0.8)
                                } else {
                                    PlainGridAnimationView()
                                        .frame(width: UIScreen.main.bounds.width * 0.8,
                                               height: UIScreen.main.bounds.width * 0.8)
                                }
                                
                                
                            }
                            PreviewPopupTemplate(
                                isVisible: $finallyDisplayPreview,
                                modelName: previewingName,
                                modelDescription: previewingDescription
                            )
                        }
                        
                        
                        .tint(.white)
                        .alert("sign_in_required".localized(), isPresented: $showSignInAlert) {
                            Button("ok".localized(), role: .cancel) {
                                pendingAction = nil
                            }
                        } message: {
                            Text("must_sign_in_body".localized())
                        }
                        

                        
                        NavigationLink(
                            destination:
                                AccountView(
                                    publishedModels: $sharedData.publishedModels,
                                    favouriteModels: favouriteModels,
                                    modelHasBeenDeleted: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            globalRefreshKey = UUID()
                                        }
                                    },
                                    displayTypeUpdated: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            globalRefreshKey = UUID()
                                            showAccountView = false
                                        }
                                    }
                                )
                                .id(accountRefreshKey)
                                .navigationBarBackButtonHidden(true),
                            isActive: $showAccountView
                        ) {
                            EmptyView()
                        }
                        
                        NavigationLink(
                            destination:
                                SettingsView()
                            
                                .background(Color(UIColor.systemBackground))
                                .navigationBarBackButtonHidden(true)
                                .onDisappear {
                                    if prevAppearance != selectedAppearance || prevAccent != selectedAccent {
                                        refreshSessionAndData()
                                        sphereRefreshKey = UUID()
                                    }
                                    if let user = Auth.auth().currentUser {
                                        if user.isAnonymous {
                                            userName = ""
                                        }
                                    } else {
                                        // currentUser is nil
                                        userName = ""
                                    
                                        
                                    }
                                },
                            isActive: $showSettingsView
                        ) {
                            EmptyView()
                        }
                        
                        NavigationLink(
                            destination:
                                ModelsView(
                                    userEmail: userEmail,
                                    modelHasBeenPublished: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            globalRefreshKey = UUID()
                                            // If you also want to pop back automatically:
                                            // showModelsOverlay = false
                                        }
                                    }
                                )
                                .navigationBarBackButtonHidden(true),
                            isActive: $showModelsOverlay
                        ) {
                            EmptyView()
                        }
                        
                        NavigationLink(
                            destination:
                                AllMessagesView()   // <-- Replace with your actual view name
                                .background(Color(UIColor.systemBackground))
                                .navigationBarBackButtonHidden(true)
                            ,
                            isActive: $showAllMessages
                        ) {
                            EmptyView()
                        }
                        .hidden()
                        
                        
                        
                        
                    }
                    .offset(y: isScrolldownActive ? UIScreen.main.bounds.height : 0)
                    .opacity(isScrolldownActive ? 0 : 1)
                    .allowsHitTesting(!(isScrolldownActive || showSuggestions))
                    .preferredColorScheme(selectedAppearance.colorScheme)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                    .disabled(forceUpdateGateActive)
                    .onChange(of: showSettingsView) { presented in
                        if presented {
                            prevAppearance = selectedAppearance
                            prevAccent = selectedAccent
                        }
                    }
                    .sheet(item: $selectedUser) { user in
                        OtherPersonAccountView(publishedModels: sharedData.publishedModels, favouriteModels: favouriteModels,  userID: user.id)
                    }
                    
                    .onChange(of: SphereIsReady) { newValue in
                        print(newValue)
                    }
                    
                    .fullScreenCover(
                        isPresented: Binding(
                            get: { GameStarted && selectedModel != nil },
                            set: { presented in
                                if !presented {
                                    // Single source of reset
                                    GameStarted = false
                                    selectedModel = nil
                                }
                            }
                        )
                    ) {
                        if let model = selectedModel {
                            BuildView(
                                model: model,
                                isPreviewingModel: false,
                                favouriteModels: favouriteModels,
                                isInSheet: false
                            )
                        }
                    }
                    
                    .fullScreenCover(isPresented: $showGestureGame) {
                        DissolvingLinesWithWave()
                    }
                    .fullScreenCover(isPresented: $forceUpdateGateActive) {
                        UpdateGateView(
                            title: "update_the_app_title".localized(),
                            message: "update_the_app_message".localized(),
                            appStoreURL: appStoreURL,
                            isMandatory: true,
                            onDefer: {
                                forceUpdateGateActive = false
                            }
                        )
                        .ignoresSafeArea()
                    }
                    
                    
                    
                    
                    
                    //111111111111
                    .overlay(alignment: .bottom) {
                        if !isLandscape {
                            if !isScrolldownActive && !showForum && !showLoading && !showAccountView && !showModelsOverlay && !hideTopInset && !showAllMessages && !showSettingsView {
                                VStack(spacing: 0) {
                                    ZStack {
                                        HStack(alignment: .center, spacing: 0) {
                                            
                                            Spacer(minLength: 0)
                                            
                                            Button {
                                                if clickCounter < 1 { clickCounter += 1 } else {
                                                    selectedModel = nil; GameStarted = false; clickCounter = 0
                                                }
                                                showSearch = false
                                                focused = false
                                                showSuggestions = false
                                                committedQuery = ""
                                                DispatchQueue.main.async { createNewModel() }
                                            } label: {
                                                Image(systemName: "plus")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: H * 0.035, height: H * 0.035)   // ≈ 3% of screen height
                                                    .foregroundStyle(selectedAccent.color)
                                                    .padding(18)                        // bigger central affordance
                                                    .background(.ultraThinMaterial, in: Circle())

                                            }
                                            .disabled(overLimit)
                                            .accessibilityLabel("New")
                                            
                                        }
                                        .allowsHitTesting(!(isScrolldownActive || showForum))
                                        .opacity((isScrolldownActive || showForum) ? 0.0 : 1.0)
                                        .animation(.easeInOut(duration: 0.22), value: showForum)
                                        .animation(.easeInOut(duration: 0.22), value: isScrolldownActive)
                                        .animation(.easeInOut(duration: 0.22), value: showLoading)
                                        .zIndex(4)
                                        .padding(.trailing, 40)
                                        .padding(.bottom, 40)
                                    }
                                }
                                
                                .frame(maxWidth: .infinity)
                                .readHeight { bottomOverlayHeight = $0 }
                                .background(Color.clear)
                                .ignoresSafeArea(edges: .bottom)
                            }
                            
                        }
                    }
                    
                    .ignoresSafeArea(.keyboard, edges: .bottom) // ⬅️ add this
                    .fullScreenCover(isPresented: $showWelcomeGate) {
                        WelcomeGateView(
                            onContinueWithGmail: {
                                
                                handleGoogleSignIn { success in
                                    if success {
                                        showLoading = false
                                        defaults.set(true, forKey: firstRunKey)
                                        defaults.set(true, forKey: signedInKey)
                                        isSignedIn = true
                                        showWelcomeGate = false
                                        fetchUserName()
                                        fetchUserProfileImage { img in
                                            if let img = img {
                                                selectedImage = img
                                            }
                                        }
                                    } else {
                                        
                                    }
                                }
                            },
                            onContinueAsGuest: {
                                defaults.set(true, forKey: firstRunKey)
                                defaults.set(false, forKey: signedInKey)
                                isSignedIn = false
                                showWelcomeGate = false
                            },
                            onContinueWithApple: {
                                handleAppleSignIn { success in
                                    if success {
                                        defaults.set(true, forKey: firstRunKey)
                                        defaults.set(true, forKey: signedInKey)
                                        isSignedIn = true
                                        showWelcomeGate = false
                                        fetchUserName()
                                        fetchUserProfileImage { img in
                                            if let img = img {
                                                selectedImage = img
                                            }
                                        }
                                    } else {
                                        
                                    }
                                }
                            }
                        )
                        .ignoresSafeArea()
                    }
                    .onChange(of: bottomOverlayHeight) { _ in
                        sharedData.bottomOverlayClearance = bottomOverlayHeight
                    }
                    .onChange(of: selectedAppearance) { newValue in
                        guard newValue != prevAppearance else { return }
                        sphereRefreshKey = UUID()
                        prevAppearance = newValue
                    }
                    
                    .onChange(of: selectedAccent) { newValue in
                        guard newValue != prevAccent else { return }
                        sphereRefreshKey = UUID()
                        prevAccent = newValue
                    }
                    .onAppear {

                        USDZPreloader.shared.preload(named: usdzItems[0].file)

                        if let user = Auth.auth().currentUser, !user.isAnonymous {
                            hasUserLoggedIn = true
                            fetchUserName()
                            
                        }

                        if !isScrolldownActive {
                            fetchUserProfileImage { img in
                                if let img = img {
                                    selectedImage = img
                                }
                            }
                            prevAppearance = selectedAppearance
                            prevAccent = selectedAccent
                            lastEffectiveScheme = effectiveScheme
                            if let email = Auth.auth().currentUser?.email ?? Auth.auth().currentUser?.providerData.compactMap({ $0.email }).first,
                               !email.isEmpty {
                                isSignedIn = true
                                defaults.set(true, forKey: signedInKey)
                            } else {
                                isSignedIn = false
                                if hasDismissedWelcomeLogin == 5 || hasDismissedWelcomeLogin == 0{
                                    showWelcomeGate = true
                                    hasDismissedWelcomeLogin = 0
                                }
                                hasDismissedWelcomeLogin += 1
                                defaults.set(false, forKey: signedInKey)
                            }

                            if let email = Auth.auth().currentUser?.email {
                                fetchUserData(userEmail: email)
                                isSignedIn = true
                                userEmail = email
                                notifService.fetchNotificationsOnce()
                                notifService.startNotificationsListener()
                                personalModelsFunctions.fetchAllFavouriteModels { result in
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(let dict):
                                            self.favouriteModels = dict
                                            sharedData.publishedFavModels = dict
                                        case .failure(let err):
                                            self.favouriteModels = [:]
                                            
                                            
                                        }
                                    }
                                }
                                
                                publishFunctionality.fetchBlockedUsers { result in
                                    switch result {
                                    case .success(let blockedUIDs):
                                        sharedData.blockedUserIDs = blockedUIDs   // ✅ use the array
                                    case .failure(let error):
                                        print("❌ Failed to fetch blocked users:", error.localizedDescription)
                                    }
                                }
                                
                                
                            } else {
                                userEmail = ""
                                isSignedIn = false
                            }
                            

                            
                            fetchUsernamesByDocumentId { result in
                                switch result {
                                case .success(let usernamesDict):
                                    ALLUSERSNAMES = usernamesDict
                                    sharedData.ALLUSERNAMES = usernamesDict
                                case .failure(let error):
                                    print("")
                                }
                            }
                        }
                        
                    }
                    
                    .onChange(of: sharedData.publishedModels) { models in
                        sortedModels = models.values.sorted { $0.id.uuidString < $1.id.uuidString }
                    }
                    .onDisappear { notifService.stopNotificationsListener() }
                    
                    
                    .onChange(of: systemColorScheme) { _ in
                        checkSchemeChangeAndRefresh()
                    }

                    
                    .sheet(item: $selectedModelCard) { selected in
                        
                        BuildView(
                            model: selected,
                            isPreviewingModel: true,
                            favouriteModels: sharedData.publishedFavModels,
                            isInSheet: true,
                            openModelCard: quickOpen
                        )
                    }


                    .alert("skipped_scroll_because_user_is_blocked".localized(),
                           isPresented: $showBlockedSkipAlert) {
                        Button("ok".localized(), role: .cancel) { }
                    }
                           .onChange(of: openModelCard) { open in
                               print("YA CALLED")
                               guard open,
                                     let number = selectedNodeName,
                                     let name = sharedData.GlobalModelsData[number],
                                     !name.isEmpty,
                                     let newModel = sharedData.publishedModels[name]
                               else {
                                   
                                   
                                   selectedNodeName = 0
                                   openModelCard = false
                                   return
                               }
                               
                               if sharedData.blockedUserIDs.contains(newModel.creator) {
                                   selectedNodeName = 0
                                   openModelCard = false
                                   showBlockedSkipAlert = true
                                   UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                   return
                               }
                               quickOpen = true
                               isPreviewingModel = true
                               selectedNodeName = 0
                               isFavouriteModel = sharedData.publishedFavModels.keys.contains(name)
                               
                               selectedModelCard = newModel
       
                               openModelCard = false
                               
                           }
                    
                    
                    
                           .onChange(of: isPreviewVisible) { open in
                               print("YA CALLED2")
                               if open {
                                   guard
                                    let number = selectedNodeName,
                                    let name = sharedData.GlobalModelsData[number],
                                    !name.isEmpty,
                                    let model = sharedData.publishedModels[name]
                                   else {
                                       isPreviewVisible = false
                                       return
                                   }
                                   
                                   // 🚫 Blocked user check
                                   if sharedData.blockedUserIDs.contains(model.creator) {
                                       isPreviewVisible = false
                                       showBlockedSkipAlert = true
                                       UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                       return
                                   }
                                   
                                   
                                   
                                   if let cachedTaps = sharedData.cachedCommandData[name],
                                      let cachedNames = sharedData.cachedCommandNames[name] {
                                       previewingName = name
                                       previewingDescription = model.description
                                       finallyDisplayPreview = true
                                       isPreviewVisible = false
                                   } else {
                                       publishFunctionality.fetchConfigForPublishedModel(modelName: model.name) { result in
                                           DispatchQueue.main.async {
                                               switch result {
                                               case .success(let payload):
                                                   previewingName = name
                                                   previewingDescription = model.description
                                                   sharedData.cachedCommandData[name] = payload.taps
                                                   sharedData.cachedCommandNames[name] = payload.names
                                                   finallyDisplayPreview = true
                                                   isPreviewVisible = false
                                               case .failure:
                                                   isPreviewVisible = false
                                               }
                                           }
                                       }
                                   }
                               }
                           }
                           .onDisappear { stopSpecificAutoRefresh() }
                           .onChange(of: scenePhase) { phase in
                               switch phase {
                               case .active:
                                   hideTheView = false
                                   hideTopInset = false
                               case .inactive, .background:
                                   hideTheView = true
                                   stopSpecificAutoRefresh()
                                   hideTopInset = false
                               @unknown default:
                                   break
                               }
                               
                           }
                    
                    
                    
                }
                .onReceive(nav.$pending.compactMap { $0 }) { route in
                    if route == .model {
                        showSettingsView = true          // present your existing fullScreenCover
                        nav.pending = nil                // consume the route
                    }
                }
                .onDisappear {
                    sphereRefreshKey = UUID()
                }
                // Add effectiveScheme to your dependency bundle if already tracking others
                .task(id: effectiveScheme) {
                    // First time? Just record it
                    if lastEffectiveScheme == effectiveScheme { return }
                    
                    // 💡 Effective scheme flipped (light <-> dark)
                    sphereRefreshKey = UUID()       // 🔁 Rebuild Sphere/Plane views
                    
                    // Store new scheme
                    lastEffectiveScheme = effectiveScheme
                }
                
                .onChange(of: showSettingsView) { if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showForum)        { if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showAccountView)  { if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showModelsOverlay){ if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showAllMessages)  { if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showGestureGame)  { if $0 { isDropDownMenuOpen = false } }
                .onChange(of: showWelcomeGate)  { if $0 {
                    isDropDownMenuOpen = false }
                    if hasDismissedWelcomeLogin == 0 {
                        hasDismissedWelcomeLogin += 1
                    }
                }
                .onChange(of: isScrolldownActive){ if $0 { isDropDownMenuOpen = false } }
                .onChange(of: GameStarted) { if $0 { isDropDownMenuOpen = false } }
                
                // --- Tap-to-dismiss dropdown overlay ---
                if isDropDownMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDropDownMenuOpen = false
                            }
                        }
                }
                
            }
            .id(globalRefreshKey)
            //22222222222222
            .safeAreaInset(edge: .top) {
                if !isLandscape {
                    HStack(alignment: .top) {
                    
                        if !showForum && !isScrolldownActive && !showLoading && !showAccountView && !showModelsOverlay && !hideTopInset && !showSettingsView && !showAllMessages{

                            ProfileMenuButton(onSearchCompleted: {
                                triggerSearchAction()
                            },
                            onShowForum: {
                                showSearch = false
                                focused = false
                                showSuggestions = false
                                
                                showForum = true
                            },
                            onShowProfile: {
                                showSearch = false
                                focused = false
                                showSuggestions = false
                                committedQuery = ""
                                isRollViewClosed = false
                                isScrolldownActive = false
                                showModelsOverlay = false
                                showGameMenu = false
                                accountRefreshKey = UUID()
                                showAccountView = true
                                notifService.stopNotificationsListener()
                            },
                            onShowMessages: {
                                showAllMessages = true
                            },
                            onShowGame: {
                                showSearch = false
                                focused = false
                                showSuggestions = false
                                committedQuery = ""
                                showGestureGame = true
                            },
                            onShowStorage: {
                                showAccountView = false
                                showGameMenu = false
                                isRollViewClosed = false
                                isScrolldownActive = false
                                showModelsOverlay = true
                                showSearch = false
                                focused = false
                                showSuggestions = false
                                committedQuery = ""
                            },
                            onShowScrolls: {
                                let now = Date()
                                if now.timeIntervalSince(lastTapDate) > 2 {
                                    showSearch = false
                                    focused = false
                                    showSuggestions = false
                                    committedQuery = ""
                                    lastTapDate = now
                                    showModelsOverlay = false
                                    showAccountView = false
                                    showGameMenu = false
                                    withAnimation(.Scrolldown) {
                                        isRollViewClosed = true
                                        isScrolldownActive = true
                                    }
                                    
                                }
                            },
                            onShowSettings: {
                                showSettingsView = true
                            },
                                              selectedImage: selectedImage,
                                              H: H,
                                              selectedAccent: selectedAccent.color,
                                              userName: userName,
                                              searchQuery: $searchQuery,
                                              isOpen: $isDropDownMenuOpen
                                              
                            )
           
                            .padding(.leading)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
               
                                TextField("search".localized(), text: $searchQuery)
                                    .focused($focused)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 18))
                                    .padding(.leading, 18)
                                    .padding(.vertical, 14)
                                    .tint(.primary)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .submitLabel(.return)
                                    .onChange(of: searchQuery) { newValue in
                                        if newValue.count > 50 {
                                            searchQuery = String(newValue.prefix(50))
                                        }
                                    }
                                    .onSubmit {
                                        triggerSearchAction()
                                    }

                            }
                            .background(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(.ultraThinMaterial.opacity(0.9)) // 👈 THIS is the key
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 28)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .frame(height: 56)
                            .padding(.horizontal, 14)
                            .padding(.top, 10) // 👈 Move it lower
                        }
                    }
                }
            }
            
        }
    }
    
    
    private func closeDropdown() {
        if isDropDownMenuOpen {
            withAnimation(.easeInOut(duration: 0.25)) {
                isDropDownMenuOpen = false
            }
        }
    }

    private func fetchUserName() {
        
        guard let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous else {
            
            return
        }

        
        let userEmail = currentUser.email ?? ""
        let uid = currentUser.uid
        
    
        let db = Firestore.firestore()
        db.collection("Followers").document(uid).getDocument { snapshot, error in
            if let error = error {
                
                return
            }

            
            guard let data = snapshot?.data() else {
                
                return
            }

            let fetchedName = data["UserName"] as? String ?? ""
            let fetchedBio = data["Bio"] as? String ?? ""
            
            DispatchQueue.main.async {
                userName = fetchedName
                sharedData.myUsername = fetchedName
            }
        }
    }
    private func commandDescriptions(for modelName: String) -> [String] {
        guard let level1 = sharedData.cachedCommandNames[modelName] else { return [] }

        // cachedCommandNames: [String: [Int: [Int: String]]]
        // We ignore the ints, flatten to [String] descriptions.
        var out: [String] = []
        out.reserveCapacity(64)

        for (_, level2) in level1 {
            for (_, desc) in level2 {
                let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
            }
        }
        return out
    }

    private func bestCommandSimilarity(queryTF: [String: Double], modelName: String) -> Double {
        let descriptions = commandDescriptions(for: modelName)
        guard !descriptions.isEmpty else { return 0 }

        var best: Double = 0
        for d in descriptions {
            let dTokens = tokens(from: d)
            if dTokens.isEmpty { continue }
            let dTF = termFrequency(for: dTokens)
            let s = cosineSimilarity(queryTF, dTF)
            if s > best { best = s }
            // tiny micro-optimization: if it's basically perfect, stop early
            if best > 0.98 { break }
        }
        return best
    }

    // 1) put the shared action in a helper
    private func triggerSearchAction() {
        var hasText: Bool {
            !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            
            if hasText {

                var modelsCountByPKAndName: [Int: [String: Int]] {
                    var result: [Int: [String: Int]] = [:]
                    for (pk, name) in sharedData.GlobalModelsData {
                        let count = sharedData.orderForConnections[pk]?.count ?? 0
                        result[pk] = [name: count]
                    }
                    return result
                }
                
                var rankedResults: [(name: String, score: Double)] {
                    let models = sharedData.publishedModels

                    let qTokens = tokens(from: searchQuery)
                    let qTF = termFrequency(for: qTokens)

                    return models.map { (name, model) in
                        // Name similarity (your existing)
                        let nameScore = similarityForName(name, searchQuery)

                        // Model description cosine similarity (your existing)
                        let descTokens = tokens(from: model.description)
                        let descTF = termFrequency(for: descTokens)
                        let descScore = cosineSimilarity(qTF, descTF)

                        // NEW: command description similarity (best match across commands)
                        let commandScore = bestCommandSimilarity(queryTF: qTF, modelName: name)

                        // Combine
                        // - Keep your desc emphasis
                        // - Add commandScore so even one matching command boosts the model
                        // Feel free to tweak weights.
                        let score =
                            0.30 * nameScore +
                            0.50 * descScore +
                            0.20 * commandScore

                        return (name: name, score: score)
                    }
                    .filter { $0.score > 0 }
                    .sorted { $0.score > $1.score }
                    .prefix(50)
                    .map { ($0.name, $0.score) }
                }

                
                
                
                let nameToPK = Dictionary(
                    sharedData.GlobalModelsData.map { ($0.1, $0.0) },
                    uniquingKeysWith: { first, _ in first }
                )

                let results = rankedResults
                
                if results.count >= 2 {
                    var seen = Set<Int>()
                    selectedGroup = results
                        .compactMap { nameToPK[$0.name] }
                        .filter { seen.insert($0).inserted }
                    
                    searchedNode = selectedGroup.first
                } else {
                    selectedGroup = []        // or leave unchanged if preferred
                    searchedNode = nil        // optional: clear searched node too
                }
                
                
                
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showSuggestions = false
                    showSearch = false
                    focused = false
                }
            } else {
                searchedNode = nil
                selectedGroup = []
                showSearch = false
                focused = false
                showSuggestions = false
            }
        
        }
    }


    
    
    func fetchUserProfileImage(completion: @escaping (UIImage?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cacheID = "\(uid)/ProfileImage.jpg"
        
        // 1. Try disk cache first
        if let cached = ImageDiskCache.shared.load(identifier: cacheID) {
            completion(cached)
            return
        }
        
        // 2. Fallback: fetch from Firebase
        let storageRef = Storage.storage().reference()
            .child("ProfileImages")
            .child(uid)
            .child("ProfileImage.jpg")
        
        storageRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            if let data, let image = UIImage(data: data) {
                // Save to disk for next time
                ImageDiskCache.shared.save(image, identifier: cacheID, quality: 0.9)
                completion(image)
            } else {
                completion(nil)
            }
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



    private func fetchIconIfNeeded(model: Model) {
        let modelId = model.creator
        guard !modelId.isEmpty else { return }
        if iconURLCache[modelId] != nil || iconFetchFailures.contains(modelId) { return }
        
        let storage = Storage.storage()
        let base = storage.reference().child("ProfileImages").child(modelId)
        
        // 1) Quick tries
        let candidates = ["example.png.png"]
        
        func resolve(from refs: [StorageReference], completion: @escaping (URL?) -> Void) {
            guard let ref = refs.first else { completion(nil); return }
            ref.downloadURL { url, _ in
                if let url { completion(url) }
                else { resolve(from: Array(refs.dropFirst()), completion: completion) }
            }
        }
        
        resolve(from: candidates.map { base.child($0) }) { url in
            if let url {
                DispatchQueue.main.async { self.iconURLCache[modelId] = url }
                return
            }
            
            // 2) Fallback: list folder, pick newest
            base.listAll { result, error in
                if let error = error {
                    print("[Icons] list error (\(modelId)):", error.localizedDescription)
                    DispatchQueue.main.async { self.iconFetchFailures.insert(modelId) }
                    return
                }
                let items = result?.items ?? []
                guard !items.isEmpty else {
                    DispatchQueue.main.async { self.iconFetchFailures.insert(modelId) }
                    return
                }
                
                var metas: [(StorageReference, StorageMetadata)] = []
                let group = DispatchGroup()
                for item in items {
                    group.enter()
                    item.getMetadata { meta, _ in
                        if let meta { metas.append((item, meta)) }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    let best = metas.sorted { ($0.1.updated ?? .distantPast) > ($1.1.updated ?? .distantPast) }.first?.0
                    best?.downloadURL { url, _ in
                        DispatchQueue.main.async {
                            if let url { self.iconURLCache[modelId] = url }
                            else { self.iconFetchFailures.insert(modelId) }
                        }
                    }
                }
            }
        }
    }
    
    func handleAppleSignIn(completion: @escaping (Bool) -> Void) {
        appleHelper.startSignInWithAppleFlow { success in
            guard success else { completion(false); return }

            guard let user = Auth.auth().currentUser, !user.isAnonymous else {
                completion(false); return
            }

            let uid = user.uid
            let email = user.email ?? ""              // may be empty after first sign-in
            let name  = user.displayName ?? ""

            // Use email when available, otherwise fallback to uid
            let userKey = email.isEmpty ? uid : email

            print("Apple/Firebase signed in: uid=\(uid) email=\(email) name=\(name)")
            saveUserState(userName: name.isEmpty ? "No Name" : name,
                          userEmail: email.isEmpty ? "No Email" : email)
            isSignedIn = true

            functions.doesUserExist(user: userKey) { exists in
                if exists {
                    completion(true)
                    return
                }

                functions.createUserFolder(user: userKey, userName: name) { created in
                    print("createUserFolder: \(created)")
                    completion(true)
                }
            }
        }
    }

    
    private func stopSpecificAutoRefresh() {
        specificRefreshTask?.cancel()
        specificRefreshTask = nil
    }
    
    private func checkSchemeChangeAndRefresh() {
        let newScheme = effectiveScheme
        if newScheme != lastEffectiveScheme {
            lastEffectiveScheme = newScheme
            sphereRefreshKey = UUID()
        }
    }
    
    private func refreshSessionAndData() {
        if let email = Auth.auth().currentUser?.email ?? Auth.auth().currentUser?.providerData.compactMap({ $0.email }).first,
           !email.isEmpty {
            isSignedIn = true
            notifService.fetchNotificationsOnce()
            defaults.set(true, forKey: signedInKey)
        } else {
            notifService.stopNotificationsListener()
            notifService.notifications = []
            isSignedIn = false
            defaults.set(false, forKey: signedInKey)
        }
        
        
        if let email = Auth.auth().currentUser?.email ??
            Auth.auth().currentUser?.providerData.compactMap({ $0.email }).first,
           !email.isEmpty {
            
            userEmail = email
            fetchUserData(userEmail: email)
            isSignedIn = true
            personalModelsFunctions.fetchAllFavouriteModels { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let dict):
                        favouriteModels = dict
                        sharedData.publishedFavModels = dict
                    case .failure:
                        favouriteModels = [:]
                    }
                }
            }
        } else {
            userEmail = ""
            isSignedIn = false
        }
        
        fetchUsernamesByDocumentId { result in
            switch result {
            case .success(let usernamesDict):
                ALLUSERSNAMES = usernamesDict
                sharedData.ALLUSERNAMES = usernamesDict
                
                
            case .failure(let error):
                print("")
            }
        }
        
        retrieveDocuments { result in
            switch result {
            case .success:
                publishFunctionality.fetchAllPublishedModels { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let dict):
                            sharedData.publishedModels = dict
                            showLoading = false
                        case .failure:
                            sharedData.publishedModels = [:]
                        }
                    }
                }
            case .failure(let error):
                print("")
            }
        }
    }
    
    func fetchUsernamesByDocumentId(completion: @escaping (Result<[String: String], Error>) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("Followers").getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(.success([:]))
                return
            }
            
            var usernamesById: [String: String] = [:]
            
            for doc in documents {
                if let username = doc.data()["UserName"] as? String {
                    usernamesById[doc.documentID] = username
                }
            }
            
            completion(.success(usernamesById))
        }
    }
    
    func checkAppVersion(completion: @escaping (String) -> Void) {
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        
        let db = Firestore.firestore()
        let docRef = db.collection("appVersion").document("latestVersion")
        
        docRef.getDocument { (document, error) in
            if let document = document, document.exists,
               let latestVersion = document.data()?["version"] as? String {
                completion(latestVersion)
                
            } else {
                
                completion("")
            }
        }
    }
    
    func retrieveDocuments(completion: @escaping (Result<[Int: String], Error>) -> Void) {
        let db = Firestore.firestore()
        let collection = db.collection("Models")
        // Add any additional shards here
        let docIDs = ["Nodes"]

        var mergedModels: [Int: String] = [:]
        var mergedConnections: [Int: [Int: Int]] = [:]
        var mergedRates: [Int: [Int: Double]] = [:]
        var mergedLargestShellValue: Int = 0

        let group = DispatchGroup()
        var firstError: Error?

        for id in docIDs {
            group.enter()
            collection.document(id).getDocument { snap, err in
                defer { group.leave() }

                if let err = err {
                    // Record the first error but keep going to merge whatever we can.
                    if firstError == nil { firstError = err }
                    return
                }
                guard let data = snap?.data() else { return }

                // Merge numeric top-level fields into GlobalModelsData
                for (key, value) in data {
                    // Skip known non-model maps
                    if key == "Connections" || key == "Rate" || key == "largestShellValue" { continue }
                    if let intKey = Int(key) {
                        if let s = value as? String {
                            mergedModels[intKey] = s
                        } else if let n = value as? NSNumber {
                            mergedModels[intKey] = n.stringValue
                        }
                    }
                }

                // Merge Connections
                if let connections = data["Connections"] as? [String: Any] {
                    for (outerKey, innerDictAny) in connections {
                        guard let outerIntKey = Int(outerKey),
                              let innerMap = innerDictAny as? [String: Any] else { continue }

                        var innerResult = mergedConnections[outerIntKey] ?? [:]
                        for (innerKey, innerValAny) in innerMap {
                            if let innerIntKey = Int(innerKey) {
                                if let v = innerValAny as? Int {
                                    innerResult[innerIntKey] = v
                                } else if let num = innerValAny as? NSNumber {
                                    innerResult[innerIntKey] = num.intValue
                                }
                            }
                        }
                        mergedConnections[outerIntKey] = innerResult
                    }
                }
                
                

                // Merge Rate
                if let rates = data["Rate"] as? [String: Any] {
                    for (outerKey, innerDictAny) in rates {
                        guard let outerIntKey = Int(outerKey),
                              let innerMap = innerDictAny as? [String: Any] else { continue }

                        var innerResult = mergedRates[outerIntKey] ?? [:]
                        for (innerKey, innerValAny) in innerMap {
                            if let innerIntKey = Int(innerKey) {
                                if let v = innerValAny as? Double {
                                    innerResult[innerIntKey] = v
                                } else if let num = innerValAny as? NSNumber {
                                    innerResult[innerIntKey] = num.doubleValue
                                }
                            }
                        }
                        mergedRates[outerIntKey] = innerResult
                    }
                }

                // largestShellValue (last writer wins)
                if let lsv = data["largestShellValue"] as? Int {
                    mergedLargestShellValue = lsv
                } else if let num = data["largestShellValue"] as? NSNumber {
                    mergedLargestShellValue = num.intValue
                }
            }
        }

        group.notify(queue: .main) {
            // If absolutely nothing came back and we had an error, surface it
            if mergedModels.isEmpty, let err = firstError {
                completion(.failure(err))
                return
            }



            sharedData.GlobalModelsData = mergedModels
             
            sharedData.orderForConnections = mergedConnections
            sharedData.rateForConnections = mergedRates
            sharedData.largestShellValue = mergedLargestShellValue
            completion(.success(mergedModels))
        }
    }

    
    func fetchUserData(userEmail: String) {
        isSignedIn = true
        personalModelsFunctions.fetchMyModels(for: userEmail) { result in
            switch result {
            case .success(let modelNames):
                
                for name in modelNames {
                    
                    let alreadyLoaded = sharedData.personalModelsData.contains { $0.name == name }
                    guard !alreadyLoaded else { continue }
                    guard
                        let user = Auth.auth().currentUser,
                        !user.isAnonymous
                    else { return }

                    let uid = user.uid

                    personalModelsFunctions.fetchModelData(for: name, uid: uid) { result in
                        switch result {
                        case .success(let modelData):
                            let newModel = Model(
                                name: name,
                                description: modelData["description"] as? String ?? "",
                                keyword: modelData["keyword"] as? String ?? "",
                                creator: modelData["creator"] as? String ?? "",
                                rate: modelData["rate"] as? Int ?? 0,
                                creationDate: modelData["creationData"] as? String ?? "",
                                publishDate: modelData["publishDate"] as? String ?? "",
                                justCreated: modelData["justCreated"] as? Bool ?? false,
                                createdWithVib: modelData["createdWithVib"] as? Bool ?? false
                            )
                            DispatchQueue.main.async {
                                sharedData.personalModelsData.insert(newModel)
                            }
                            
                            
                        case .failure(let error):
                            print("")
                            
                        }
                    }
                }
                
            case .failure(let error):
                print("")
            }
            
            
        }
    }
    
    func fetchUserNames(for modelsById: [String: Model]) async throws -> [String: String] {
        let db = Firestore.firestore()
        
        return try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for model in modelsById.values {
                let docId = model.creator.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !docId.isEmpty else { continue }
                
                group.addTask {
                    let snap = try await db.collection("Followers").document(docId).getDocument()
                    
                    
                    if let decoded = try? snap.data(as: FollowerDoc.self) {
                        return (docId, decoded.userName)
                    } else {
                        let raw = snap.get("UserName") as? String
                        return (docId, raw)
                    }
                }
            }
            
            var result: [String: String] = [:]
            for try await (docId, userName) in group {
                if let userName { result[docId] = userName }
            }
            return result
        }
    }
    
    private func createNewModel() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue.global(qos: .background)
        
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                // ✅ Internet available → proceed
                DispatchQueue.main.async {
                    addModel()
                }
            } else {
                addModelNoInternet()
                DispatchQueue.main.async {
                    print("No internet connection, skipping insert into sharedData")
                }
            }
            monitor.cancel() // stop monitoring after first check
        }
        
        monitor.start(queue: queue)
    }
    private func isSnapshotStorageEmpty() -> Bool {
        guard !onAppModelDescription.isEmpty else { return true }

        guard let snapshots = try? JSONDecoder().decode(
            [ModelSnapshot].self,
            from: onAppModelDescription
        ) else {
            return true
        }

        return snapshots.isEmpty
    }

    private func addModel() {
        print("onAppModelDescription: \(onAppModelDescription)")
        if Auth.auth().currentUser == nil || Auth.auth().currentUser?.isAnonymous == true,
           isSnapshotStorageEmpty() {

            
            let baseName = "model".localized()

            let nowString = Model.creationFormatter.string(from: Date())

            // ✅ guest creator constant
            let creatorName = "mode123456789"

            let newModel = Model(
                name: baseName,
                description: "",
                keyword: "",
                creator: creatorName,
                rate: 0,
                creationDate: nowString,
                publishDate: "",
                justCreated: true,
                createdWithVib: false
            )

            // ✅ Save into AppStorage as JSON Data
            let snap = ModelSnapshot(
                name: newModel.name,
                description: newModel.description,
                keyword: newModel.keyword,
                creator: newModel.creator,
                rate: newModel.rate,
                creationDate: newModel.creationDate,
                publishDate: newModel.publishDate,
                justCreated: newModel.justCreated,
                createdWithVib: newModel.createdWithVib
            )
            print("YOO")
            onAppModelDescription = saveSnapshots([snap])

            // ✅ keep your existing runtime behavior
            selectedModel = nil
            selectedModel = newModel
            GameStarted = true
        } else if (Auth.auth().currentUser == nil || Auth.auth().currentUser?.isAnonymous == true)
                    && !isSnapshotStorageEmpty() {

            print("YAA")
            let baseName = "model".localized()
            var newName = baseName

            
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
            
            let nowString = formatter.string(from: Date())
            
            let creatorName: String = {
                guard
                    let user = Auth.auth().currentUser,
                    !user.isAnonymous
                else { return "" }

                
                let uid = user.uid
                
                return uid
            }()
            
            let newModel = Model(
                name: newName,
                description: "",
                keyword: "",
                creator: creatorName,
                rate: 0,
                creationDate: nowString,
                publishDate: "",
                justCreated: true,
                createdWithVib: false
            )
            selectedModel = nil
            selectedModel = newModel
            GameStarted = true
        } else {
            print("YAAAA")
            let baseName = "model".localized()
            var newName = baseName
            var suffixCount = 1
            
            
            while sharedData.personalModelsData.contains(where: { $0.name == newName }) {
                newName = baseName + "_\(suffixCount)"
                suffixCount += 1
            }
            
            
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
            
            let nowString = formatter.string(from: Date())
            
            let creatorName: String = {
                guard
                    let user = Auth.auth().currentUser,
                    !user.isAnonymous
                else { return "" }

                
                let uid = user.uid
                
                return uid
            }()
            
            let newModel = Model(
                name: newName,
                description: "",
                keyword: "",
                creator: creatorName,
                rate: 0,
                creationDate: nowString,
                publishDate: "",
                justCreated: true,
                createdWithVib: false
            )
            selectedModel = nil
            selectedModel = newModel
            GameStarted = true
            sharedData.personalModelsData.insert(newModel)
        }
    }
    
    private func loadSnapshots(from data: Data) -> [ModelSnapshot] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ModelSnapshot].self, from: data)) ?? []
    }

    private func saveSnapshots(_ snapshots: [ModelSnapshot]) -> Data {
        (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    
    private func addModelNoInternet() {
        let baseName = "model".localized()
        var newName = baseName
        var suffixCount = 1
        
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yy-MM-dd-HH-mm-ss"
        
        let nowString = formatter.string(from: Date())

        let newModel = Model(
            name: newName,
            description: "",
            keyword: "",
            creator: "",
            rate: 0,
            creationDate: nowString,
            publishDate: "",
            justCreated: true,
            createdWithVib: false
        )
        selectedModel = nil
        selectedModel = newModel
        GameStarted = true
    }


    func handleGoogleSignIn(completion: @escaping (Bool) -> Void) {
        guard !isSigningIn else { print("SignIn already in progress"); completion(false); return }
        isSigningIn = true
        defer { isSigningIn = false }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("No rootVC for sign-in")
            completion(false); return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("GID signIn error: \(error.localizedDescription)")
                completion(false); return
            }
            guard let result = result else { print("GID result nil"); completion(false); return }

            let gidUser = result.user
            guard let idToken = gidUser.idToken?.tokenString else {
                print("Missing idToken from GID")
                completion(false); return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: gidUser.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Firebase signIn error: \(error.localizedDescription)")
                    completion(false); return
                }
                guard let user = authResult?.user else { print("Firebase user nil"); completion(false); return }

                let email = user.email ?? ""
                let name  = user.displayName ?? ""

                print("Firebase signed in: uid=\(user.uid) email=\(email) name=\(name)")
                saveUserState(userName: name.isEmpty ? "No Name" : name,
                              userEmail: email.isEmpty ? "No Email" : email)
                isSignedIn = true

                // Use email as the user key (your current backend expectation)
                functions.doesUserExist(user: email) { exists in
                    if !exists {
                        functions.createUserFolder(user: email, userName: name) { success in
                            print("createUserFolder: \(success)")
                            completion(true)
                        }
                    } else {
                        completion(true)
                    }
                }
            }
        }
    }

    func saveUserState(userName: String?, userEmail: String?) {
        let defaults = UserDefaults.standard
        if let userName = userName, let userEmail = userEmail {
            defaults.setValue(userEmail, forKey: "GoogleUserEmail")
            defaults.setValue(userName, forKey: "GoogleUserName")
            defaults.setValue(true, forKey: "IsSignedIn")
        } else {
            defaults.removeObject(forKey: "GoogleUserEmail")
            defaults.removeObject(forKey: "GoogleUserName")
            defaults.setValue(false, forKey: "IsSignedIn")
        }
    }
}


private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
// MARK: - Lightweight text similarity helpers
private func tokens(from text: String) -> [String] {
    text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 1 } // drop 1-char noise
}

private func termFrequency(for tokens: [String]) -> [String: Double] {
    var tf: [String: Double] = [:]
    for t in tokens { tf[t, default: 0] += 1 }
    return tf
}

private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
    var dot = 0.0
    for (k, v) in a { if let w = b[k] { dot += v * w } }
    let normA = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
    let normB = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
    guard normA > 0, normB > 0 else { return 0 }
    return dot / (normA * normB)
}

private func charBigrams(_ s: String) -> Set<String> {
    let chars = Array(s.lowercased())
        .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    guard chars.count >= 2 else { return [] }
    var set = Set<String>()
    for i in 0..<(chars.count - 1) {
        set.insert(String(chars[i]) + String(chars[i + 1]))
    }
    return set
}

private func jaccard<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Double {
    let u = a.union(b).count
    guard u > 0 else { return 0 }
    let i = a.intersection(b).count
    return Double(i) / Double(u)
}

private func similarityForName(_ name: String, _ query: String) -> Double {
    let n = name.lowercased()
    let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return 0 }
    if n == q { return 1.0 }
    if n.contains(q) {
        // reward longer matches, capped at 1.0
        return min(1.0, 0.8 + Double(q.count) / Double(max(n.count, 1)) * 0.2)
    }
    return jaccard(charBigrams(n), charBigrams(q))
}


struct AvatarView: View {
    let selectedImage: UIImage?
    let H: CGFloat
    let selectedAccent: Color
    let dimmed: Bool          // 👈 NEW

    var body: some View {
        if let uiImage = selectedImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: H * 0.05, height: H * 0.05)              // adjust if needed
                .clipShape(Circle())
                .opacity(dimmed ? 0.55 : 1.0)
                .saturation(dimmed ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: dimmed)
        } else {
            ZStack {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: H * 0.025, height: H * 0.025) // 🔽 smaller glyph only
                    .foregroundStyle(selectedAccent)
            }
            .frame(width: H * 0.03, height: H * 0.03)          // ⭕ fixed outer size
            .padding(H * 0.01)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(dimmed ? 0.55 : 1.0)
            .saturation(dimmed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: dimmed)
        }
    }
}


struct ProfileMenuButton: View {
    var onSearchCompleted: () -> Void   // NEW
    var onShowForum: () -> Void   // NEW
    var onShowProfile: () -> Void   // NEW
    var onShowMessages: () -> Void   // NEW
    var onShowGame: () -> Void   // NEW
    var onShowStorage: () -> Void   // NEW
    var onShowScrolls: () -> Void   // NEW
    var onShowSettings: () -> Void   // NEW
    var selectedImage: UIImage?
    var H: CGFloat
    var selectedAccent: Color
    let userName: String
    @Binding var searchQuery: String
    @Binding var isOpen: Bool
    private let cardPadding: CGFloat = 16
    

    var body: some View {
        ZStack(alignment: .topLeading) {
            let toggleMenu = {
                withAnimation(.spring(response: 0.35,
                                      dampingFraction: 0.8,
                                      blendDuration: 0.1)) {
                    isOpen.toggle()
                }
            }

            if isOpen {
                ProfileDropdown(
                    onAvatarTap: toggleMenu,
                    onShowForum: onShowForum,
                    onSearch: {
                        onSearchCompleted()
                        withAnimation(.easeInOut) {
                            isOpen = false
                        }
                    },

                    onShowProfile: onShowProfile,
                    onShowMessages:  onShowMessages,
                    onShowGame: onShowGame,
                    onShowStorage: onShowStorage,
                    onShowScrolls: onShowScrolls,
                    onShowSettings: onShowSettings,
                    userName: userName,
                    searchQuery: $searchQuery
                )
                .padding(cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial.opacity(0.9)) // 👈 THIS is the key
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .offset(x: -cardPadding * 0.75, y: -cardPadding)
                .transition(
                    .scale(scale: 1.0, anchor: .topLeading)
                        .combined(with: .opacity)
                )
                .zIndex(1)

            }

            Button(action: toggleMenu) {
                AvatarView(
                    selectedImage: selectedImage,
                    H: H,
                    selectedAccent: selectedAccent,
                    dimmed: isOpen          // 👈 HERE
                )
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
        .padding(.top, 20)
    }
}

struct ProfileDropdown: View {
    var onAvatarTap: () -> Void
    var onShowForum: () -> Void
    var onSearch: () -> Void
    var onShowProfile: () -> Void
    var onShowMessages: () -> Void
    var onShowGame: () -> Void
    var onShowStorage: () -> Void
    var onShowScrolls: () -> Void
    var onShowSettings: () -> Void
    let userName: String
    @Binding var searchQuery: String
    @State private var isSearching = false
    @FocusState private var searchFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // HEADER – tap to close
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(.clear)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.headline)
                }
                
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onAvatarTap() }
            
            Divider()
            
            // MARK: SEARCH ROW
            // 🔍 Search Field Mode

            
            
        
            MenuRow(systemImage: "person.fill", customImageName: nil, title: "myspace".localized(), action: onShowProfile)
            //MenuRow(systemImage: "message.fill",  customImageName: nil, title: "conversations".localized(), action: onShowMessages)
            MenuRow(
                systemImage: nil,
                customImageName: "gesture_gesture_symbol",
                title: "scribble".localized(),
                action: onShowGame
            )

            MenuRow(systemImage: "app.fill", customImageName: nil, title: "storage".localized(), action: onShowStorage)
            MenuRow(systemImage: "nil", customImageName: "scrolls", title: "scrolls".localized(), action: onShowScrolls)
            MenuRow(systemImage: "gearshape.fill",
                    customImageName: nil,
                    title: "settings".localized(),
                    action: onShowSettings)
            /*
            Button(action: onUpdate) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Update App")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            */
        }
        .frame(width: UIScreen.main.bounds.width * 0.40)   // 👈 Set the dropdown width here
    }
}
struct MenuRow: View {
    let systemImage: String?
    let customImageName: String?
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

                // PRIORITY: custom image → fallback: SF Symbol
                if let custom = customImageName {
                    Image(custom)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .rotationEffect(custom == "scrolls" ? .degrees(270) : .degrees(0))
                } else if let system = systemImage {
                    Image(systemName: system)
                        .frame( width: 18, height:  18)
                }

                Text(title)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
