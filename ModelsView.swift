






import SwiftUI
import UIKit
import CoreHaptics
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import CoreImage
import CryptoKit
import Combine
import Firebase
import FirebaseDatabase
import GoogleSignIn
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide   = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        willChange
            .merge(with: willHide)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }

                if note.name == UIResponder.keyboardWillHideNotification {
                    self.height = 0
                    return
                }

                guard
                    let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let window = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                        .first
                else { return }

                // keyboard overlap relative to the screen bottom
                let bottomInset = window.safeAreaInsets.bottom
                let overlap = max(0, window.bounds.maxY - frame.minY - bottomInset)

                self.height = overlap
            }
            .store(in: &cancellables)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}

struct CachedStorageImage: View {
    let storageRef: StorageReference
    let identifier: String // stable id, e.g. "\(email)/Models/\(modelName)/ModelImage.jpg"
    var placeholder: AnyView = AnyView(Rectangle().fill(Color.clear))

    @State private var uiImage: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                placeholder
                    .overlay(ProgressView().opacity(isLoading ? 1 : 0))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        // 1) Disk first
        if let cached = ImageDiskCache.shared.load(identifier: identifier) {
            self.uiImage = cached
            return
        }
        // 2) Network (Storage) if no disk
        guard !isLoading else { return }
        isLoading = true

        storageRef.getData(maxSize: 6 * 1024 * 1024) { data, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data, let img = UIImage(data: data) else { return }
                ImageDiskCache.shared.save(img, identifier: identifier, quality: 0.9)
                self.uiImage = img
            }
        }
    }
}


final class ImageDiskCache {
    static let shared = ImageDiskCache()
    private init() {}
    
    private var dir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ModelImages", isDirectory: true)
    }
    
    private func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    private func key(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    func path(for identifier: String) -> URL {
        ensureDir()
        return dir.appendingPathComponent("\(key(identifier)).jpg")
    }
    
    func load(identifier: String) -> UIImage? {
        let url = path(for: identifier)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    func save(_ image: UIImage, identifier: String, quality: CGFloat = 0.8) {
        ensureDir()
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: path(for: identifier), options: .atomic)
    }
    func clearAll() {
        let d = dir
        let fm = FileManager.default
        // If the folder exists, delete it; then recreate empty.
        if fm.fileExists(atPath: d.path) {
            try? fm.removeItem(at: d)
        }
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
    }
    func remove(identifier: String) {
        try? FileManager.default.removeItem(at: path(for: identifier))
    }
}

private enum ActiveCover: Identifiable, Equatable {
    case modelCard(Model, publishPopup: Bool)

    var id: String {
        switch self {
        case .modelCard(let model, let publish):
            return "modelCard-\(model.id.uuidString)-\(publish)"
        }
    }
}


extension String {
    var canonName: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

extension Image {
    func asUIImage() -> UIImage? {
        let controller = UIHostingController(rootView: self.resizable())
        let view = controller.view

        let targetSize = CGSize(width: 100, height: 100) // small for color analysis
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            view?.drawHierarchy(in: view?.bounds ?? .zero, afterScreenUpdates: true)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
struct BottomSheetShape: Shape {
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))

        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))

        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

extension Color {
    func softenedBackgroundColor(for scheme: ColorScheme, amount: CGFloat = 0.9) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)

        let accentUI = UIColor(self).resolvedColor(with: traits)
        let baseUI = UIColor.systemBackground.resolvedColor(with: traits)

        let softened = accentUI.blended(with: baseUI, amount: amount)
        return Color(softened)
    }
}
private struct BottomInteractiveSheet<Content: View>: View {
    let expandedOffset: CGFloat
    let collapsedOffset: CGFloat
    @Binding var offset: CGFloat
    @Binding var dragStartOffset: CGFloat
    let content: Content
    init(
        expandedOffset: CGFloat,
        collapsedOffset: CGFloat,
        offset: Binding<CGFloat>,
        dragStartOffset: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self.expandedOffset = expandedOffset
        self.collapsedOffset = collapsedOffset
        self._offset = offset
        self._dragStartOffset = dragStartOffset
        self.content = content()
    }
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @Environment(\.colorScheme) private var scheme

    private var grabberFill: Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
    }

    private var grabberStroke: Color {
        scheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.10)
    }
    var body: some View {
        let sheetBG = selectedAccent.color.softenedBackgroundColor(for: scheme, amount: 0.9)

        GeometryReader { geo in
            let extraTail: CGFloat = geo.size.height * 1.0   // how much extra below the screen
            let contentHeight: CGFloat = geo.size.height      // keep blob area fixed

            VStack(spacing: 0) {
                // ✅ visible sheet (grabber + content) stays screen-height
                VStack(spacing: 0) {
                    Capsule()
                        .fill(grabberFill)
                        .overlay(Capsule().stroke(grabberStroke, lineWidth: 1))
                        .frame(width: 100, height: 10)
                        .padding(.top, 10)
                        .padding(.bottom, 10)

                    content
                        .frame(height: contentHeight) // ✅ prevents blob from growing
                        .frame(maxWidth: .infinity)
                }
                .background(sheetBG)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .clipShape(BottomSheetShape(radius: 22))
                .overlay(
                    BottomSheetShape(radius: 22)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())

                // ✅ invisible extra height so you never see the bottom edge
                Color.clear
                    .frame(height: extraTail)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .offset(y: offset)
        .simultaneousGesture(dragGesture)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: offset)
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if value.translation == .zero { dragStartOffset = offset }
                let proposed = dragStartOffset + value.translation.height

                // allow some extra beyond bounds while dragging
                let overshoot: CGFloat = 80
                offset = min(max(proposed, expandedOffset - overshoot),
                             collapsedOffset + overshoot)
            }
            .onEnded { value in
                let predicted = dragStartOffset + value.predictedEndTranslation.height
                let mid = (expandedOffset + collapsedOffset) / 2
                let target = predicted < mid ? expandedOffset : collapsedOffset

                offset = clamp(target)        // snaps back inside bounds
                dragStartOffset = offset
            }

    }


    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, expandedOffset), collapsedOffset)
    }
}


struct ModelsView: View {
    @EnvironmentObject var sharedData: SharedData
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @AppStorage("zoomSteps") private var zoomSteps: Int = 1
    let userEmail: String
    var modelHasBeenPublished: () -> Void = {}
    @State private var favouriteModels: [String: Model] = [:]
    @State private var isPressed = false
    private var zoomScale: CGFloat {
        1.0 + (CGFloat(zoomSteps) * 0.5)
    }
    @State private var GameStarted: Bool = false
    @State private var pressedModelID: UUID? = nil
    @State private var selectedModel: Model? = nil
    @State private var buttonWidth: CGFloat = 0.0
    @State private var selectedOption = "Models"
    @State private var sortNewestFirst = true
    @State private var showPublishPopup: Bool = false
    @State private var isFavouriteModel: Bool = false
    @State private var userIsAuthorized: Bool = false
    @State private var loadingWorkItem: DispatchWorkItem?
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("singleModelImageData") private var singleModelImageData: Data = Data()


    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var showLoading: Bool = false
    @State private var renamingModelID: UUID? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFocusedID: UUID?
    @State private var refreshID = UUID()
    
    @AppStorage("modelAliasMapJSON") private var modelAliasMapJSON: String = "{}"
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
    
    @State private var reloadKey = UUID()
    @State private var activeCover: ActiveCover?
    @State private var modelInReview: Bool = false
    @State private var modelHasBeenDeleted: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var isAdjustingImage = false
    @State private var isPhotoPickerPresented: Bool = false
    @State private var selectedModelForImage: Model? = nil
    @State private var stableWidth: CGFloat?
    @State private var disableScroll = false
    @State private var showBuildView = false
    @State private var descriptionExistsError: Bool = false
    @State private var nameIsEmptyError: Bool = false
    @State private var notFiveSeconds: Bool = false
    @State private var showSuccess = false
    @State private var tapDescriptionIsEmpty: Bool = false
    @State private var descriptionIsEmpty: Bool = false
    @State private var nameExistsError: Bool = false
    @State private var isPublishing: Bool = false
    @State private var tapsExistError: Bool = false
    @State private var selectedModelToPublish: Model? = nil
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @AppStorage("onAppModelDescription") private var onAppModelDescription: Data = Data()
    @AppStorage("tapData") private var tapDataJSON: Data = Data()
    
    let api = AIRespondsAPI()
    
    @State private var pendingBlobReset = false
    private func convertTomodel(from snap: ModelSnapshot) -> Model {
        Model(
            name: snap.name,
            description: snap.description,
            keyword: snap.keyword,
            creator: snap.creator,
            rate: snap.rate,
            creationDate: snap.creationDate,
            publishDate: snap.publishDate,
            justCreated: snap.justCreated,
            createdWithVib: snap.createdWithVib
        )
    }
    @State private var sheetOffset: CGFloat = UIScreen.main.bounds.height * 0.9
    @State private var sheetDragStartOffset: CGFloat = UIScreen.main.bounds.height * 0.9

    @State private var isSheetVisible: Bool = true       // keep it in hierarchy (or always true)
    @Environment(\.colorScheme) var scheme
    @State private var blobResetToken: Int = 0
    @State private var blobProgress: Float = 0
    @State private var isChatting: Bool = true
    @StateObject private var keyboard = KeyboardObserver()

    @State private var chatText: String = ""
    @State private var messages: [ChatMessage] = []

    @State private var blobDragOffset: CGSize = .zero
    @State private var activeTapID: String? = nil
    
    @State private var blobPosition: CGPoint? = nil
    
    @State private var blobPosX: Double = 0
    @State private var blobPosY: Double = 0
    
    @State private var blobSlidLeft = false
    private let defaults = UserDefaults.standard
    @State private var blobReturnTask: Task<Void, Never>?
    @State private var blobTapLocked = false
    @State private var aiRef: DatabaseReference?
    @State private var childAddedHandle: DatabaseHandle?
    @State private var childChangedHandle: DatabaseHandle?
    @State private var previousOpenProgress: CGFloat = 0
    private let appleHelper = AppleSignInHelper()
    @AppStorage("chatLimitReached") private var chatLimitReached: Bool = false
    func startListeningAI(limitLast: UInt = 100) {        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let base = FirebaseRefs.db.reference()
            .child("aiChat/conversations/\(uid)")
        
        let msgs = base.child("messages")
        
        aiRef = base
        
        let query = msgs
            .queryOrdered(byChild: "createdAt")
            .queryLimited(toLast: limitLast)
        
        childAddedHandle = query.observe(.childAdded) { snap in
            
            guard let dict = snap.value as? [String: Any] else { return }
            
            if let msg = decodeChatMessage(dict: dict, fallbackId: snap.key) {
                DispatchQueue.main.async {
                    if !messages.contains(where: { $0.id == msg.id }) {
                        messages.append(msg)
                    }
                }
            }
        }
        
        childChangedHandle = msgs.observe(.childChanged) { snap in
            
            guard
                let dict = snap.value as? [String: Any],
                let updated = decodeChatMessage(dict: dict, fallbackId: snap.key)
            else { return }
            
            DispatchQueue.main.async {
                if let idx = messages.firstIndex(where: { $0.id == updated.id }) {
                    messages[idx] = updated
                }
            }
        }
    }
    func stopListeningAI() {
        
        if let ref = aiRef {
            
            if let h = childAddedHandle {
                ref.child("messages").removeObserver(withHandle: h)
            }
            
            if let h = childChangedHandle {
                ref.child("messages").removeObserver(withHandle: h)
            }
        }
        
        childAddedHandle = nil
        childChangedHandle = nil
        aiRef = nil
    }
    func sendAIChatMessage(text: String,
                           messageType: String = "Text",
                           comments: String = "",
                           completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "Auth", code: -1)))
            return
        }
        
        let uid = user.uid
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Validation", code: -2)))
            return
        }
        
        let ref = FirebaseRefs.db.reference()
            .child("aiChat/conversations/\(uid)/messages")
            .childByAutoId()
        
        let msg: [String: Any] = [
            "userId": uid,
            "userName": "You",
            "messageType": messageType,
            "text": trimmed,
            "comments": comments,
            "createdAt": ServerValue.timestamp()
        ]
        
        ref.setValue(msg) { error, _ in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(ref.key ?? ""))
                }
            }
        }
    }
    @State private var chatViewRefreshID = UUID()
    @State private var isAiResponding = false
    @State private var blabalbla = false
    @State private var shouldDismissKeyboard = false
    @State private var isAiRespondingNow = false
    
    private let firstRunKey = "HasCompletedWelcomeGate"
    private let signedInKey = "IsSignedIn"
    @State private var showWelcomeGate = false
    private let appleEmailKey = "appleEmail"
    @State private var isSignedIn = false
    private func refreshPage() {
        refreshID = UUID()
    }
    @EnvironmentObject var functions: Functions
    @State private var handlingSigningOut: Bool = false
    var body: some View {
        
        ZStack {
            // ✅ EVERYTHING NORMAL
            Group {
                ZStack(alignment: .top) {
                    selectedAccent.color.opacity(0.08)
                        .ignoresSafeArea()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        GeometryReader { geo in
                            let spacing: CGFloat = 12
                            let minTapTarget: CGFloat = 44
                            
                            let clampedSteps = max(-2, min(2, zoomSteps))
                            let columnsCount = max(1, 3 - clampedSteps)
                            
                            let availableWidth: CGFloat = max(0, geo.size.width)
                            let totalSpacing: CGFloat = spacing * CGFloat(max(0, columnsCount - 1))
                            let rawCellWidth: CGFloat = (availableWidth - totalSpacing) / CGFloat(columnsCount)
                            let saneCellWidth: CGFloat = rawCellWidth.isFinite ? rawCellWidth : availableWidth
                            let cellWidth: CGFloat = max(minTapTarget, saneCellWidth.rounded(.down))
                            
                            let columns: [GridItem] = Array(
                                repeating: GridItem(.fixed(cellWidth), spacing: spacing, alignment: .top),
                                count: columnsCount
                            )
                            
                            let favouriteIDs = Set(sharedData.publishedFavModels.values.map(\.id))
                            
                            
                            let mergedModels: [Model] = {
                                // 1) load saved on-app models (if any) and put them FIRST
                                let storedSnaps = loadSnapshots(from: onAppModelDescription)
                                let storedModels = storedSnaps.map(convertTomodel(from:))
                                
                                // 2) de-dupe by something stable you control (name + creator is a good key)
                                func key(_ m: Model) -> String { "\(m.creator)|\(m.name)" }
                                
                                var seen = Set<String>()
                                var out: [Model] = []
                                
                                // prepend saved models
                                for m in storedModels where seen.insert(key(m)).inserted {
                                    out.append(m)
                                }
                                
                                // then favourites
                                for fav in sharedData.publishedFavModels.values where seen.insert(key(fav)).inserted {
                                    out.append(fav)
                                }
                                
                                // then personal
                                for m in sharedData.personalModelsData where seen.insert(key(m)).inserted {
                                    out.append(m)
                                }
                                
                                return out
                            }()
                            
                            
                            let sortedModels = mergedModels.sorted { a, b in
                                let aFav = favouriteIDs.contains(a.id)
                                let bFav = favouriteIDs.contains(b.id)
                                if aFav != bFav { return aFav && !bFav }
                                switch (a.creationDateValue, b.creationDateValue) {
                                case let (d0?, d1?): return sortNewestFirst ? (d0 > d1) : (d0 < d1)
                                case (nil, nil):      return a.name < b.name
                                case (_?, nil):       return true
                                case (nil, _?):       return false
                                }
                            }
                            
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                                    ForEach(sortedModels) { model in
                                        let isFav = favouriteIDs.contains(model.id)
                                        
                                        modelItemView(
                                            model: model,
                                            isFavourite: isFav,
                                            pressedModelID: pressedModelID,
                                            onPressChanged: { pressed in
                                                pressedModelID = pressed ? model.id : nil
                                            },
                                            onTap: {
                                                isFavouriteModel = isFav
                                                selectedModel = model
                                                print("AAA")
                                                showBuildView = true
                                            }
                                        )
                                        .frame(width: cellWidth, height: cellWidth)
                                        .aspectRatio(1, contentMode: .fit)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(
                                    GeometryReader { inner in
                                        Color.clear.preference(key: ContentHeightKey.self, value: inner.size.height)
                                    }
                                )
                                .padding(.bottom, 8)
                            }
                            .onPreferenceChange(ContentHeightKey.self) { contentH in
                                let viewportH = geo.size.height
                                disableScroll = contentH <= viewportH
                            }
                            .scrollDisabled(disableScroll)
                        }
                        .id(reloadKey)
                    }
                    .animation(.easeInOut(duration: 0.2), value: zoomScale)
                    .padding(8)
                }
                .fullScreenCover(isPresented: $showWelcomeGate) {
                    WelcomeGateView(
                        onContinueWithGmail: {
                            handleGoogleSignIn { success in
                                if success {
                                    defaults.set(true, forKey: firstRunKey)
                                    defaults.set(true, forKey: signedInKey)
                                    isSignedIn = true
                                    showWelcomeGate = false
                                    refreshPage()          // ✅ add
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
                                    refreshPage()          // ✅ add
                                }
                            }
                        }

                    )
                    .ignoresSafeArea()
                }
                .blur(radius: handlingSigningOut ? 6 : 0)
                .allowsHitTesting(!handlingSigningOut || !showWelcomeGate)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top) {
                    HStack(spacing: 12) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(selectedAccent.color)
                        }
                        
                        Text("storage".localized())
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Menu {
                            Button { sortNewestFirst.toggle() } label: {
                                Label(
                                    sortNewestFirst ? "sort_n_o".localized() : "sort_o_n".localized(),
                                    systemImage: sortNewestFirst ? "chevron.down" : "chevron.up"
                                )
                            }
                            
                            Button { if zoomSteps < 2 { zoomSteps += 1 } } label: {
                                Label("zoom_in".localized(), systemImage: "plus.magnifyingglass")
                            }
                            
                            Button { if zoomSteps > -2 { zoomSteps -= 1 } } label: {
                                Label("zoom_out".localized(), systemImage: "minus.magnifyingglass")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .tint(selectedAccent.color)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 18)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .background(Color(.systemBackground))
                    .overlay(Divider(), alignment: .bottom)
                    .zIndex(100)
                }
                
                
                NavigationLink(
                    destination: Group {
                        if let selectedModel {
                            
                            
                            let isPreview = sharedData.publishedModels[selectedModel.name] != nil && sharedData.publishedFavModels.values.contains { $0.name == selectedModel.name }
                            BuildView(
                                model: selectedModel,
                                isPreviewingModel: isPreview,
                                favouriteModels: sharedData.publishedFavModels,
                                isInSheet: false
                            )
                            .id(selectedModel.id)   // 👈 key line
                            
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: $showBuildView
                ) { EmptyView() }
                    .hidden()
                
                    .onChange(of: activeCover) { newValue in
                        if newValue == nil {
                            reloadFavouritesAndScreen()
                        }
                    }
                
                    .preferredColorScheme(selectedAppearance.colorScheme)
                    .sheet(isPresented: $isPhotoPickerPresented) {
                        PhotoPicker(
                            selectedImage: $selectedImage,
                            isAdjusting: $isAdjustingImage,
                            onSave: saveImageToAppStorage
                        )
                    }
                    .onAppear {
                        
                        loadingWorkItem?.cancel()
                        showLoading = false
                        
                        let wi = DispatchWorkItem {
                            DispatchQueue.main.async { showLoading = true }
                        }
                        loadingWorkItem = wi
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: wi)
                        
                        guard Auth.auth().currentUser?.isAnonymous == false else {
                            wi.cancel()
                            return
                        }
                        
                        fetchUserData()
                        personalModelsFunctions.fetchAllFavouriteModels { result in
                            DispatchQueue.main.async {
                                wi.cancel()
                                self.showLoading = false
                                
                                switch result {
                                case .success(let dict):
                                    self.favouriteModels = dict
                                    let keys = Array(dict.keys)
                                    sharedData.listOfFavModels = keys
                                    sharedData.publishedFavModels = dict
                                    userIsAuthorized = true
                                    
                                    if let email = Auth.auth().currentUser?.email {
                                        for modelName in keys {
                                            if sharedData.favouriteModelImageURLs[modelName] == nil {
                                                fetchFavouriteModelImageIfExists(for: modelName, email: email)
                                            }
                                        }
                                    }
                                    
                                case .failure:
                                    self.favouriteModels = [:]
                                    userIsAuthorized = false
                                }
                            }
                        }
                    }
            }
            
            // ✅ TOP-MOST LAYER: overlays EVERYTHING
            if isPublishing || showPublishPopup {
                ZStack {
                    // dim only for publish popup (optional)
                    if showPublishPopup {
                        Color.black.opacity(0.35).ignoresSafeArea()
                    }
                    
                    if isPublishing {
                        VStack(spacing: 12) {
                            if selectedDisplayMethod == .sphere {
                                RotatingSphereView(successToPublish: showSuccess)
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
                    
                    if showPublishPopup {
                        
                        VStack(spacing: 12) {
                            if nameExistsError {
                                errorRow("such_name_already_exists".localized())
                            }
                            if notFiveSeconds {
                                errorRow("not_five_seconds".localized())
                            }
                            if tapDescriptionIsEmpty {
                                errorRow("tap_descriptions_empty".localized())
                            }
                            if descriptionIsEmpty {
                                errorRow("description_is_empty".localized())
                            }
                        }
                    }
                }
                .zIndex(10_000)
                .allowsHitTesting(true) // blocks touches to everything underneath
            }
            
            
            
            
            GeometryReader { proxy in
                let expandedOffset: CGFloat = proxy.safeAreaInsets.top + 6
                let collapsedOffset: CGFloat = UIScreen.main.bounds.height * 0.9
                
                // 0 = collapsed, 1 = expanded
                let openProgress = max(
                    0,
                    min(1, 1 - (sheetOffset - expandedOffset) / (collapsedOffset - expandedOffset))
                )
                
                
                Color.clear
                    .onAppear {
                        sheetOffset = collapsedOffset
                        sheetDragStartOffset = collapsedOffset
                    }
                
            
            }

        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isChatting else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        .onAppear {
            if let currentUser = Auth.auth().currentUser {
                print("Current user ID: \(currentUser.uid)")
            } else {
                print("No user is currently signed in")
            }
            startListeningAI()
        }
        .onDisappear {
            stopListeningAI()
        }
        
        
    }
    
    func decodeChatMessage(dict: [String: Any], fallbackId: String) -> ChatMessage? {
        
        guard
            let userId = dict["userId"] as? String,
            let userName = dict["userName"] as? String,
            let messageType = dict["messageType"] as? String,
            let text = dict["text"] as? String,
            let createdAt = dict["createdAt"] as? TimeInterval
        else { return nil }
        
        let comments = dict["comments"] as? String ?? ""
        
        return ChatMessage(
            id: fallbackId,
            userId: userId,
            userName: userName,
            messageType: messageType,
            text: text,
            date: Date(timeIntervalSince1970: createdAt / 1000),
            comments: comments
        )
    }
    private func saveUserState(userName: String?, userEmail: String?) {
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
    private func loadSnapshots(from data: Data) -> [ModelSnapshot] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ModelSnapshot].self, from: data)) ?? []
    }

    private func saveSnapshots(_ snapshots: [ModelSnapshot]) -> Data {
        (try? JSONEncoder().encode(snapshots)) ?? Data()
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
    func handleGoogleSignIn(completion: @escaping (Bool) -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("No root view controller found!")
            completion(false)
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                print("Error during Google Sign-In: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let result = result else {
                print("User sign-in failed.")
                completion(false)
                return
            }

            let user = result.user
            guard let idToken = user.idToken?.tokenString else {
                print("Failed to retrieve Google ID token.")
                completion(false)
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Firebase authentication failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }

                guard let firebaseUser = authResult?.user else {
                    completion(false)
                    return
                }

                let userName = firebaseUser.displayName ?? ""
                let userEmail = firebaseUser.email ?? ""

                print("Successfully signed in with Firebase: \(userName.isEmpty ? "-" : userName), Email: \(userEmail.isEmpty ? "-" : userEmail)")

                saveUserState(
                    userName: userName.isEmpty ? "No Name" : userName,
                    userEmail: userEmail.isEmpty ? "No Email" : userEmail
                )
                isSignedIn = true

                // IMPORTANT: don't use "No Email" as a backend key
                guard !userEmail.isEmpty else {
                    print("[ERROR] Google/Firebase user has no email; cannot create folder keyed by email.")
                    completion(false)
                    return
                }

                functions.doesUserExist(user: userEmail) { doesExist in
                    if !doesExist {
                        // ✅ pass actual name into folder creation
                        functions.createUserFolder(user: userEmail, userName: userName) { success in
                            print(success ? "Folder creation succeeded." : "Folder creation failed.")
                            completion(true) // sign-in succeeded regardless of folder outcome
                        }
                    } else {
                        print("User already Exists")
                        completion(true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func errorRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
            Text(text)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 2)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder private func successRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
            Text(text)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 2)
        }
        .padding(.bottom, 2)
    }

    private func reloadFavouritesAndScreen() {
        personalModelsFunctions.fetchAllFavouriteModels { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let dict):
                    self.favouriteModels = dict
                    let keys = Array(dict.keys)
                    sharedData.listOfFavModels = keys
                    sharedData.publishedFavModels = dict
                case .failure:
                    self.favouriteModels = [:]
                }
                // Force GeometryReader/LazyVGrid to recompute
                self.reloadKey = UUID()
            }
        }
        // If you also need to refresh other user data, do it here:
        // fetchUserData()
    }
    private func saveImageToAppStorage(_ image: UIImage) {
        // Resize & compress FIRST (important for UserDefaults)
        let resized = image.resized(toMax: 1080)

        guard let data = resized.jpegDataCapped(maxBytes: 500 * 1024) else {
            print("❌ Failed to encode image")
            return
        }

        if !userIsAuthorized {
            // ✅ Save locally for unauthorized user
            singleModelImageData = data
            print("✅ Image saved to AppStorage (singleModelImageData)")
        
        } else {
            uploadTapImageToFirebase(image)
        }
    }
    
    private func uploadTapImageToFirebase(_ image: UIImage) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            return
        }

        let email = user.email ?? ""
        guard let modelName = selectedModelForImage?.name else { return }
        
        let storageRef = Storage.storage().reference()
            .child("Users").child(email)
            .child("Models").child(modelName)
            .child("ModelImage.jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000, immutable"
        
        // Resize first, then cap to ~500 KB
        let base = image.resized(toMax: 1080)
        guard let data = base.jpegDataCapped(maxBytes: 500 * 1024) else { return }
        
        // Write to disk cache immediately so UI never flashes empty
        let cacheID = "\(email)/Models/\(modelName)/ModelImage.jpg"
        if let preview = UIImage(data: data) {
            ImageDiskCache.shared.save(preview, identifier: cacheID, quality: 0.9)
        }
        
        storageRef.putData(data, metadata: metadata) { _, error in
            if let error = error {
                print("Upload error:", error.localizedDescription)
                return
            }
            DispatchQueue.main.async { self.reloadKey = UUID() }
            print("Image uploaded.")
        }
    }
    
    
    private func deleteModelImage() {
        guard let model = selectedModelForImage,
              let email = Auth.auth().currentUser?.email else { return }

        let storageRef = Storage.storage().reference()
            .child("Users").child(email)
            .child("Models").child(model.name)
            .child("ModelImage.jpg")

        storageRef.delete { error in
            DispatchQueue.main.async {
                // Even if remote delete fails, you can still clear local cache/state
                let personalID = "\(email)/Models/\(model.name)/ModelImage.jpg"
                ImageDiskCache.shared.remove(identifier: personalID)

                sharedData.modelImageURLs[model.name] = nil
                sharedData.imageAccentColors[model.name] = nil

                // If you surface the image in other maps, clear them as well
                sharedData.favouriteModelImageURLs[model.name] = nil
                sharedData.publishedModelImageURLs[model.name] = nil
                sharedData.publishedAccentColors[model.name] = nil

                reloadKey = UUID()
            }
        }
    }
    
    
    
    
    func fetchUserData() {
        
        personalModelsFunctions.fetchMyModels(for: userEmail) { result in
            switch result {
            case .success(let modelNames):
                
                for name in modelNames {
                    if sharedData.modelImageURLs[name] == nil {
                        if let email = Auth.auth().currentUser?.email {
                            fetchModelImageIfExists(for: name, email: email)
                        }
                    }
                    let alreadyLoaded = sharedData.personalModelsData.contains { $0.name == name }
                    guard !alreadyLoaded else { continue }
                    guard let uid = Auth.auth().currentUser?.uid else {
                        return
                    }
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
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func checkNameAndPublish() {
        // Reset all errors at the start
        nameExistsError = false
        tapsExistError = false
        nameIsEmptyError = false
        descriptionIsEmpty = false
        tapDescriptionIsEmpty = false
        notFiveSeconds = false

        guard let model = selectedModelToPublish else {
            isPublishing = false
            showPublishPopup = false
            return
        }

        let publishName = displayName(for: model)

        let trimmedName = publishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            isPublishing = false
            nameIsEmptyError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPublishPopup = false
            }
            return
        }

        let trimmedDescription = model.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            isPublishing = false
            descriptionIsEmpty = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPublishPopup = false
            }
            return
        }

        personalModelsFunctions.fetchConfigForMyModel(userEmail: userEmail, modelName: model.name) { result in
            switch result {
            case .success(let payload):
                // ✅ local copies only
                let tapDataLocal = payload.taps
                let commandNamesLocal = payload.names

                loadingWorkItem?.cancel()

                let hasAnyTapEntries: Bool = tapDataLocal.values.contains { innerDict in
                    innerDict.values.contains { entries in !entries.isEmpty }
                }

                guard hasAnyTapEntries else {
                    isPublishing = false
                    notFiveSeconds = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showPublishPopup = false
                    }
                    return
                }

                var totalM1M2Time: Double {
                    var sum: Double = 0
                    for inner in tapDataLocal.values {
                        for entries in inner.values {
                            for e in entries where e.entryType == "m1" || e.entryType == "m2" || e.entryType == "delay" || e.entryType == "m3" {
                                sum += e.value
                            }
                        }
                    }
                    return sum
                }

                guard totalM1M2Time > 5.0 else {
                    isPublishing = false
                    notFiveSeconds = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showPublishPopup = false
                    }
                    return
                }

                let hasInvalidCommandNames: Bool = tapDataLocal.contains { primaryKey, secondaryDict in
                    // commandNames must have this primary key
                    guard let namesForPrimary = commandNamesLocal[primaryKey] else {
                        return true
                    }

                    // every secondary key must exist and be non-empty
                    return secondaryDict.keys.contains { secondaryKey in
                        guard let name = namesForPrimary[secondaryKey] else {
                            return true
                        }
                        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                }

                if hasInvalidCommandNames {
                    isPublishing = false
                    tapDescriptionIsEmpty = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showPublishPopup = false
                    }
                    return
                }


                let language = currentAppLanguage()
                let firestore = Firestore.firestore()
                let docRef = firestore
                    .collection("Published")
                    .document("\(language)")

                docRef.getDocument { snapshot, error in
                    if let _ = error {
                        isPublishing = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showPublishPopup = false
                        }
                        return
                    }

                    let modelsMap = (snapshot?.data()?["models"] as? [String: Any]) ?? [:]
                    if modelsMap.keys.contains(trimmedName) {
                        isPublishing = false
                        nameExistsError = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showPublishPopup = false
                        }
                        return
                    }

                    print("trimmedName: \(trimmedName)")
                    publishFunctionality.publishModel(
                        named: model.name,
                        publishName: trimmedName,
                        publishDescription: trimmedDescription,
                        taps: tapDataLocal,
                        commandNames: commandNamesLocal
                    ) { result in
                        isPublishing = false
                        switch result {
                        case .success:
      
                            showSuccess = true
                            removeDisplayName(for: model)
                            sharedData.personalModelsData.remove(model)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showPublishPopup = false
                                isPublishing = false
                                showSuccess = false
                                showLoading = false
                                // 1) Clear on-disk cache
                                removeCachedImagesForModel(model.name)

                                // 2) Clear in-memory / URL state
                                removeDisplayName(for: model)
                                sharedData.personalModelsData.remove(model)
                                sharedData.imageAccentColors[model.name] = nil
                                sharedData.modelImageURLs[model.name] = nil

                            
                                
                                modelHasBeenPublished()
                                dismiss()
                                
                            }

                        case .failure:
                            print("")
                        }
                    }
                }

            case .failure:
                loadingWorkItem?.cancel()

                showLoading = false
            }
        }
    }

    private func fetchUsersModels() -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }
        
        // Filter to the current user's published models
        let mine = sharedData.publishedModels
            .values
            .filter { $0.creator == uid }
        
        // Return the count instead of populating models
        return mine.count
    }
 
    private func modelItemView(
        model: Model,
        isFavourite: Bool,
        pressedModelID: UUID?,
        onPressChanged: @escaping (Bool) -> Void,
        onTap: @escaping () -> Void
    ) -> some View {
        let existsInPublished   = sharedData.personalModelsData.contains(model)
        let existsInFavourites  = favouriteModels[model.name] != nil
        let existsInBoth        = existsInPublished && existsInFavourites
        let isOrphanedFavourite = isFavourite && !existsInBoth

        let isPressed  = (pressedModelID == model.id)
        let isEditing  = userIsAuthorized ? (renamingModelID == model.id && !isOrphanedFavourite) : (renamingModelID == model.id)
        let accent     = sharedData.imageAccentColors[model.name]
                         ?? (isOrphanedFavourite ? sharedData.publishedAccentColors[model.name] : nil)
                         ?? selectedAccent.color

        let hPad: CGFloat = 8
        let vSpacing: CGFloat = 6
        let labelHeight: CGFloat = 36
        
        @inline(__always)
        func ensurePublishedAccentIfFavourite() {
            guard isOrphanedFavourite else { return }

            // Already have an accent? done.
            if sharedData.publishedAccentColors[model.name] != nil { return }

            let cacheID = "PublishedModels/\(sharedData.appLanguage)/\(model.name)/ModelImage.jpg"

            // 1) Try disk cache first
            if let img = ImageDiskCache.shared.load(identifier: cacheID) {
                if let ui = (img.vibrantAverageColor ?? img.averageColor) {
                    sharedData.publishedAccentColors[model.name] = Color(ui)
                }
                return
            }

            // 2) Otherwise prime the URL so your image loader can fetch later
            let ref = Storage.storage().reference()
                .child("PublishedModels")
                .child("\(sharedData.appLanguage)")
                .child(model.name)
                .child("ModelImage.jpg")

            ref.downloadURL { url, error in
                guard let url else {
                    // ignore "object not found" silently
                    return
                }
                DispatchQueue.main.async {
                    sharedData.publishedModelImageURLs[model.name] = url
                }
            }
        }

        @ViewBuilder
        func tileImage(_ geo: GeometryProxy) -> some View {
            ZStack {
                
                if !userIsAuthorized,
                   model.creator == "mode123456789",
                   let ui = UIImage(data: singleModelImageData) {

                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .onAppear {
                            if sharedData.imageAccentColors[model.name] == nil {
                                let picked: UIColor? = ui.vibrantAverageColor ?? ui.averageColor
                                if let picked { sharedData.imageAccentColors[model.name] = Color(picked) }
                            }
                        }

                } else if let email = Auth.auth().currentUser?.email {
                    let storage = Storage.storage().reference()

                    // Decide path + cache id based on favourite flag
                    let (storageRef, id): (StorageReference, String) = {
                        if isOrphanedFavourite {
                            let ref = storage
                                .child("Users").child(email)
                                .child("FavouriteModels").child(model.name)
                                .child("ModelImage.jpg")
                            let id  = "\(email)/FavouriteModels/\(model.name)/ModelImage.jpg"
                            return (ref, id)
                        } else {
                            let ref = storage
                                .child("Users").child(email)
                                .child("Models").child(model.name)
                                .child("ModelImage.jpg")
                            let id  = "\(email)/Models/\(model.name)/ModelImage.jpg"
                            return (ref, id)
                        }
                    }()

                    CachedStorageImage(storageRef: storageRef, identifier: id)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .onAppear {
                            if sharedData.imageAccentColors[model.name] == nil,
                               let img = ImageDiskCache.shared.load(identifier: id) {
                                let picked: UIColor? = img.vibrantAverageColor ?? img.averageColor
                                if let picked { sharedData.imageAccentColors[model.name] = Color(picked) }
                            }
                        }

                    // Optional fallback to Published for favourites if their personal fav image is missing
                    if isOrphanedFavourite,
                       ImageDiskCache.shared.load(identifier: id) == nil {
                        let pubRef = storage
                            .child("PublishedModels")
                            .child("\(sharedData.appLanguage)")
                            .child(model.name)
                            .child("ModelImage.jpg")
                        let pubID = "PublishedModels/\(sharedData.appLanguage)/\(model.name)/ModelImage.jpg"

                        CachedStorageImage(storageRef: pubRef, identifier: pubID)
                            .clipped()
                            .onAppear {
                                if sharedData.publishedAccentColors[model.name] == nil,
                                   let img = ImageDiskCache.shared.load(identifier: pubID) {
                                    let picked: UIColor? = img.vibrantAverageColor ?? img.averageColor
                                    if let picked { sharedData.publishedAccentColors[model.name] = Color(picked) }
                                }
                            }
                    }
                } else {
                    
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                     

                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent, lineWidth: 1.2))
            .overlay(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.14)).opacity(isPressed ? 1 : 0))
            .shadow(color: Color.black.opacity(isPressed ? 0.08 : 0.12),
                    radius: isPressed ? 6 : 12, x: 0, y: isPressed ? 3 : 6)
        }


        func commitRename() {
            // block rename for favourites outright
            guard !isOrphanedFavourite else { renamingModelID = nil; return }
            guard renamingModelID == model.id else { return }

            let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldName = model.name

            guard !newName.isEmpty else { renameText = oldName; renamingModelID = nil; return }
            guard newName != displayName(for: model) else { renamingModelID = nil; return }

            setDisplayName(newName, for: model)
            renamingModelID = nil
        }

        return VStack(alignment: .leading, spacing: vSpacing) {
            // SQUARE TILE (fills column width)
            GeometryReader { geo in
                tileImage(geo)
                    .scaleEffect(isPressed ? 0.98 : 1) // press feedback only
                    .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isPressed)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let inside = geo.frame(in: .local).contains(value.location)
                                if inside, !isPressed { onPressChanged(true) }
                                if !inside, isPressed { onPressChanged(false) }
                            }
                            .onEnded { value in
                                let inside = geo.frame(in: .local).contains(value.location)
                                onPressChanged(false)
                                guard inside else { return }
                                
                                onTap()
                            
                            }
                    )
                    .allowsHitTesting(!isEditing)
                    .contextMenu {
                        if isOrphanedFavourite {
                            Label("fav_model_on_delete".localized(), systemImage: "star.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            if userIsAuthorized
                                ? sharedData.modelImageURLs[model.name] != nil
                                : !singleModelImageData.isEmpty {
                                Button(role: .destructive) {
                                    if !userIsAuthorized {
                                        sharedData.modelImageURLs.removeValue(forKey: model.name)
                                        sharedData.imageAccentColors.removeValue(forKey: model.name)
                                        singleModelImageData = Data()
                                    } else {
                                        sharedData.imageAccentColors.removeValue(forKey: model.name)
                                        sharedData.modelImageURLs.removeValue(forKey: model.name)
                                        selectedModelForImage = model
                                        deleteModelImage()
                                    }
                                } label: { Label("delete_image".localized(), systemImage: "trash") }
                            } else {
                                Button {
                                    if !userIsAuthorized {
                                        selectedModelForImage = model
                                        isPhotoPickerPresented = true
                                    } else {
                                        selectedModelForImage = model
                                        isPhotoPickerPresented = true
                                    }
                                } label: { Label("set_image".localized(), systemImage: "photo.fill") }
                            }
                            if userIsAuthorized {
                                Button {
                                    
                                    renamingModelID = model.id
                                    renameText = displayName(for: model)
                                    DispatchQueue.main.async { renameFocusedID = model.id }
                                    
                                } label: { Label("rename".localized(), systemImage: "pencil") }
                                    .disabled(!userIsAuthorized)
                                
                                Button {
                                    selectedModelToPublish = model
                                    showPublishPopup = true
                                    isPublishing = true
                                    showLoading = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        checkNameAndPublish()
                                    }
                                } label: {
                                    Label("publish".localized(), systemImage: "globe")
                                        .labelStyle(.titleAndIcon)
                                }
                                .disabled(fetchUsersModels() >= 5 || !userIsAuthorized)
                                .foregroundStyle(modelInReview ? .gray : .blue)
                            }
                            Button(role: .destructive) {
                                if !userIsAuthorized {
                                    sharedData.imageAccentColors.removeValue(forKey: model.name)
                                    sharedData.modelImageURLs.removeValue(forKey: model.name)
                                    singleModelImageData = Data()
                                    tapDataJSON = Data()
                                    onAppModelDescription = Data()
                                } else {
                                    personalModelsFunctions.deleteModel(modelName: model.name) { result in
                                        switch result {
                                        case .success:
                                            DispatchQueue.main.async {
                                                // 1) Clear on-disk cache
                                                removeCachedImagesForModel(model.name)
                                                sharedData.modelImageURLs.removeValue(forKey: model.name)

                                                // 2) Clear in-memory / URL state
                                                removeDisplayName(for: model)
                                                sharedData.personalModelsData.remove(model)
                                                sharedData.imageAccentColors.removeValue(forKey: model.name)

                                                
                                                reloadKey = UUID()
                                            }
                                            
                                        case .failure:
                                            reloadKey = UUID()
                                        }
                                    }
                                }
                            } label: { Label("delete".localized(), systemImage: "trash") }

                        }
                    }
            }
            .aspectRatio(1, contentMode: .fit)        // ← make the tile square by column width

            // LABEL
            Group {
                if isEditing {
                    TextField("", text: $renameText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.footnote.weight(.regular))
                        .tint(Color.primary)
                        .focused($renameFocusedID, equals: model.id)
                        .submitLabel(.return)
                        .onSubmit { commitRename() }
                        .onChange(of: renameText) { newValue in
                            if newValue.count > 20 { renameText = String(newValue.prefix(20)) }
                        }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if isOrphanedFavourite {
                            Button(action:  {
                                
                            }) {Image(systemName: "plus.circle.fill")
                                    .font(.system(size: UIScreen.main.bounds.width * 0.025))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(accent)
                                    .frame(width: UIScreen.main.bounds.width * 0.015, height: UIScreen.main.bounds.width * 0.015)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)
                        }
                    
                        Text(displayName(for: model))
                            .font(.footnote.weight(.regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .allowsHitTesting(false)
                    }
                
                }
            }
            .frame(maxWidth: .infinity, minHeight: labelHeight, alignment: .topLeading)
            .padding(.horizontal, hPad)
        }
        .frame(maxWidth: .infinity)   // let the grid dictate the width
        .onAppear {
            if isOrphanedFavourite { ensurePublishedAccentIfFavourite() }
        }
    }
    private func removeCachedImagesForModel(_ modelName: String) {
        guard let email = Auth.auth().currentUser?.email else { return }

        // These identifiers mirror how you save/load images elsewhere
        let personalID  = "\(email)/Models/\(modelName)/ModelImage.jpg"
        let favouriteID = "\(email)/FavouriteModels/\(modelName)/ModelImage.jpg"
        let publishedID = "PublishedModels/\(sharedData.appLanguage)/\(modelName)/ModelImage.jpg"

        ImageDiskCache.shared.remove(identifier: personalID)
        ImageDiskCache.shared.remove(identifier: favouriteID)
        ImageDiskCache.shared.remove(identifier: publishedID)
    }

    private func fetchModelImageIfExists(for modelName: String, email: String) {
        let ref = Storage.storage().reference()
            .child("Users")
            .child(email)
            .child("Models")
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
                    sharedData.modelImageURLs[modelName] = url
                }
            }
        }
    }
    private func fetchFavouriteModelImageIfExists(for modelName: String, email: String) {
        let ref = Storage.storage().reference()
            .child("Users")
            .child(email)
            .child("FavouriteModels")
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
                    sharedData.favouriteModelImageURLs[modelName] = url
                }
            }
        }
    }
    private func displayName(for model: Model) -> String {
        let favouriteIDs = Set(favouriteModels.values.map(\.id))
        if favouriteIDs.contains(model.id) { return model.name }
        let key = model.name.canonName
        if let alias = modelAliasMap[key], !alias.isEmpty { return alias }
        return model.name
    }
    @MainActor
    private func setDisplayName(_ alias: String, for model: Model) {
        var dict = modelAliasMap
        let key = model.name.canonName
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = trimmed
        }
        modelAliasMap = dict
    }
    @MainActor
    private func removeDisplayName(for model: Model) {
        var dict = modelAliasMap
        dict.removeValue(forKey: model.name.canonName)
        modelAliasMap = dict
    }

}

extension UIImage {
    /// Returns a more "vibrant" average color by sampling down to a grid,
    /// ignoring gray/black/white, and preferring higher saturation colors.
    var vibrantAverageColor: UIColor? {
        // Downscale to a small thumbnail for performance
        let targetSize = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumb = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let cgImage = thumb.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        guard let ctx = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var bestColor: UIColor?
        var bestScore: CGFloat = 0

        for x in 0..<width {
            for y in 0..<height {
                let idx = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = CGFloat(pixelData[idx]) / 255.0
                let g = CGFloat(pixelData[idx + 1]) / 255.0
                let b = CGFloat(pixelData[idx + 2]) / 255.0

                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
                UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)

                // Ignore nearly grayscale or too dark/light colors
                guard s > 0.2, v > 0.2, v < 0.95 else { continue }

                // Score by saturation × brightness
                let score = s * v
                if score > bestScore {
                    bestScore = score
                    bestColor = UIColor(red: r, green: g, blue: b, alpha: 1)
                }
            }
        }

        // Fallback: return plain average if no vibrant color found
        return bestColor ?? averageColor
    }

    /// Your old plain average (kept as backup)
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let context = CIContext(options: [.workingColorSpace: NSNull()])

        let parameters: [String: Any] = [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: parameters),
              let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

extension UIImage {
    func resized(toMax dimension: CGFloat) -> UIImage {
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        if aspectRatio > 1 {
            // Landscape
            newSize = CGSize(width: dimension, height: dimension / aspectRatio)
        } else {
            // Portrait
            newSize = CGSize(width: dimension * aspectRatio, height: dimension)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
extension UIImage {
    /// Produce JPEG data under `maxBytes` by lowering quality, and if needed, scaling down.
    func jpegDataCapped(maxBytes: Int,
                        initialQuality: CGFloat = 0.7,
                        minQuality: CGFloat = 0.4,
                        minDimension: CGFloat = 900) -> Data? {
        var workingImage = self
        var quality = initialQuality
        var data = workingImage.jpegData(compressionQuality: quality)
        var maxDim = max(size.width, size.height)

        // Keep compressing / downscaling until under the cap (or we hit our limits)
        while let d = data, d.count > maxBytes, (quality > minQuality || maxDim > minDimension) {
            if quality > minQuality {
                quality -= 0.1
            } else {
                maxDim = max(minDimension, maxDim * 0.85)
                workingImage = workingImage.resized(toMax: maxDim)
                quality = initialQuality
            }
            data = workingImage.jpegData(compressionQuality: quality)
        }
        return data
    }
}
