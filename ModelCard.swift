import SwiftUI
import UIKit
import CoreHaptics
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine
import CoreMotion
import NaturalLanguage

struct EditableRoundedTextEdit: View {
    @Binding var text: String
    @Binding var isFocusedExternal: Bool   // 👈 add this

    let model: Model
    var placeholder: String = "Type here…"
    var icon: String? = "square.and.pencil"
    var accentColor: Color = .accentColor
    var cornerRadius: CGFloat = 14
    var height: CGFloat = 60

    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @FocusState private var isFocusedInternal: Bool
    @AppStorage("onAppModelDescription") private var onAppModelDescription: Data = Data()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accentColor.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accentColor, lineWidth: 1.2))

            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .imageScale(.small)
                        .foregroundStyle(.primary)
                        .padding(.top, 6)
                }

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $text)
                        .tint(.primary)
                        .font(.caption2)
                        .focused($isFocusedInternal)
                        .scrollContentBackground(.hidden)
                        .padding(.vertical, 0)
                        .frame(maxHeight: .infinity)
                        .onChange(of: text) { newValue in
                            if newValue.count > 100 {
                                text = String(newValue.prefix(100))
                            }
                        }
                
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { isFocusedInternal = true }

        // 🔁 sync internal <-> external focus
        .onChange(of: isFocusedInternal) { isFocusedExternal = $0 }
        .onChange(of: isFocusedExternal) { isFocusedInternal = $0 }

        .onDisappear {
            guard model.description != text else { return }

            model.description = text

            if Auth.auth().currentUser?.isAnonymous == false {
                // ✅ Authenticated → update backend
                personalModelsFunctions.updateModelDescription(
                    modelName: model.name,
                    to: text
                ) { _ in }
            } else {
                // 🚫 Not authenticated → update snapshot ONLY for customized models
                guard model.creator == "mode123456789" else { return }

                upsertSnapshotDescription(
                    modelName: model.name,
                    newDescription: text
                )
            }
        }


    }
    private func loadSnapshots(from data: Data) -> [ModelSnapshot] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ModelSnapshot].self, from: data)) ?? []
    }

    private func saveSnapshots(_ snapshots: [ModelSnapshot]) -> Data {
        (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    private func upsertSnapshotDescription(modelName: String, newDescription: String) {
        var snaps = loadSnapshots(from: onAppModelDescription)

        if let idx = snaps.firstIndex(where: { $0.name == modelName }) {
            snaps[idx].description = newDescription
        } else {
            // If not found, you can either create a new snapshot,
            // or skip. Creating new is usually nicer:
            let snap = ModelSnapshot(
                name: model.name,
                description: newDescription,
                keyword: model.keyword,
                creator: model.creator,
                rate: model.rate,
                creationDate: model.creationDate,
                publishDate: model.publishDate,
                justCreated: model.justCreated,
                createdWithVib: model.createdWithVib
            )
            snaps.append(snap)
        }

        onAppModelDescription = saveSnapshots(snaps)
    }

}

extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide   = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        return MergeMany(willChange, willHide)
            .map { note -> CGFloat in
                guard
                    let info = note.userInfo,
                    let end  = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                else { return 0 }
                if end.origin.y >= UIScreen.main.bounds.height { return 0 }
                return max(0, UIScreen.main.bounds.height - end.origin.y)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

struct ModelCard: View {
    @EnvironmentObject var sharedData: SharedData
    let isPreviewingModel: Bool
    let nameWidth: CGFloat
    @Binding var isFavouriteModel: Bool
    @ObservedObject var model: Model
    @State private var showPublishPopup: Bool
    var closeToHome: (() -> Void)?
    init(
        isPreviewingModel: Bool = false,
        nameWidth: CGFloat = 0,
        isFavouriteModel: Binding<Bool>,
        model: Model,
        initialShowPublishPopup: Bool = false,
        closeToHome: (() -> Void)? = nil   
    ) {
        self.isPreviewingModel = isPreviewingModel
        self.nameWidth = nameWidth
        self._isFavouriteModel = isFavouriteModel
        self.model = model
        self._showPublishPopup = State(initialValue: initialShowPublishPopup)
        self.closeToHome = closeToHome
    }
    @State private var favouriteModels: [String: Model] = [:]
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirmation = false
    @State private var myEmail: String = ""
    @State private var gameStarted: Bool = false
    @State private var animate = false
    @FocusState private var isEditing: Bool
    @State private var modelName: String = ""
    @State private var justCreated: Bool = false
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    @EnvironmentObject var tapsFunctions: TapsFunctions
    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    private let blinkTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    @State private var initialModelName: String = ""
    @State private var showPlayView = false
    @State private var playViewShouldOpen = false
    @State private var MemoryNames: [Int: String] = [:]
    @State private var MemoryList: [String: [Int]] = [:]
    @State private var memoryUsersTaps: [Int: [Int: String]] = [:]
    @State private var memoryTapsConfigs: [Int: TAPSConfig?] = [:]
    @State private var expandedKeys: Set<Int> = []
    @State private var eyeTappedKey: Int? = nil
    @State private var selectedKeys: [Int: Set<Int> ] = [:]
    @State private var processedDragValues: [Int: Set<Int>] = [:]
    @State private var cellFrames: [Int: [Int: CGRect]] = [:]
    @State private var TapData: [Int: [Int: [TapEntry]]] = [:]
    @State private var modelIsEmpty: Bool = false
    @State private var UsersTaps: [Int: String] = [:]
    @State private var descriptionDraft = ""         
    @FocusState private var isFocused
    @State private var previewInSeconds: Double = 0.0
    @State private var previewSeconds: Double = 0.0
    @State private var isPlayingPreview = false
    @State private var playbackTimer: Timer? = nil
    @State private var playbackIsPlayed: Bool = false
    @State private var currentPlayers: [CHHapticAdvancedPatternPlayer] = []
    @State private var playbackTapEntries: [Double: [Int: [TapEntry]]] = [:]
    @State private var bucketDurations: [Double: Double] = [:]
    @State private var texts: [Int: String] = [:]
    @State private var orderedKeys: [Double] = []
    @State private var nextBucketIndex = 0
    private let epsilon: Double = 0.0005
    @State private var commandNames: [Int: [Int: String]] = [:]
    @FocusState private var isDescFocused: Bool
    @State private var processingIsFavourite: Bool = false
    private let allowedCharsRegex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_]*$"#)
    @State private var showNameInvalidWarning: Bool = false
    @State private var userName: String = ""
    @State private var userID: String = ""
    @State private var publishName: String = ""
    @State private var publishDescription: String = ""
    @State private var nameExistsError: Bool = false
    @State private var isPublishing: Bool = false
    @State private var tapsExistError: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var selectedUser: SelectedUser? = nil
    @State private var isPresented: Bool = false
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("modelAliasMapJSON") private var modelAliasMapJSON: String = "{}"
    @AppStorage("likingModelCooldownUntil") private var likingCooldownUntil: Double = 0   
    @AppStorage("likingModelSpamCount")     private var likingSpamCount: Int = 0
    @AppStorage("likingModelLastTap")       private var likingLastTap: Double = 0
    @AppStorage("onAppModelDescription") private var onAppModelDescription: Data = Data()
    @State private var showLikeCooldownAlert = false
    @State private var likeCooldownMessage   = ""
    @FocusState private var focusedKey: String?
    private let likeSpamThreshold  = 10                  
    private let likeCooldownWindow: TimeInterval = 30*60 
    private let likeSpamWindow:    TimeInterval = 60
    @State private var previousCommandNames: [Int: [Int: String]] = [:]        // key -> custom name
    private var aliasMap: [String:String] {
        (try? JSONDecoder().decode([String:String].self, from: Data(modelAliasMapJSON.utf8))) ?? [:]
    }
    private var displayName: String {
        if let alias = aliasMap[model.name.canonName], !alias.isEmpty {
            return alias
        }
        return model.name
    }
    @State private var bioFocused = false

    @State private var descriptionExistsError: Bool = false
    @State private var nameIsEmptyError: Bool = false
    @State private var notFiveSeconds: Bool = false
    @State private var userEmail: String = ""
    @State private var selection = 0
    @State private var loadingWorkItem: DispatchWorkItem?
    @State private var showLoading: Bool = false
    @State private var yourModelInReview: Bool = false
    @State private var refreshID = UUID()
    @State private var showVibInfo = false
    @State private var showSuccess = false
    @State private var tapDescriptionIsEmpty: Bool = false
    
    @State private var isPillPressing = false
    @State private var addedToFav = false
    @State private var pillFillProgress: CGFloat = 0
    @State private var showFavToast = false
    @AppStorage("tapData") private var tapDataJSON: Data = Data()
    @AppStorage("lastUsedEntries") private var lastUsedEntriesData: Data = Data()
    
    @State private var spiralBaseRotation: [Int: Angle] = [:]

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
    @State private var showReportMenu = false
    @State private var modelID: Int = 0
    @Environment(\.colorScheme) private var systemColorScheme

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
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @State private var activeKey: Int? = nil
    @FocusState private var editorFocused: Bool
    @Namespace private var editorNS
    @State private var showEditor = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var descriptionIsEmpty: Bool = false
    @State private var reportTarget: Model? = nil
    @State private var wasFavouriteModel: Bool = false
    
    @StateObject private var deviceMotion = DeviceMotionManager.shared
    @State private var spiralTotalRotation: Angle = .zero
    @State private var spiralDragRotation: Angle = .zero
    @State private var spiralDragStartAngle: Angle? = nil
    @State private var activeSpiralKey: Int?                  // the key currently in full-screen
    @State private var deviceBaseYaw: Double? = nil
    @State private var deviceYawRotation: Angle = .zero
    @State private var fillWorkItem: DispatchWorkItem?
    @State private var showBrokenHeart = false
    @State private var isFavouriteModel2 = false
    @State private var isPressingPill = false

    var body: some View {
        GeometryReader { geometry in
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
            let overlayBackgroundColor: Color = accent.opacity(0.08)
            let isDisabled = isPreviewingModel || isFavouriteModel
            let canUnlike = isFavouriteModel
            let canLike   = isPreviewingModel && !isFavouriteModel
            ZStack {

                
                let toolbarHeight: CGFloat = UIScreen.main.bounds.height * 0.1
                let isDisabled = isPreviewingModel || isFavouriteModel
                
                let keys = TapData.keys.sorted()
                
                
                
                let secondaryKeysByPrimary: [Int: [Int]] = keys.reduce(into: [:]) { result, primaryKey in
                    result[primaryKey] = TapData[primaryKey]?.keys.sorted() ?? []
                }
                
                let totalFavourites = favouriteModels.count
                let totalPersonal   = sharedData.personalModelsData.count
                let totalCombined   = totalFavourites + totalPersonal
                let limit           = 50
                let overLimit       = totalCombined >= limit
                
                var tapDuration: Double {
                    var sum: Double = 0
                    for inner in TapData.values {
                        for entries in inner.values {
                            for e in entries where e.entryType == "m1" || e.entryType == "m2" || e.entryType == "m3" || e.entryType == "delay" {
                                sum += e.value
                            }
                        }
                    }
                    return sum
                }
                let secondsRounded = Int(round(tapDuration))
                let minutesUp = Int(ceil(tapDuration / 60))
                

                let descriptionPlaceholder = "description".localized().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                var currentRate: Int {
                    sharedData.publishedModels[model.name]?.rate ?? model.rate
                }

                let circleView =
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.primary,
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
                .frame(width: 14, height: 14)
                .contentShape(Circle())
                .offset(.zero)
                .scaleEffect(1.0)
                
                overlayBackgroundColor
                    .ignoresSafeArea() 
                // ✅ Tap anywhere to close editor
                if showEditor || bioFocused{
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                showEditor = false
                                editorFocused = false
                                activeKey = nil
                                activeSpiralKey = nil
                                bioFocused = false
                            }
                        }
                
                }
                VStack(spacing: 0) {


                    // ✅ YOUR EXISTING CONTENT

                    VStack(alignment: .leading, spacing: 20) {
                        
                        Button(action: {
                            if !userID.isEmpty {
                                selectedUser = SelectedUser(id: userID)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person")
                                    .imageScale(.small)
                                    .foregroundStyle(Color.primary)
                                
                                
                                Text("created_by".localized())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                
                                Circle()
                                    .foregroundStyle(Color.gray) 
                                    .frame(width: 3, height: 3)
                                    .opacity(0.6)
                                
                                Text(userID == model.creator || userName.isEmpty
                                     ? "\("you_doubleclosing".localized()) \(userName)"
                                     : "\(userName)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.gray) 
                                .lineLimit(1)
                                
                                
                            }
                            .padding(.horizontal, 12) 
                            .padding(.vertical, 7)
                        }
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().fill(accent.opacity(0.18)))
                        .overlay(
                            Capsule().strokeBorder(accent, lineWidth: 1.2)
                        )
                        .contentShape(Capsule())
                        .allowsHitTesting(true)      
                        .zIndex(1000)          
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                
                                if !model.creator.isEmpty && !userName.isEmpty && userID != model.creator{
                                    
                                    
                                    selectedUser = SelectedUser(id: model.creator)
                                }
                            }
                        )
                        
                        HStack {
                            FuturisticChipTime(
                                label: isPreviewingModel || isFavouriteModel ? "published".localized() : "created".localized(),
                                systemImage: "clock",
                                selected: true,
                                accent: accent,
                                valueText: isPreviewingModel || isFavouriteModel ? model.publishDate : model.creationRelative
                            )
                            Spacer()
                        }
                        Button(action: {
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.batteryblock")
                                    .imageScale(.small)
                                    .foregroundStyle(Color.primary)
                                
                                
                                Text("duration".localized())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                
                                Circle()
                                    .foregroundStyle(Color.gray)
                                    .frame(width: 3, height: 3)
                                    .opacity(0.6)


                                Text(
                                    tapDuration < 60
                                        ? "\(secondsRounded) " + (secondsRounded == 1 ? "second".localized() : "seconds".localized())
                                        : "\(minutesUp) " + (minutesUp == 1 ? "minute".localized() : "minutes".localized())
                                )
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.gray)
                                .lineLimit(1)

                                
                                
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().fill(accent.opacity(0.18)))
                        .overlay(
                            Capsule().strokeBorder(accent, lineWidth: 1.2)
                        )
                        .contentShape(Capsule())
                        
                        Button(action: {
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(Color.primary)
                                
                                
                                Text("rating".localized())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                
                                Circle()
                                    .foregroundStyle(Color.gray)
                                    .frame(width: 3, height: 3)
                                    .opacity(0.6)


                                Text(
                                    userName.isEmpty
                                    ? "not_published".localized()
                                    : String(Int(currentRate))
                                )


                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.gray)
                                .lineLimit(1)

                                
                                
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().fill(accent.opacity(0.18)))
                        .overlay(
                            Capsule().strokeBorder(accent, lineWidth: 1.2)
                        )
                        .contentShape(Capsule())
                        
                        
                        Button(action: {
                        }) {
                            HStack(spacing: 8) {
                                circleView
                                
                                
                                Text("taps".localized())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                
                                Circle()
                                    .foregroundStyle(Color.gray)
                                    .frame(width: 3, height: 3)
                                    .opacity(0.6)
                                
                                Text("\(keys.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                                                
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().fill(accent.opacity(0.18)))
                        .overlay(
                            Capsule().strokeBorder(accent, lineWidth: 1.2)
                        )
                        .contentShape(Capsule())
                        EditableRoundedTextEdit(
                            text: $publishDescription,
                            isFocusedExternal: $bioFocused,     // 👈 pass binding
                            model: model,
                            placeholder: "",
                            icon: "",
                            accentColor: accent,
                            cornerRadius: 14,
                            height: UIScreen.main.bounds.height * 0.15
                        )
                        .padding(.horizontal, 1)   // 👈 keeps left & right inside screen
                        .allowsHitTesting(!(isPreviewingModel || isFavouriteModel || showEditor))
                        
                        SoftNeonDivider(accent: accent)
                            .padding(.vertical, 0) // ← override any internal vertical padding
                        
                        VStack(spacing: 0) {
                            ZStack {
                                ZStack(alignment: .leading) {
                                    TabView(selection: $selection) {
                                        ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                                            GeometryReader { geo in
                                                let secondaryKeys = secondaryKeysByPrimary[key] ?? []
                                                let diameter = geo.size.width * 0.20
                                                let side = 50.0
                                                let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                                                let editorHeight = lineHeight * 4 + 20
                                                let overlap: CGFloat  = geo.size.width * 0.03
                                                if secondaryKeys.count == 1 {
                                                    HStack(spacing: 16) {
                                                        Button {
                                                            if !isPreviewingModel && !isFavouriteModel {
                                                                showEditor = true   // 👈 trigger the editor
                                                            }
                                                        } label: {
                                                            SpiralTextInCircle(
                                                                text: commandNames[key]?[0] ?? "",
                                                                accent: accent
                                                            )
                                                        }
                                                        .buttonStyle(PlainButtonStyle()) // avoid default blue highlight
                                                        .padding()
                                                        
                                                        
                                                    }
                                                    .padding(.leading, side + diameter / 2)
                                                    .padding(.trailing, side)
                                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                                                    .rotationEffect(.degrees(90))
                                                    
                                                } else {
                                                    ZStack {
                                                        HStack(spacing: -overlap) {
                                                            ForEach(secondaryKeys, id: \.self) { secondaryKey in
                                                                Circle()
                                                                    .fill(accent.opacity(0.16))
                                                                    .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: 1.2))
                                                                    .frame(width: diameter, height: diameter)
                                                            }
                                                        }
                                                        .padding(.leading, side)
                                                        .padding(.trailing, side)
                                                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                                                        .rotationEffect(.degrees(90))
                                                    }
                                                }
                                            }
                                            .frame(width: UIScreen.main.bounds.width * 1.0, height: UIScreen.main.bounds.height * 0.30)
                                            .tag(idx)
                                        }
                                    }
                                    .tabViewStyle(.page(indexDisplayMode: .never))
                                    .highPriorityGesture(TapGesture(), including: .subviews)
                                    .rotationEffect(.degrees(-90))
                                    .frame(maxWidth: .infinity)
                                    .opacity(keyboardHeight == 0 ? 1 : 0)
                                    .allowsHitTesting(keyboardHeight == 0)
                                    
                                    
                                    PageDots(keys: keys, current: $selection, accent: accent)
                                        .padding(.leading, 10)
                                        .zIndex(10)
                                    
                                    
                                }
                                
                                .clipped()                       // <- hard clip to the ZStack bounds
       
                                .onTapGesture {
                                    if isDisabled {
                                        return
                                    } else {
                                        isDescFocused = true
                                        
                                    }
                                }
                                .overlay(alignment: .center) {
                                    let diameter = UIScreen.main.bounds.width * 0.7
                                    let side = 50.0
                                    
                                    // Use the same key you use for the spiral
                                    // Prefer activeSpiralKey if it's set, otherwise fall back to selection
                                    let keyFromSelection = keys.indices.contains(selection) ? keys[selection] : nil
                                    let key = activeSpiralKey ?? keyFromSelection
                                    
                                    // Same base rotation you use above:
                                    let baseRotation = key.flatMap { spiralBaseRotation[$0] } ?? .zero
                                    let totalRotation = baseRotation + spiralDragRotation + deviceYawRotation
                                    
                                    if let key {
                                        HStack(spacing: 16) {
                                            SpiralTextEditor(
                                                text: Binding(
                                                    get: {
                                                        commandNames[key]?[0] ?? ""
                                                    },
                                                    set: { newValue in
                                                        let capped = String(newValue.prefix(50)) // limit to 50 characters
                                                        if commandNames[key] == nil { commandNames[key] = [:] }
                                                        commandNames[key]?[0] = capped
                                                        
#if os(iOS)
                                                        if capped != newValue {
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                        }
#endif
                                                    }
                                                ),
                                                showEditor: $showEditor,
                                                accent: accent
                                            )
                                            .padding()
                                        }
                                        .frame(width: diameter, height: diameter, alignment: .center)
                                        .opacity(showEditor && keyboardHeight > 0 ? 1 : 0)
                                        .allowsHitTesting(keyboardHeight > 0 && showEditor)
                                        .offset(y: keyboardHeight == 0 ? 0 : -keyboardHeight - 8)
                                        .animation(.easeOut(duration: 0.22), value: keyboardHeight)
                                        .onReceive(Publishers.keyboardHeight) { keyboardHeight = $0 }
                                        .onAppear { DispatchQueue.main.async { editorFocused = true } }
                                        .onChange(of: editorFocused) { focused in
                                            if !focused {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                                    activeKey = nil     // collapse back into the circle
                                                }
                                            }
                                        }
                                        // 🔁 Apply the SAME rotation as the spiral:
                                        .rotationEffect(totalRotation)
                                        
                                    } else {
                                        EmptyView()
                                    }
                                }
                                
                                .onAppear {
                                    descriptionDraft = model.description
                                }
                                .onChange(of: isDescFocused) { focused in
                                    if !focused {
                                        let trimmed = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed != model.description {
                                            model.description = trimmed
                                            descriptionDraft = trimmed
                                        }
                                    }
                                }
                            }
                            .ignoresSafeArea(.keyboard)
                        }
    
                        Spacer()
                    }
                }
                .padding(.top, 10)   // ✅ this moves the entries down



            }
            .safeAreaInset(edge: .top, spacing: 0) {

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
                .contentShape(     RoundedRectangle(cornerRadius: 10, style: .continuous))

                // tap = details
                .onTapGesture {
                    dismiss()
                }

                // hold = add/remove fav with 0.5s delay + 1s fill

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
                            if
                                let user = Auth.auth().currentUser,
                                !user.isAnonymous
                            {

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




            .onDisappear {
   
                if !myEmail.isEmpty && !commandNames.isEmpty {
                    print("commandNames: \(commandNames)")
                    tapsFunctions.saveCommandNamesForMyModel(
                        userEmail: myEmail,
                        ModelName: model.name,
                        commandNames: commandNames
                    ) { result in
                        switch result {
                        case .success:
                            print("Command names saved successfully.")
                        case .failure(let error):
                            print("Failed to save command names: \(error.localizedDescription)")
                        }
                    }
                } else if myEmail.isEmpty && !commandNames.isEmpty {
                    upsertSnapshotCommandNames(modelName: model.name, newCommandNames: commandNames)
                }
            }


            .id(refreshID)
            .task(id: refreshID) {
                loadData()   
            }
            .preferredColorScheme(selectedAppearance.colorScheme) 
            .overlay(alignment: .bottom) {
                if let target = reportTarget {
                    RollActionSheet(
                        model: target,
                        modelID: modelID,
                        accent: selectedAccent.color,
                        isInModelCard: true,
                        onReportModel: {
                            forumFunctionality.sendUserReport(
                                forumTag: "model",
                                reason: model.name,
                                reportedUserUID: model.creator
                            ) { result in
                                switch result {
                                case .success(let id): print("Report filed: \(id)")
                                case .failure(let error): print("Report failed: \(error.localizedDescription)")
                                }
                            }
                            reportTarget = nil
                        },
                        onCancel: {
                            reportTarget = nil
                        },
                        onModelOpen: {
                            
                        }
                    )
                    .zIndex(100)
                }
            }
            
            .blur(radius: showPublishPopup || isPublishing ? 1 : 0)
            .allowsHitTesting(!showPublishPopup && !isPublishing)
            .ignoresSafeArea(.keyboard)
            .overlay(
                Group {
                    
                    if showFavToast {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)                 // “see through” system material
                            .frame(width: 140, height: 140)
                            .overlay(
                                Image(systemName: showBrokenHeart ? "minus" : "plus")
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(showBrokenHeart ? .secondary : .primary)
                            )
                            .shadow(radius: 10)
                            .transition(.scale.combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                
                    if showPublishPopup {
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            VStack(spacing: 12) {
                                if nameExistsError {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill") // ⬅️ Filled X icon
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                        Text("such_name_already_exists".localized())
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.red)
                                            .multilineTextAlignment(.center)
                                            .padding(.bottom, 2)
                                    }
                                    .padding(.bottom, 2)
                                }
                                
                                
                                if notFiveSeconds {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill") // ⬅️ Filled X icon
                                            .font(.callout)
                                            .foregroundStyle(.red)

                                        Text("not_five_seconds".localized())
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.red)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.bottom, 2)
                                }
                                
                                if tapDescriptionIsEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.callout)
                                            .foregroundStyle(.red)

                                        Text("tap_descriptions_empty".localized())
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.red)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.bottom, 2)
                                }
                                if descriptionIsEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.callout)
                                            .foregroundStyle(.red)

                                        Text("description_is_empty".localized())
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.red)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.bottom, 2)
                                }
                                if showSuccess {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")   // ✅ green tick
                                            .font(.callout)
                                            .foregroundStyle(.green)


                                        Text("success_publish".localized())
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.green)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.bottom, 2)
                                }
                            

                            }
                            
                        }
                    }
                    
                    if showLoading && !isPublishing {
                        ZStack {
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
                            VStack(spacing: 12) {
                                if selectedDisplayMethod == .sphere {
                                    RotatingSphereView(accent: accent)
                                        .frame(
                                            width: UIScreen.main.bounds.width * 0.8,
                                            height: UIScreen.main.bounds.width * 0.8
                                        )
                                } else {
                                    PlainGridAnimationView(accent: accent)
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
                    }
                
                    if isPublishing {
                        ZStack {
        
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
                            VStack(spacing: 12) {
                                if selectedDisplayMethod == .sphere {
                                    RotatingSphereView(accent: accent)
                                        .frame(
                                            width: UIScreen.main.bounds.width * 0.8,
                                            height: UIScreen.main.bounds.width * 0.8
                                        )
                                } else {
                                    PlainGridAnimationView(accent: accent)
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
                    
                }
                
            )

            .alert("cooldown".localized(), isPresented: $showLikeCooldownAlert) {
                Button("ok".localized(), role: .cancel) { }
            } message: {
                Text(likeCooldownMessage)
            }
            
            .sheet(item: $selectedUser) { user in
                OtherPersonAccountView(publishedModels: sharedData.publishedModels, favouriteModels: favouriteModels,  userID: model.creator)
            }

            .onChange(of: gameStarted) { newValue in
                if !newValue {
                    refreshID = UUID()
                }
            }
            .onAppear {
                print("model.description: \(model.description)")
                pillFillProgress = isFavouriteModel ? 1.0 : 0.0
                wasFavouriteModel = isPreviewingModel
                isFavouriteModel2 = isFavouriteModel
                ensurePublishedAccentIfPreviewing()
                if showPublishPopup {
                    isPublishing = true
                }
                print("GUUGGA")
                if let key = sharedData.GlobalModelsData.first(where: { $0.value == model.name })?.key {
                    modelID = key
                }
                print("GGAGA")
                loadingWorkItem?.cancel()
                showLoading = false
                let wi = DispatchWorkItem {
                    DispatchQueue.main.async { if !model.justCreated {showLoading = true } }
                }
                loadingWorkItem = wi
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: wi)
                
                if
                    let user = Auth.auth().currentUser,
                    !user.isAnonymous
                {
                    
                    let uid = user.uid
                    let email = user.email ?? ""
                    userID = uid
                    userEmail = email
                    let defaults = UserDefaults.standard
                    defaults.setValue(email, forKey: "GoogleUserEmail")
                    defaults.setValue(true, forKey: "IsSignedIn")
                    myEmail = UserDefaults.standard.string(forKey: "GoogleUserEmail") ?? ""
                }
                if let name = sharedData.ALLUSERNAMES[model.creator]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    userName = name
                }
                
                
                if !isPreviewingModel && !isFavouriteModel{
                    if Auth.auth().currentUser == nil || Auth.auth().currentUser?.isAnonymous == true {
                        
                        if model.creator == "mode123456789" && !tapDataJSON.isEmpty {
                            
                            let decoder = JSONDecoder()
                            
                            if let decoded = try? decoder.decode(
                                [String: [Int: [Int: [TapEntry]]]].self,
                                from: tapDataJSON
                            ) {
                                // If this model exists as a key, use it
                                if let modelData = decoded[model.name] {
                                    TapData = modelData
                                } else {
                                    // Otherwise, fall back to the FIRST available entry (guest/default case)
                                    TapData = decoded.values.first ?? [:]
                                }
                            }
                            
                            TapData.removeValue(forKey: 0)
                            print("TRYING TO LOAD")
                            commandNames = loadCommandNamesFromSnapshot(modelName: model.name)
                            
                            wi.cancel()
                            showLoading = false
                        } else {
                            print("creator: \(model.creator)")
                            print("NO DATA: \(tapDataJSON)")
                        }
                    } else {
                        personalModelsFunctions.fetchConfigForMyModel(userEmail: myEmail, modelName: model.name) { result in
                            switch result {
                            case .success(let payload):
                                TapData = payload.taps
                                commandNames = payload.names
                                print("commandNames: \(commandNames)")
                                previousCommandNames = payload.names
                                wi.cancel()
                                showLoading = false
                                if showPublishPopup {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        checkNameAndPublish()
                                    }
                                }
                            case .failure(let error):
                                wi.cancel()
                                showLoading = false
                                
                            }
                        }
                    }
                } else {
                    publishFunctionality.fetchConfigForPublishedModel(modelName: model.name) { result in
                        switch result {
                        case .success(let payload):
                            
                            let usedEntries = getLastUsedEntries()
                            if !usedEntries.isEmpty {
                                
                                if
                                    let user = Auth.auth().currentUser,
                                    !user.isAnonymous
                                {
                                    let uid = user.uid
                                    
                                    
                                    if model.creator != uid {
                                        let firstKey = usedEntries.keys.first ?? ""
                                        let values = Array(usedEntries.values)
                                            .flatMap { $0 }
                                            .joined(separator: ", ")
                                        
                                        forumFunctionality.sendModelActivity(
                                            forumTag: firstKey,
                                            text: values
                                        ) { result in
                                            switch result {
                                            case .success:
                                                clearAllLastUsedEntries()
                                                wi.cancel()
                                                showLoading = false
                                            case .failure(let error):
                                                
                                                wi.cancel()
                                                showLoading = false
                                                clearAllLastUsedEntries()
                                            }
                                        }
                                    } else {
                                        clearAllLastUsedEntries()
                                    }
                                } else {
                                    clearAllLastUsedEntries()
                                }
                            }
           
                            TapData = payload.taps
                            commandNames = payload.names
                            wi.cancel()
                            showLoading = false
                        case .failure(let error):
                            dismiss()
                        }
                    }
                }
                
                
                publishName = displayName
            
                print("model.description: \(model.description)")
                publishDescription = model.description
            
                nameExistsError = false
            }
            
            .onChange(of: model.name) { newValue in
                
                let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                
                let limited = String(filtered.prefix(20))
                
                if limited != newValue {
                    model.name = limited
                    showNameInvalidWarning = true
                    
                }
            }
            
            .onChange(of: showPublishPopup) { newValue in
                if !newValue {
                    dismiss()
                }
            }
            
            
            .onChange(of: gameStarted) { buildClose in
                if !buildClose && !isPreviewingModel && !isFavouriteModel{
                    personalModelsFunctions.fetchConfigForMyModel(userEmail: myEmail, modelName: model.name) { result in
                        switch result {
                        case .success(let payload):
                            TapData = payload.taps
                            commandNames = payload.names
                        case .failure(let error):
                            print("")
                        }
                    }
                }
            }
            
            .onDisappear {
                if model.justCreated {
                    model.justCreated = false
                }
                
                
            }
            .onReceive(blinkTimer) { _ in
                if model.justCreated {
                    animate.toggle()
                }
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


    private func loadSnapshots(from data: Data) -> [ModelSnapshot] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ModelSnapshot].self, from: data)) ?? []
    }

    private func loadCommandNamesFromSnapshot(modelName: String) -> [Int: [Int: String]] {
        let snaps = loadSnapshots(from: onAppModelDescription)
        return snaps.first(where: { $0.name == modelName })?.commandNames ?? [:]
    }

    private func displayName(for model: Model) -> String {
        modelAliasMap[model.name.canonName].map { $0.isEmpty ? model.name : $0 } ?? model.name
    }
    
    func clearAllLastUsedEntries() {
        
        let emptyData = (try? JSONEncoder().encode([String: [String]]())) ?? Data()
        DispatchQueue.main.async {
            lastUsedEntriesData = emptyData
        }
    }

    func getLastUsedEntries() -> [String: [String]] {
        do {
            return try JSONDecoder().decode([String: [String]].self, from: lastUsedEntriesData)
        } catch {
            
            return [:]
        }
    }

    private func loadData() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        
        myEmail = UserDefaults.standard.string(forKey: "GoogleUserEmail") ?? ""
        
        if !isPreviewingModel && !isFavouriteModel{
            personalModelsFunctions.fetchConfigForMyModel(userEmail: myEmail, modelName: model.name) { result in
                switch result {
                case .success(let payload):
                    TapData = payload.taps
                    commandNames = payload.names
                    tapsFunctions.fetchFolderNames(for: myEmail, selectedModel: model.name) { result in
                        switch result {
                        case .success(let memoryNames):
                            DispatchQueue.main.async {
                                self.MemoryNames = memoryNames
                                
                            }
                        case .failure(let error):
                            
                            print("")
                        }
                    }
                case .failure(let error):
                    print("")
                    
                }
                
            }
        }
    }
    private func upsertSnapshotCommandNames(modelName: String,
                                            newCommandNames: [Int: [Int: String]]) {
        var snaps = loadSnapshots(from: onAppModelDescription)

        if let idx = snaps.firstIndex(where: { $0.name == modelName }) {
            snaps[idx].commandNames = newCommandNames
        } else {
            // create a new snapshot if missing (same pattern you used)
            let snap = ModelSnapshot(
                name: model.name,
                description: model.description,
                keyword: model.keyword,
                creator: model.creator,
                rate: model.rate,
                creationDate: model.creationDate,
                publishDate: model.publishDate,
                justCreated: model.justCreated,
                createdWithVib: model.createdWithVib,
                commandNames: newCommandNames                 // ✅ store it
            )
            snaps.append(snap)
        }

        onAppModelDescription = saveSnapshots(snaps)
    }
    private func saveSnapshots(_ snapshots: [ModelSnapshot]) -> Data {
        (try? JSONEncoder().encode(snapshots)) ?? Data()
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
                            author_name: userName
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
                        removeCachedImagesForModel(model.name)
                        sharedData.favouriteModelImageURLs[model.name] = nil
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

    private func showLikeCooldown(remaining: TimeInterval, justStarted: Bool = false) {
        let minutesLeft = Int(ceil(max(remaining, 0) / 60))
        let leftText = minutesLeft == 1 ? "1_minute".localized() : "\(minutesLeft) \("minutes".localized())"
        likeCooldownMessage = "\("cooldown_30_minutes".localized()) \(leftText) \("left".localized())."
        showLikeCooldownAlert = true
    }
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func checkNameAndPublish() {
        nameExistsError = false
        tapsExistError = false
        let trimmedName = publishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            isPublishing = false
            nameIsEmptyError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPublishPopup = false
            }
            return
        }

        let trimmedDescription = publishDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            isPublishing = false
            descriptionIsEmpty = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPublishPopup = false
            }
            return
        }
        
        let hasAnyTapEntries: Bool = TapData.values.contains { innerDict in
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
            for inner in TapData.values {
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
        
        let hasEmptyTapDescription =
            commandNames.isEmpty ||
            commandNames.values.contains { innerDict in
                innerDict.isEmpty || innerDict.values.contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

        if hasEmptyTapDescription {
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
            if let error = error {
                
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
                publishDescription: publishDescription,
                taps: TapData,
                commandNames: commandNames
            ) { result in
                isPublishing = false
                switch result {
                case .success:
                    isPublishing = false
                    showSuccess = true
                    removeDisplayName(for: model)
                    sharedData.personalModelsData.remove(model)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showPublishPopup = false
                        closeToHome?()
                    }

                case .failure(let err):
                    print("")
                }
            }
        }
    }
    
    
    private func limitWords(_ s: String, to n: Int) -> String {
        let words = s.split { $0.isWhitespace || $0.isNewline }
        guard words.count > n else { return s }
        return words.prefix(n).joined(separator: " ")
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
    
    func saveLastUsedEntry(for model: Model, listOfFavModels: [String]) {
        var currentDict: [String: [String]] = [:]
        
        
        if let decoded = try? JSONDecoder().decode([String: [String]].self, from: lastUsedEntriesData) {
            currentDict = decoded
        }
        
        
        currentDict[model.name] = listOfFavModels
        
        
        do {
            let data = try JSONEncoder().encode(currentDict)
            lastUsedEntriesData = data
        } catch {
            
        }
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

    private func toggle(_ id: Int, in memoryKey: Int) {
        if selectedKeys[memoryKey, default: []].contains(id) {
            selectedKeys[memoryKey]?.remove(id)
        } else {
            selectedKeys[memoryKey, default: []].insert(id)
        }
    }

}

private struct CellFrameKey: PreferenceKey {
  static var defaultValue: [Int: CGRect] = [:]
  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}
