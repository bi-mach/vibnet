import SwiftUI
import FirebaseAuth
import Firebase
import FirebaseStorage
import FirebaseFirestore
import CoreHaptics
import PhotosUI

private extension View {
    func readSizeInto(height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { gp in
                Color.clear
                    .preference(key: HeightKey.self, value: gp.size.height)
            }
        )
        .onPreferenceChange(HeightKey.self) { height.wrappedValue = $0 }
    }
}
struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// helper to measure the bar’s height
struct AccountView: View {
    @EnvironmentObject var sharedData: SharedData
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @Binding var publishedModels: [String: Model]
    var favouriteModels: [String: Model]
    var modelHasBeenDeleted: () -> Void = {}
    var displayTypeUpdated: () -> Void = {}
    @State private var newPost: String = ""
    @State private var posts: [Post] = []
    @State private var userName: String = ""
    @State private var bio: String = ""
    @State private var isEditingName = false
    @State private var isEditingBio = false
    @State private var isEditing = false
    @State private var isComposerExpanded = false
    @State private var newTitle: String = ""
    @State private var newBody: String = ""
    
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    
    @State private var isPhotoPickerPresented: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var isAdjustingImage: Bool = false
    @AppStorage("savedProfileImageData") private var savedProfileImageData: String = ""
    
    @State private var showEditingSheet = false
    
    @State private var isKeyboardVisible = false
    
    @FocusState private var focusedField: Field?
    enum Field { case name, bio }
    
    
    @State private var originalUserName: String = ""
    @State private var originalBio: String = ""
    
    
    @State private var hasTappedBio = false
    
    @State private var usernameError: String? = nil
    
    @State private var followingList: [UserData] = []
    @State private var followingCount: Int = 0
    @State private var followersList: [UserData] = []
    @State private var followersCount: Int = 0
    
    @State private var feedSection: FeedSection = .models
    
    @State private var models: [Model] = []
    @State private var userUID: String = ""
    
    private let compareTrimmed = true
    private func changed(_ new: String, vs old: String) -> Bool {
        if compareTrimmed {
            return new.trimmingCharacters(in: .whitespacesAndNewlines)
            != old.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return new != old
        }
    }
    
    
    @State private var notifications: [AppNotification] = []
    @State private var notifListener: ListenerRegistration?
    @State private var showNotificationsSheet = false
    
    @State private var showOtherPersonSheet = false
    @State private var selectedAuthorID: String? = nil
    @State private var authorToPresent: AuthorSelection? = nil
    @EnvironmentObject var notifService: NotificationsService
    private var unreadCount: Int {
        notifService.notifications.filter { !$0.isRead }.count
    }
    
    @State private var isPreviewingModel: Bool = false
    @State private var selectedModelCard: Model? = nil
    @State private var isFavouriteModel: Bool = false
    @State private var showSettingsView: Bool = false
    @State private var accountRefreshKey = UUID()
    @State private var hasUserLoggedIn = false
    
    @State private var showCooldownAlert: Bool = false
    @State private var cooldownMessage: String = ""
    @State private var isPosting = false  // put this on your view model
    @AppStorage("nextAllowedPostAt") private var nextAllowedPostAt: Double = 0
    
    @State private var openPostID: Post.ID? = nil
    @State private var openModelID: Model.ID? = nil
    @State private var modelID: Int = 0
    @State private var centeredID: Model.ID? = nil
    private func refreshAccount() {
        // Re-fetch anything your AccountView shows
        fetchPosts()
        fetchUsersModels()
        fetchFollowersCount()
        // Force a view reinit (triggers .onAppear paths tied to the new id)
        accountRefreshKey = UUID()
    }
    let inputBarHeight: CGFloat = 58 // whatever your inputBar needs
    var inputBarVisible: Bool {
        !isEditing &&
        feedSection == .posts &&
        (Auth.auth().currentUser?.isAnonymous == false)
    }

    @State private var currentPostIndex = 0
    // Add these states
    @State private var cachedAvatar: UIImage? = nil
    private var avatarCacheKey: String {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return ""
        }

        return "ProfileImages/\(user.uid)/ProfileImage.jpg"
    }

    
    // Load avatar: disk → remote (and save to disk)
    private func loadAvatar() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let uid = user.uid
        guard !uid.isEmpty else { return }
        
        // 1) Try disk cache
        if let disk = ImageDiskCache.shared.load(identifier: avatarCacheKey) {
            cachedAvatar = disk
            return
        }
        
        // 2) Try remote (download, then cache)
        let ref = Storage.storage().reference()
            .child("ProfileImages").child(uid).child("ProfileImage.jpg")
        
        ref.getData(maxSize: 5 * 1024 * 1024) { data, _ in
            guard let data, let img = UIImage(data: data) else { return }
            ImageDiskCache.shared.save(img, identifier: avatarCacheKey, quality: 0.9)
            DispatchQueue.main.async { self.cachedAvatar = img }
        }
    }
    
    // Call when user pulls a “reload”
    private func handleReloadIfNeeded() {
        if sharedData.hasReloaded {
            // Clear both disk + memory previews
            ImageDiskCache.shared.clearAll()
            cachedAvatar = nil
            selectedImage = nil
            // Fetch fresh
            loadAvatar()
            sharedData.hasReloaded = false
        }
    }
    
    @State private var avatarURLCache: [String: URL] = [:]
    @State private var avatarFetchFailures: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
    @State private var topBarHeight: CGFloat = 0
    
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.dynamicTypeSize) private var dynType
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @State private var showLoading = false
    @State private var isComposingInPager = false   // you already have this


    var body: some View {
        ZStack(alignment: .top) {
            // Accent background only behind content, not behind system top area
            selectedAccent.color.opacity(0.08)
                .ignoresSafeArea(edges: [.bottom])   // ← NOT .top

            VStack(spacing: 0) {
                topBar                           // ✅ sits at the very top
                    .padding(.horizontal)
                    .padding(.vertical, 18)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .background(Color(.systemBackground))   // ← opaque backing
                    .overlay(Divider(), alignment: .bottom)

                ZStack { header }
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { sharedData.headerHeight = geo.size.height }
                                .onChange(of: geo.size.height) { new in
                                    let val = max(0, new)
                                    if abs(val - sharedData.headerHeight) > 0.5 {
                                        sharedData.headerHeight = val
                                    }
                                }
                        }
                    )
                    .zIndex(1)
                    .onTapGesture { hideKeyboard() }

                let shouldLift = isComposingInPager && isKeyboardVisible

                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(y: shouldLift ? -sharedData.headerHeight : 0)
                .zIndex(shouldLift ? 10 : 0)
                .animation(.easeInOut(duration: 0.2), value: shouldLift)
                .onPreferenceChange(IsCreatingKey.self) { isCreating in
                    isComposingInPager = isCreating
                }
            }
        }
        .preferredColorScheme(selectedAppearance.colorScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    

    
        
        .alert("cooldown".localized(), isPresented: $showCooldownAlert) {
            Button("ok".localized(), role: .cancel) { }
        } message: {
            Text(cooldownMessage)
        }
        
        .sheet(item: $authorToPresent) { selection in
            NavigationStack {
                OtherPersonAccountView(publishedModels: publishedModels, favouriteModels: favouriteModels, userID: selection.id)
                    .background(Color(UIColor.systemBackground))
                    .presentationDetents([.large])            // prevents medium/auto jumps
                    .presentationDragIndicator(.hidden)
            }
        }
        
        
        .sheet(isPresented: $showNotificationsSheet) {
            NotificationsOverlay(
                isPresented: $showNotificationsSheet,
                notifications: notifService.notifications.sorted { $0.date > $1.date },
                
                onMarkRead: { id in
                    if let i = notifService.notifications.firstIndex(where: { $0.id == id }) {
                        notifService.notifications[i].isRead = true
                    }
                    notifService.markNotificationRead(id)
                },
                onShowAuthor: { uid in
                    DispatchQueue.main.async {
                        authorToPresent = AuthorSelection(id: uid)
                    }
                },
                onDelete: { id in
                    withAnimation {
                        notifService.notifications.removeAll { $0.id == id }
                        notifService.deleteNotification(id)
                    }
                }
            )
            .padding(.horizontal, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
        }
        .onChange(of: selectedDisplayMethod) { _ in
            showLoading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                displayTypeUpdated()
            }
        }
        .onAppear {
            if Auth.auth().currentUser?.isAnonymous == false {
                hasUserLoggedIn = true
                fetchUserName()
                fetchPosts()
                fetchUserProfileImage { img in
                    if let img = img {
                        selectedImage = img
                    }
                }
                fetchFollowersCount()
                fetchUsersModels()
            }
            fetchMissingAvatars(for: followersList.map { $0.uid } + followingList.map { $0.uid })
        }
        .onChange(of: followersList.count) { _ in
            fetchMissingAvatars(for: followersList.map(\.uid))
        }

        .onChange(of: followingList.count) { _ in
            fetchMissingAvatars(for: followingList.map(\.uid))
        }

        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoPicker(selectedImage: $selectedImage, isAdjusting: $isAdjustingImage, onSave: saveProfileImageToAppStorage)
        }
        .sheet(isPresented: $showSettingsView, onDismiss: {
            if Auth.auth().currentUser == nil && hasUserLoggedIn {
                dismiss()
            }
            accountRefreshKey = UUID()
            
            
        }) {
            SettingsView()
            
        }
                
        .sheet(item: $selectedModelCard) { selected in
            
            BuildView(
                model: selected,
                isPreviewingModel: true,
                favouriteModels: favouriteModels,
                isInSheet: true
            )
        }
        
        .onTapGesture {
            
            guard focusedField != nil else { return }
            focusedField = nil
        }
        .id(accountRefreshKey)
    }
    // Split content out for clarity
    @ViewBuilder
    private var content: some View {
        switch feedSection {
        case .posts:
            BlogPager(
                posts: $posts,
                userID: userUID,
                otherPersonView: false,
                index: $currentPostIndex,
                onSend: { addPost(title: $0, text: $1) },
                onDeleteIn: { uid, postID, completion in
                    deletePost(uid: uid, postID: postID, completion: completion)
                }
            )

        case .models:
            ModelsWheelView(
                models: models,
                selectedID: $centeredID,
                favouriteModels: favouriteModels,
                selectedModelCard: $selectedModelCard,
                isPreviewingModel: $isPreviewingModel,
                isFavouriteModel: $isFavouriteModel
              )  { model in
                    // your existing delete logic (wrapped)
                    let backup = models
                    withAnimation { models.removeAll { $0.id == model.id } }
                    
                    publishFunctionality.deleteModelFromPublished(modelName: model.name) { result in
                        switch result {
                        case .success:
                            DispatchQueue.main.async {
                                publishedModels.removeValue(forKey: model.name)
                                fetchUsersModels()
                                modelHasBeenDeleted()
                            }
                        case .failure:
                            DispatchQueue.main.async {
                                withAnimation { models = backup }
                            }
                        }
                    }
                }
                
                .onAppear {
                    centeredID = centeredID ?? models.first?.id
                }
        case .following:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(followingList) { u in
                        FollowingCard(usersData: u, avatarURL: avatarURLCache[u.uid]) {
                            authorToPresent = AuthorSelection(id: u.uid)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

        case .followers:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(followersList) { u in
                        FollowingCard(usersData: u, avatarURL: avatarURLCache[u.uid]) {
                            authorToPresent = AuthorSelection(id: u.uid)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
    // MARK: - Resolve best profile image reference
    private func resolveProfileImageRef(for uid: String, completion: @escaping (StorageReference?) -> Void) {
        guard !uid.isEmpty else { completion(nil); return }
        let base = Storage.storage().reference().child("ProfileImages").child(uid)
        let candidates = ["ProfileImage.jpg"]

        func resolve(from refs: [StorageReference], completion: @escaping (StorageReference?) -> Void) {
            guard let ref = refs.first else { completion(nil); return }
            ref.getMetadata { meta, error in
                if meta != nil {
                    completion(ref)
                } else {
                    resolve(from: Array(refs.dropFirst()), completion: completion)
                }
            }
        }

        // Try direct candidates first
        let directRefs = candidates.map { base.child($0) }
        resolve(from: directRefs) { found in
            if let found { completion(found); return }

            // Fallback: list all and pick most recently updated
            base.listAll { result, error in
                if let error = error {
                    print("[Account] avatar list error (\(uid)):", error.localizedDescription)
                    completion(nil)
                    return
                }

                let items = result?.items ?? []
                guard !items.isEmpty else { completion(nil); return }

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
                    let best = metas.sorted {
                        ($0.1.updated ?? .distantPast) > ($1.1.updated ?? .distantPast)
                    }.first?.0
                    completion(best)
                }
            }
        }
    }

    // MARK: - Fetch + cache avatar URL for multiple UIDs
    private func fetchMissingAvatars(for uids: [String]) {
        let all = Set(uids)
        let missing = all.subtracting(avatarURLCache.keys).subtracting(avatarFetchFailures)

        for uid in missing {
            resolveProfileImageRef(for: uid) { ref in
                ref?.downloadURL { url, _ in
                    DispatchQueue.main.async {
                        if let url {
                            self.avatarURLCache[uid] = url
                        } else {
                            self.avatarFetchFailures.insert(uid)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fetch current user's profile image (UIImage)
    func fetchUserProfileImage(completion: @escaping (UIImage?) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let uid = user.uid

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

    
    private func deleteProfileImage() {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return }
        let email = user.email ?? user.uid
        let userUid = user.uid
        
        let pathID = "ProfileImages/\(userUid)/ProfileImage.jpg"
        let ref = Storage.storage().reference()
            .child("ProfileImages")
            .child(userUid)
            .child("ProfileImage.jpg")
        
        // Evict local cache first (UX: immediate)
        ImageDiskCache.shared.remove(identifier: pathID)
        
        ref.delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Delete failed:", error.localizedDescription)
                    return
                }
                self.accountRefreshKey = UUID()
            }
        }
    }
    
    
    private func showCooldownOfPosts(remaining: TimeInterval, justStarted: Bool = false) {
        let minutesLeft = Int(ceil(max(remaining, 0) / 60))
        let leftText = minutesLeft == 1 ? "1_minute".localized() : "\(minutesLeft) \("minutes".localized())"
        cooldownMessage = "\("posts_cool_down".localized()) \(leftText) \("left".localized())."
        showCooldownAlert = true
    }
    
    private func fetchUsersModels() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let uid = user.uid


        let dateParser: DateFormatter = {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .iso8601)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yy-MM-dd-HH-mm-ss" // keep this the same as what you save
            return df
        }()

        let relativeFormatter: RelativeDateTimeFormatter = {
            let rf = RelativeDateTimeFormatter()
            rf.unitsStyle = .full
            return rf
        }()

        // 1) Filter to the current user's models (from the SOURCE OF TRUTH)
        let mine = sharedData.publishedModels
            .values
            .filter { $0.creator == uid }

        // 2) Sort by the parsed, RAW publishDate (don’t mutate yet)
        let sorted = mine.sorted { lhs, rhs in
            let l = dateParser.date(from: lhs.publishDate) ?? .distantPast
            let r = dateParser.date(from: rhs.publishDate) ?? .distantPast
            return l > r
        }

        // 3) Map to copies with a DISPLAY value (don’t break the raw)
        let now = Date()
        models = sorted.map { model in
            var copy = model
            if let date = dateParser.date(from: model.publishDate) {
                // If you can, prefer a dedicated display property:
                // copy.displayPublishDate = relativeFormatter.localizedString(for: date, relativeTo: now)
                copy.publishDate = relativeFormatter.localizedString(for: date, relativeTo: now)
            }
            return copy
        }
    }
    private func uploadProfileImageToFirebase(_ image: UIImage) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let uid   = user.uid
        let email = user.email ?? ""   // optional if you want cacheID consistency

        let storageRef = Storage.storage().reference()
            .child("ProfileImages")
            .child(uid)
            .child("ProfileImage.jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000, immutable"

        // Resize first, then cap to ~500 KB
        let base = image.resized(toMax: 1080)
        guard let data = base.jpegDataCapped(maxBytes: 500 * 1024) else { return }

        // Write to disk cache immediately
        let cacheID = "\(uid)/ProfileImage.jpg"
        if let preview = UIImage(data: data) {
            ImageDiskCache.shared.save(preview, identifier: cacheID, quality: 0.9)
        }

        // Upload
        storageRef.putData(data, metadata: metadata) { _, error in
            if let error = error {
                print("Upload error:", error.localizedDescription)
                return
            }
            DispatchQueue.main.async { self.accountRefreshKey = UUID() }
            print("Profile image uploaded.")
        }
    }

    private func saveProfileImageToAppStorage(_ image: UIImage) {
        uploadProfileImageToFirebase(image)
    }

    private func fetchUserName() {
        
        guard
            let currentUser = Auth.auth().currentUser,
            !currentUser.isAnonymous
        else { return }


        
        let userEmail = currentUser.email ?? ""
        let uid = currentUser.uid
        
        userUID = uid

        
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
                bio = fetchedBio
            }
            let defaults = UserDefaults.standard
            defaults.setValue(userEmail, forKey: "GoogleUserEmail")
            defaults.setValue(fetchedName, forKey: "GoogleUserName")
            defaults.setValue(true, forKey: "IsSignedIn")
        }
    }

    
    private func segmentLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minWidth: 72)
        
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55),
                                         Color.blue.opacity(0.55),
                                         Color.purple.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                }
            }
            .shadow(color: selected ? Color.black.opacity(0.08) : .clear, radius: 12, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: selected)
    }
    
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedAccent.color)
                
            }

            
            Spacer()
            
            Button {
                showNotificationsSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: showNotificationsSheet ? "bell.fill" : "bell")
                        .imageScale(.large)
                        .foregroundStyle(selectedAccent.color)
                        .contentShape(Circle())
                    
                }
            }
            
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isEditing.toggle()
                    if isEditing {
                        originalUserName = userName
                        originalBio = bio
                        isEditingName = true
                        isEditingBio = true
                    } else {
                        saveEdit(.name)
                        saveEdit(.bio)
                        focusedField = nil
                    }
                }
            } label: {
                Image(systemName: isEditing ? "paintbrush.fill" : "paintbrush")
                    .imageScale(.large)
                    .foregroundStyle(selectedAccent.color)
                    .contentShape(Circle())
            }
        }
    }
    private func fetchPosts() {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            return
        }
        let uid = user.uid

        
        let db = Firestore.firestore()
        db.collection("Followers").document(uid).getDocument { snapshot, error in
            if let error = error {
                
                return
            }
            guard let data = snapshot?.data() else {
                
                return
            }
            
            
            
            
            var postsByID: [String: [String: Any]] = [:]
            
            
            if let postsMap = data["Posts"] as? [String: Any] {
                for (k, v) in postsMap {
                    if let d = v as? [String: Any] {
                        postsByID[k] = d
                    }
                }
            }
            
            
            if postsByID.isEmpty {
                for (k, v) in data where k.hasPrefix("Posts.") {
                    let id = String(k.dropFirst("Posts.".count))
                    if let d = v as? [String: Any] {
                        postsByID[id] = d
                    }
                }
            }
            
            
            
            var loaded: [Post] = postsByID.compactMap { (postID, dict) in
                let title = dict["Title"] as? String ?? "Untitled"
                let text  = dict["Text"]  as? String ?? ""
                let date  = (dict["Date"] as? Timestamp)?.dateValue() ?? .distantPast
                let likes  = dict["Likedby"] as? [String] ?? [""]
                return Post(id: postID, title: title, preview: text, date: date, likes: 0, likedby: likes)
            }
            
            loaded.sort { $0.date > $1.date }
            
            DispatchQueue.main.async {
                self.posts = loaded
                
            }
        }
    }
    
    private func fetchFollowersCount() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let currentUID = user.uid

        let ref = Firestore.firestore().collection(Coll.followers).document(currentUID)
        
        ref.getDocument { snapshot, error in
            if let error = error {
                
                return
            }
            
            let followersMap = (snapshot?.get("Followers") as? [String: Any]) ?? [:]
            let followingMap = (snapshot?.get("Following") as? [String: Any]) ?? [:]
            
            let tempFollowersList = Array(followersMap.keys)
            let tempFollowingList = Array(followingMap.keys)
            
            DispatchQueue.main.async {
                self.followersCount = tempFollowersList.count
                self.followingCount = tempFollowingList.count
            }
            
            
            self.fetchUserSummaries(for: tempFollowersList) { users in
                DispatchQueue.main.async { self.followersList = users }
            }
            self.fetchUserSummaries(for: tempFollowingList) { users in
                DispatchQueue.main.async { self.followingList = users }
            }
            
            
        }
    }
    
    private func fetchUserSummaries(for uids: [String], completion: @escaping ([UserData]) -> Void) {
        guard !uids.isEmpty else { completion([]); return }
        
        let db = Firestore.firestore()
        var results: [UserData] = []
        results.reserveCapacity(uids.count)
        
        let group = DispatchGroup()
        
        for uid in uids {
            group.enter()
            db.collection(Coll.followers).document(uid).getDocument { snap, err in
                defer { group.leave() }
                
                if let err = err {
                    
                    return
                }
                
                let data = snap?.data() ?? [:]
                
                let userName = data["UserName"] as? String ?? ""
                let followersMap = (data["Followers"] as? [String: Any]) ?? [:]
                let postsMap = (data["Posts"] as? [String: Any]) ?? [:]
                let modelsMap = publishedModels.values.filter { $0.creator == uid }.count
                let postsCount = Self.postsCount(from: data)
                let entry = UserData(
                    id: UUID().uuidString,   
                    uid: uid,
                    userName: userName,
                    followers: followersMap.count,
                    posts: postsCount,
                    models: modelsMap
                )
                results.append(entry)
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            
            let ordered = uids.compactMap { id in results.first(where: { $0.uid == id }) }
            completion(ordered)
        }
    }
    
    private static func postsCount(from data: [String: Any]) -> Int {
        
        if let postsAny = data["Posts"] as? [String: Any] {
            var count = 0
            for value in postsAny.values {
                if value is [String: Any] { count += 1 }
            }
            return count
        }
        
        
        var flatCount = 0
        for (key, value) in data where key.hasPrefix("Posts.") {
            if value is [String: Any] { flatCount += 1 }
        }
        return flatCount
    }
    
    private func enterEdit(_ field: Field) {
        switch field {
        case .name:
            originalUserName = userName
            isEditingName = true
            focusedField = .name
        case .bio:
            originalBio = bio
            isEditingBio = true
            focusedField = .bio
        }
    }
    
    private func cancelEdit(_ field: Field) {
        switch field {
        case .name:
            isEditingName = false
            userName = originalUserName
        case .bio:
            isEditingBio = false
            bio = originalBio
        }
    }
    
    private func saveEdit(_ field: Field) {
        switch field {
        case .name:
            isEditingName = false
            if changed(userName, vs: originalUserName) {
                saveUserProfileField(field: "UserName", value: userName)
                originalUserName = userName
            }
        case .bio:
            isEditingBio = false
            if changed(bio, vs: originalBio) {
                saveUserProfileField(field: "Bio", value: bio)
                originalBio = bio
            }
        }
    }
    
    private func switchEditing(to field: Field) {
        
        if field == .name, isEditingBio { cancelEdit(.bio) }
        if field == .bio,  isEditingName { cancelEdit(.name) }
        
        enterEdit(field)
    }
    
    private func validateUserName(_ name: String) {
        
        if name.count > 20 {
            usernameError = "username_error_20".localized()
            return
        }
        
        
        let currentUID = (Auth.auth().currentUser?.isAnonymous == false)
            ? Auth.auth().currentUser?.uid
            : nil

        
        let exists = sharedData.ALLUSERNAMES.contains { uid, existing in
            existing.caseInsensitiveCompare(name) == .orderedSame && uid != currentUID
        }
        
        usernameError = exists ? "username_error_exists".localized() : nil
    }
    
    private var headerBackdrop: some View {
        let material: Material = colorScheme == .dark ? .thickMaterial : .regularMaterial

        return Rectangle()
            .fill(material)
            .overlay(
                LinearGradient(
                    colors: [selectedAccent.color.opacity(0.22), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            // Replace strokeBorder with just top + bottom borders
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.55),
                        selectedAccent.color.opacity(0.45)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.55),
                        selectedAccent.color.opacity(0.45)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                    radius: 20, x: 0, y: 12)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.black.opacity(0.12), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: 1)
                .blur(radius: 0.3)
            }
    }

    

    private var header: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // Breakpoints – base these on screen width instead of hSize
        let screenWidth = UIScreen.main.bounds.width
        let small  = screenWidth < 340
        let medium = screenWidth < 420
        let large  = screenWidth >= 600 || isPad
        
        // Responsive metrics
        let pad: CGFloat        = large ? 24 : (medium ? 18 : 14)
        let gap: CGFloat        = large ? 12 : (small ? 6 : 8)
        let cardRadius: CGFloat = large ? 22 : 16
        let avatarSize: CGFloat = large ? 84 : (medium ? 72 : 60)
        let bioHeight: CGFloat  = {
            switch dynType {
            case .xSmall, .small, .medium: return large ? 120 : 92
            case .large:                   return large ? 140 : 110
            default:                       return large ? 160 : 128
            }
        }()
        
        // Title font
        let titleFont: Font = {
            if large { return .system(.largeTitle, design: .rounded).weight(.heavy) }
            if medium { return .system(.title2, design: .rounded).weight(.heavy) }
            return .system(.title3, design: .rounded).weight(.heavy)
        }()
        
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: gap) {
                
                // Avatar
                avatar
                    .frame(width: avatarSize, height: avatarSize)
                    .accessibilityHidden(false)
                
                // Name block
                Group {
                    if isEditingName {
                        VStack(alignment: .leading, spacing: 4) {
                            if let usernameError {
                                Text(usernameError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            TextField("enter_your_name_field".localized(), text: $userName)
                                .focused($focusedField, equals: .name)
                                .padding(8)
                                .tint(Color.primary)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 0.75)
                                )
                                .onChange(of: userName, perform: validateUserName)
                        
                        }
                    } else {
                        Text(userName.isEmpty ? "" : userName)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .frame(maxHeight: 40, alignment: .leading)
                    }
                }
                .frame(height: 40, alignment: .leading)
                
                // Bio
                Group {
                    let bioFont = Font.system(.headline, design: .rounded).weight(.semibold)
                    let lineHeight: CGFloat = UIFont.preferredFont(forTextStyle: .headline).lineHeight
                    let threeLineHeight: CGFloat = lineHeight * 3 + 2 * 2
                    
                    if isEditingBio {
                        TextEditor(text: $bio)
                            .focused($focusedField, equals: .bio)
                            .padding(8)
                            .tint(Color.primary)
                            .scrollContentBackground(.hidden)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.75)
                            )
                            .frame(height: threeLineHeight, alignment: .topLeading)
                    
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(bio)
                                .font(bioFont)
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: threeLineHeight)
                        .clipped()

                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(pad)
        .background(Color.clear)
        .clipShape(Rectangle())
        .compositingGroup()
        .overlay(alignment: .topTrailing) {
            // Chips responsive layout
            ViewThatFits {
                // Wide
                HStack(spacing: 10) {
                    chipFollowers
                    chipFollowing
                    chipPosts
                    chipModels
                }
                // Compact
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 10) {
                        chipFollowers
                        chipFollowing
                    }
                    HStack(spacing: 10) {
                        chipPosts
                        chipModels
                    }
                }
            }
            .padding(pad)
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    // MARK: - Chips as small helpers (unchanged visuals)
    private var chipFollowers: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .followers }
        } label: {
            statChip(
                icon: "person.2.fill",
                title: "followers".localized(),
                value: "\(followersCount)",
                isSelected: feedSection == .followers,
                size: setchipSize
            )
        }
        .disabled(isEditing)
        .buttonStyle(.plain)
    }

    private var chipFollowing: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .following }
        } label: {
            statChip(
                icon: "person.crop.circle.badge.checkmark",
                title: "following".localized(),
                value: "\(followingCount)",
                isSelected: feedSection == .following,
                size: setchipSize
            )
        }
        .disabled(isEditing)
        .buttonStyle(.plain)
    }

    private var chipPosts: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .posts }
        } label: {
            statChip(
                icon: "text.word.spacing",
                title: "posts".localized(),
                value: "\(posts.count)",
                isSelected: feedSection == .posts,
                size: setchipSize
            )
        }
        .disabled(isEditing)
        .buttonStyle(.plain)
    }
    
    private var setchipSize: ChipSize {
        UIScreen.main.bounds.width < 400 ? .compact : .medium
    }


    private var chipModels: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .models }
        } label: {
            statChip(
                icon: "app.fill",
                title: "models".localized(),
                value: "\(models.count)",
                isSelected: feedSection == .models,
                size: setchipSize
            )
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
    }
    private var avatar: some View {
        ZStack {
            if selectedImage == nil && cachedAvatar == nil {
                Circle()
                    .fill(
                        (selectedAppearance == .system &&
                         colorScheme == .light &&
                         selectedAccent == .default)
                        ? .regularMaterial
                        : .ultraThinMaterial
                    )


            }

            Group {
                if let uiImage = selectedImage ?? cachedAvatar {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(Circle())
        }
        .frame(width: 86, height: 86)
        .overlay(alignment: .bottomTrailing) {
            if isEditing {
                HStack(spacing: 8) {
                    // If nothing chosen/cached → show camera
                    if selectedImage == nil && cachedAvatar == nil {
                        Button {
                            isPhotoPickerPresented = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .imageScale(.small)
                                .padding(6)
                                .foregroundStyle(selectedAccent.color)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                        }
                    } else {
                        // If we have something → show delete
                        Button {
                            deleteProfileImage()                // your existing remote delete
                            ImageDiskCache.shared.remove(identifier: avatarCacheKey)
                            cachedAvatar = nil
                            selectedImage = nil                // clear local preview immediately
                        } label: {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .padding(6)
                                .foregroundStyle(.red)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                        }
                    }
                }
                .offset(x: 6, y: -6)

            }
        }
        .contentShape(Circle())
        .onAppear {
            loadAvatar()
            handleReloadIfNeeded()
        }
        .onChange(of: sharedData.hasReloaded) { _ in
            handleReloadIfNeeded()
        }
    }

    
    private func statChip(
        icon: String,
        title: String,
        value: String,
        isSelected: Bool = false,
        size: ChipSize = .medium
    ) -> some View {
        HStack(spacing: size.hSpacing) {
            Image(systemName: icon)
                .font(.system(size: size.icon, weight: .semibold))
                .symbolVariant(isSelected ? .fill : .none)

            Text(title)
                .font(.system(size: size.title, weight: .medium))
                .opacity(isSelected ? 1 : 0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(size: size.value, weight: .regular, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, size.hPad)
        .padding(.vertical, size.vPad)
        .background(
            Group {
                if #available(iOS 15.0, *) {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(Color(.secondarySystemBackground))
                }
            }
        )
        .overlay(
            Capsule().fill(selectedAccent.color.opacity(isSelected ? 0.18 : 0))
        )
        .overlay(
            Capsule().strokeBorder(
                isSelected ? selectedAccent.color : Color.primary.opacity(0.25),
                lineWidth: isSelected ? size.borderSel : size.border
            )
        )
        .shadow(
            color: isSelected ? selectedAccent.color.opacity(0.20) : Color.primary.opacity(0.06),
            radius: isSelected ? size.shadowR : size.shadowRUnsel,
            x: 0,
            y: isSelected ? size.shadowRY : size.shadowRYUnsel
        )
        .contentShape(Capsule())
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isSelected)
    }
    private func saveUserProfileField(field: String, value: String) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let uid = user.uid

        let db = Firestore.firestore()
        db.collection("Followers").document(uid).updateData([field: value]) { error in
            if let error = error {
                
            } else {
                
            }
        }
    }


    private func addPost(title: String, text: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText  = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedText.isEmpty else { return }

        // ✅ Local cooldown pre-check (no network)
        let now = Date()
        clearCooldownIfExpired(now: now)
        let localRemaining = localCooldownRemaining(now: now)
        if localRemaining > 0 {
            showCooldownOfPosts(remaining: localRemaining)
            return
        }

        guard !isPosting else { return }
        isPosting = true

        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            isPosting = false
            return
        }

        let uid = user.uid

        let db = Firestore.firestore()
        let docRef = db.collection("Followers").document(uid)

        // 🔎 Server check (canonical)
        docRef.getDocument { snapshot, error in
            defer { self.isPosting = false }

            if let error = error {
                print("❌ Failed to fetch posts: \(error.localizedDescription)")
                return
            }

            let data = snapshot?.data() ?? [:]

            // Collect ALL posts (nested + flattened)
            var postDicts: [[String: Any]] = []

            if let postsMap = data["Posts"] as? [String: Any] {
                for (_, v) in postsMap {
                    if let d = v as? [String: Any] { postDicts.append(d) }
                }
            }
            for (k, v) in data where k.hasPrefix("Posts.") {
                if let d = v as? [String: Any] { postDicts.append(d) }
            }

            let dates: [Date] = postDicts.compactMap { dict in
                (dict["Date"] as? Timestamp)?.dateValue()
            }

            let cutoff = now.addingTimeInterval(-3600)
            let recent = dates.filter { $0 >= cutoff }.sorted() // ascending (oldest first)

            if recent.count >= 5 {
                // ⚠️ Over limit → compute server-backed remaining & persist it
                if let oldest = recent.first {
                    let remaining = max(0, 3600 - now.timeIntervalSince(oldest))
                    self.setCooldown(until: oldest.addingTimeInterval(3600))
                    self.showCooldownOfPosts(remaining: remaining)
                } else {
                    // Fallback: full hour
                    self.setCooldown(until: now.addingTimeInterval(3600))
                    self.showCooldownOfPosts(remaining: 3600)
                }
                return
            }

            // ✅ Allowed → create post
            createNewPost()
        }

        func createNewPost() {
            let clientNow = Date()
            let postID = UUID().uuidString
            let finalTitle = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle

            withAnimation(.spring) {
                posts.insert(
                    Post(id: postID,
                         title: finalTitle,
                         preview: trimmedText,
                         date: clientNow,
                         likes: 0,
                         likedby: []),
                    at: 0
                )
            }

            let postData: [String: Any] = [
                "Title": finalTitle,
                "Text": trimmedText,
                "Date": Timestamp(date: clientNow),     // or FieldValue.serverTimestamp()
                "Likedby": [],
                "postLikes": 0
            ]

            let db = Firestore.firestore()
            guard
                let user = Auth.auth().currentUser,
                !user.isAnonymous
            else { return }

            let uid = user.uid

            db.collection("Followers").document(uid)
                .setData(["Posts.\(postID)": postData], merge: true) { error in
                    if let error = error {
                        print("❌ Failed to add post: \(error.localizedDescription)")
                        return
                    }
                    print("✅ Post added successfully")
                    // (Optional) Soft prediction: if you want a local rolling guard
                    // without hitting Firestore again, you could set a "soft"
                    // cooldown after each post like this:
                    // self.setCooldown(until: Date().addingTimeInterval(0)) // no-op
                    // Usually not needed because the server check will enforce next time.
                }
        }
    }

    private func localCooldownRemaining(now: Date = Date()) -> TimeInterval {
        let remaining = nextAllowedPostAt - now.timeIntervalSince1970
        return max(0, remaining)
    }

    private func setCooldown(until date: Date) {
        nextAllowedPostAt = date.timeIntervalSince1970
    }

    private func clearCooldownIfExpired(now: Date = Date()) {
        if now.timeIntervalSince1970 >= nextAllowedPostAt {
            nextAllowedPostAt = 0
        }
    }

    
    func deletePost(uid: String, postID: String, completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()
        let docRef = db.collection("Followers").document(uid)  // ✅ use dynamic uid

        docRef.setData(
            ["Posts.\(postID)": FieldValue.delete()],          // ✅ use dynamic postID
            merge: true
        ) { error in
            if let error = error {
                print("❌ Failed to delete post:", error.localizedDescription)
                completion(error)
            } else {
                print("✅ Successfully deleted post \(postID) for user \(uid)")
                
                
                // ✅ Also remove from local posts array to update UI instantly
                if let index = posts.firstIndex(where: { $0.id == postID }) {
                    posts.remove(at: index)
                    print("🗑️ Removed post from local array")
                } else {
                    print("⚠️ Post not found in local array")
                }
                completion(nil)
            }
        }
    }
    
}



struct Post: Identifiable {
    let id: String          
    let title: String
    let preview: String
    let date: Date
    var likes: Int
    var likedby: [String]
}
private struct StatPill: View {
    let system: String
    let value: Int
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text("\(value)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selectedAccent.color.opacity(0.08), in: Capsule())
    }
}


struct FollowingCard: View {
    let usersData: UserData
    let avatarURL: URL?
    let onSelect: () -> Void

    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @State private var contentHeight: CGFloat = 0
    private let thumbWidth: CGFloat = UIScreen.main.bounds.width * 0.18

    private var accent: Color { selectedAccent.color }

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                
                // Avatar with subtle accent ring to match GenModelCard thumb stroke
                ZStack {
                    AvatarThumb(url: avatarURL)
                        .clipShape(Circle())
                }
                .frame(width: thumbWidth, height: thumbWidth)
                
                // Text side (measured so we could match heights if you ever need)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(usersData.userName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // (Optional) verified/star etc. could go here to mirror badges in GenModelCard
                    }
                    
                    // compact stats row, same tone as GenModelCard’s secondary text
                    HStack(spacing: 10) {
                        StatPill(system: "person.2.fill", value: usersData.followers)
                        StatPill(system: "text.word.spacing", value: usersData.posts)
                        StatPill(system: "app.fill", value: usersData.models)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .highPriorityGesture(TapGesture().onEnded { onSelect() })
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))     // same bright surface
            )
            .overlay( // subtle pressed/accent aura on entire card, optional
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accent.opacity(0.15), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
        .padding(.vertical, UIScreen.main.bounds.height * 0.02)
    }
}



struct AvatarThumb: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                if #available(iOS 15.0, *) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .empty: placeholder
                        case .failure: placeholder
                        @unknown default: placeholder
                        }
                    }
                } else {
                    placeholder // Fallback for iOS 14 if needed
                }
            } else {
                placeholder
            }
        }
        .background(Circle().fill(.ultraThinMaterial))
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(6)
            .foregroundStyle(.secondary)
            .frame(width: UIScreen.main.bounds.width * 0.14, height: UIScreen.main.bounds.width * 0.14)
    }
}


private enum Coll {
    static let users = "Users"
    static let followers = "Followers"
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct GenModelCard: View {
    let model: Model
    let isCurrent: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isStarred = false
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    @EnvironmentObject var forumFunctionality: ForumFunctionality
    @EnvironmentObject var sharedData: SharedData

    @State private var showReportDialog = false
    @State private var modelID: Int = 0

    private var isCreator: Bool {
        Auth.auth().currentUser?.isAnonymous == false &&
        Auth.auth().currentUser?.uid == model.creator

    }

    @State private var contentHeight: CGFloat = 0
    private let thumbWidth: CGFloat = 72 // wider look; tweak as you like


    private var accent: Color {
        sharedData.publishedAccentColors[model.name] ?? selectedAccent.color
    }
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func fetchModelImageIfExists(for modelName: String, email: String) {
        let language = currentAppLanguage()
        let ref = Storage.storage().reference()
            .child("PublishedModels")
            .child("\(language)")
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
    private func storageRefForCurrentUserModelImage(_ name: String) -> StorageReference? {
        guard let email = Auth.auth().currentUser?.email else { return nil }
        let language = currentAppLanguage()
        return Storage.storage().reference()
            .child("PublishedModels")
            .child("\(language)")
            .child(name)
            .child("ModelImage.jpg")
    }

    private func ensureModelImageCached() {
        // If we already have a URL cached, we're done.
        if sharedData.publishedAccentColors[model.name] != nil { return }

        // Try to fetch like in your helpers
        if let email = Auth.auth().currentUser?.email {
            fetchModelImageIfExists(for: model.name, email: email)
        }
    }

    private func pickAccentIfNeeded(from identifier: String) {
        if sharedData.publishedAccentColors[model.name] == nil,
           let img = ImageDiskCache.shared.load(identifier: identifier) {
            let picked: UIColor? = img.vibrantAverageColor ?? img.averageColor
            if let picked {
                sharedData.publishedAccentColors[model.name] = Color(picked)
            }
        }
    }

    private func formattedAgo(from publishDate: String) -> String {
        let parts = publishDate.split(separator: "-").map(String.init)
        guard parts.count == 6,
              let yy = Int(parts[0]),
              let MM = Int(parts[1]),
              let dd = Int(parts[2]),
              let hh = Int(parts[3]),
              let mm = Int(parts[4]),
              let ss = Int(parts[5]) else {
            return publishDate
        }
        let fullYear = yy + 2000
        var comps = DateComponents()
        comps.year = fullYear; comps.month = MM; comps.day = dd
        comps.hour = hh; comps.minute = mm; comps.second = ss
        guard let date = Calendar.current.date(from: comps) else { return publishDate }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // LEFT: Thumbnail that matches the VStack's height
            ZStack {
                if let url = sharedData.publishedModelImageURLs[model.name] {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.2))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.2))
                        @unknown default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.2))
                        }
                    }
                } else if let storageRef = storageRefForCurrentUserModelImage(model.name) {
                  let language = sharedData.appLanguage
                    let id = "PublishedModels/\(language)/\(model.name)/ModelImage.jpg"
                    CachedStorageImage(storageRef: storageRef, identifier: id)
                        .onAppear {
                            pickAccentIfNeeded(from: id)
                            ensureModelImageCached()
                        }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.2))
                }
            }
            // 👇 make the image as tall as the right-side content
            .frame(width: thumbWidth, height: thumbWidth)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(accent.opacity(0.6), lineWidth: 1)
            )

            // RIGHT: Text content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                }

                Text(model.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(formattedAgo(from: model.publishDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            // 👇 measure the height of the text block
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .highPriorityGesture(TapGesture().onEnded { onSelect() })
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay( // subtle pressed/accent aura on entire card, optional
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.15), lineWidth: 1)
        )
        .contextMenu {
            if isCreator {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDelete()
                } label: {
                    Label("delete".localized(), systemImage: "trash")
                }
            }

            Button(role: .destructive) {
                if
                    let user = Auth.auth().currentUser,
                    !user.isAnonymous
                {
                    let currentUID = user.uid
                    forumFunctionality.sendUserReport(
                        forumTag: "model",
                        reason: model.name,
                        reportedUserUID: model.creator
                    ) { result in
                        switch result {
                        case .success(let id): print("Post report filed: \(id)")
                        case .failure(let error): print("Post report failed: \(error.localizedDescription)")
                        }
                    }
                }

            } label: {
                Label("report".localized(), systemImage: "exclamationmark.bubble")
            }

            if let shareURL = URL(string: "https://links.bi-mach.com/model/\(modelID)") {
                ShareLink(item: shareURL, subject: Text("Check out this model")) {
                    Label("share".localized(), systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            if let key = sharedData.GlobalModelsData.first(where: { $0.value == model.name })?.key {
                modelID = key
            }
        }
    }
    
}

// 1) Preference key to capture height
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


struct ModelsWheelView: View {
    let models: [Model]
    @Binding var selectedID: Model.ID?
    let favouriteModels: [String: Model]
    @Binding var selectedModelCard: Model?
    @Binding var isPreviewingModel: Bool
    @Binding var isFavouriteModel: Bool
    var onDelete: (Model) -> Void

    // Environment signals for adaptation
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize
    @Environment(\.dynamicTypeSize)     private var dynType

    // State used by the wheel logic
    @State private var distances: [Model.ID: CGFloat] = [:]
    @State private var isDragging = false

    // Computed layout knobs
    private func rowsForEnvironment() -> Int {
        // iPad (regular width) → more rows
        if hSize == .regular {
            return dynType.isAccessibilitySize ? 3 : 4
        }
        // iPhone portrait vs landscape
        if vSize == .compact { return 2 }      // landscape phone
        return dynType.isAccessibilitySize ? 2 : 3
    }

    private func spacingForEnvironment() -> CGFloat {
        if hSize == .regular { return 14 }
        return 10
    }

    private func clampItemHeight(_ proposed: CGFloat) -> CGFloat {
        // Wider screens can afford taller cards
        let (minH, maxH): (CGFloat, CGFloat) = (hSize == .regular) ? (120, 180) : (110, 160)

        // Respect Dynamic Type by bumping the minimum
        let bump: CGFloat = {
            switch dynType {
            case .xSmall, .small, .medium: return 0
            case .large: return 6
            case .xLarge: return 12
            case .xxLarge: return 18
            case .xxxLarge: return 24
            default: return 36 // accessibility sizes
            }
        }()

        return min(max(proposed, minH + bump), maxH + bump)
    }
    @EnvironmentObject var sharedData: SharedData
    var body: some View {
        GeometryReader { geo in
            // Available height inside this view (safe area aware)
            let safeTop    = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let availableH = max(0, geo.size.height - safeTop - safeBottom)

            // Adaptive knobs
            let visibleRows = rowsForEnvironment()
            let itemSpacing = spacingForEnvironment()

            // Derive an item height that fills the viewport nicely
            // rows * h + (rows-1) * spacing = target; solve for h
            let targetViewport = availableH > 0 ? availableH : geo.size.height
            let rawItemH = (targetViewport - CGFloat(visibleRows - 1) * itemSpacing) / CGFloat(visibleRows)
            let itemHeight = clampItemHeight(rawItemH)

            // Wheel geometry
            let viewportHeight = itemHeight * CGFloat(visibleRows) + itemSpacing * CGFloat(visibleRows - 1)
            let sideInset      = max(0, (viewportHeight - itemHeight) / 2)
            let centerY        = viewportHeight / 2

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: itemSpacing) {

                        ForEach(models) { model in
                            let isCurrent = (selectedID == model.id)
                            let distance  = distances[model.id] ?? 0

                            GenModelCard(
                                model: model,
                                isCurrent: isCurrent,
                                onSelect: {
                                    if isCurrent {
                                        isPreviewingModel = true
                                        isFavouriteModel = sharedData.publishedFavModels[model.name] != nil

                                        selectedModelCard = model
                                    } else {
                                        withAnimation(.snappy(duration: 0.3)) {
                                            selectedID = model.id
                                            scrollProxy.scrollTo(model.id, anchor: .center)
                                        }
                                    }
                                },
                                onDelete: { onDelete(model) }
                            )
                            .frame(height: itemHeight)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .scaleEffect(scale(for: distance, itemHeight: itemHeight))
                            .opacity(opacity(for: distance, itemHeight: itemHeight))
                            .background(
                                GeometryReader { gp in
                                    Color.clear.preference(
                                        key: ItemMidYKey.self,
                                        value: [AnyHashable(model.id): gp.frame(in: .named("wheelScroll")).midY]
                                    )
                                }
                            )
                            .id(model.id)
                        }
                    }
                    .padding(.vertical, sideInset)  
                }
                .coordinateSpace(name: "wheelScroll")
                .simultaneousGesture(DragGesture(minimumDistance: 1), including: .subviews)

                // Track which item is nearest to center
                .onPreferenceChange(ItemMidYKey.self) { mids in
                    let newDistances: [Model.ID: CGFloat] = mids.reduce(into: [:]) { result, kv in
                        if let key = kv.key as? Model.ID { result[key] = kv.value - centerY }
                    }
                    distances = newDistances

                    if let nearest = newDistances.min(by: { abs($0.value) < abs($1.value) })?.key,
                       nearest != selectedID {
                        selectedID = nearest
                        let g = UISelectionFeedbackGenerator()
                        g.prepare()
                        g.selectionChanged()
                    }
                }

                // Snap only after drag ends
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in isDragging = true }
                        .onEnded { _ in
                            isDragging = false
                            if let id = selectedID {
                                withAnimation(.snappy(duration: 0.35)) {
                                    scrollProxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                )

                // Programmatic select → center (but not while dragging)
                .onChange(of: selectedID) { new in
                    guard !isDragging, let id = new else { return }
                    withAnimation(.snappy(duration: 0.3)) {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
                .onAppear {
                    if selectedID == nil { selectedID = models.first?.id }
                    if let id = selectedID {
                        DispatchQueue.main.async { scrollProxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            // Make the wheel exactly as tall as our computed viewport
            .frame(height: viewportHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        // Let the GeometryReader fill horizontally but not force extra vertical space
        .frame(maxWidth: .infinity)
    }

    // MARK: - Visual falloff tuned to current itemHeight
    private func scale(for distance: CGFloat, itemHeight: CGFloat) -> CGFloat {
        let n = min(max(abs(distance) / itemHeight, 0), 1)
        return 1 - 0.08 * n
    }
    private func opacity(for distance: CGFloat, itemHeight: CGFloat) -> CGFloat {
        let n = min(max(abs(distance) / itemHeight, 0), 1)
        return 1 - 0.4 * n
    }
}

// Preference key unchanged
private struct ItemMidYKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGFloat] = [:]
    static func reduce(value: inout [AnyHashable: CGFloat], nextValue: () -> [AnyHashable: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
