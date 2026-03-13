






import SwiftUI
import FirebaseAuth
import Firebase
import FirebaseFirestore
import FirebaseStorage

private enum Coll {
    static let users = "Users"           
    static let followers = "Followers"   
}

struct OtherPersonAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    let publishedModels: [String: Model]
    let favouriteModels: [String: Model]
    private let initialUserID: String
    @State private var currentUserID: String
    @State private var history: [String]
    init(publishedModels: [String: Model], favouriteModels: [String: Model], userID: String) {
        self.publishedModels = publishedModels
        self.favouriteModels = favouriteModels
        self.initialUserID = userID
        _currentUserID = State(initialValue: userID)
        _history = State(initialValue: [userID])
    }
    @EnvironmentObject var sharedData: SharedData
    @State private var posts: [Post] = []
    @State private var models: [Model] = []
    @State private var userName: String = ""
    @State private var bio: String = ""
    @State private var userEmail: String = ""
    @State private var selectedImage: UIImage? = nil
    @State private var isFollowing = false
    @State private var isLoadingFollow = false
    @State private var followingList: [UserData] = []
    @State private var followingCount: Int = 0
    @State private var followersList: [UserData] = []
    @State private var followersCount: Int = 0
    @State private var feedSection: FeedSection = .models
    @State private var selectedModelCard: Model? = nil
    @State private var isFavouriteModel: Bool = false
    @State private var authorToPresent: AuthorSelection? = nil
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("followCooldownUntil") private var followCooldownUntil: Double = 0
    @AppStorage("followSpamCount")     private var followSpamCount: Int = 0
    @AppStorage("followLastTap")       private var followLastTap: Double = 0
    @State private var showCooldownAlert = false
    @State private var cooldownMessage   = ""
    private let spamThreshold  = 10
    private let cooldownWindow: TimeInterval = 30*60
    private let spamWindow:    TimeInterval = 60
    
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showAccountActionMenu = false
    @State private var isBlockedByOther = false
    @State private var centeredID: Model.ID? = nil
    @State private var currentPostIndex = 0
    @State private var avatarURLCache: [String: URL] = [:]
    @State private var avatarFetchFailures: Set<String> = []
    @State private var showChat = false
    @State private var chatDragX: CGFloat = 0
    @State private var avatarImageCache: [String: UIImage] = [:]
    @State private var reportTarget: String? = nil
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.dynamicTypeSize) private var dynType
    private var iBlockedThem: Bool {
        sharedData.blockedUserIDs.contains(currentUserID)
    }
    
    private var showBlockOverlay: Bool {
        iBlockedThem || isBlockedByOther
    }
    @ViewBuilder
    private var mainScaffold: some View {
        VStack(spacing: 0) {
            topBar
                // ✅ same “shell” as AccountView
                .padding(.horizontal)
                .padding(.vertical, 18)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .background(Color(.systemBackground))   // ← neutral backing, not tinted by accent
                .overlay(Divider(), alignment: .bottom)
            header
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard() }
            
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    
    // MARK: Block gate overlay
    
    private struct BlockGate: View {
        let iBlockedThem: Bool
        let onUnblock: () -> Void
        
        var body: some View {
            ZStack {
                // Eat all taps behind the card
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .imageScale(.large)
                    
                    Text("user_is_blocked".localized())
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    
                    if iBlockedThem {
                        Button(action: onUnblock) {
                            Text("unblock_user".localized())
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("you_are_blocked_by_this_user".localized())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .frame(maxWidth: 360)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                
                .shadow(radius: 20)
                .padding()
            }
        }
    }
    
    // MARK: Chat drag behavior
    
    private struct ChatDrag: ViewModifier {
        @Binding var dragX: CGFloat
        var onEnd: (_ dismissed: Bool) -> Void
        
        init(dragX: Binding<CGFloat>, _ onEnd: @escaping (_ dismissed: Bool) -> Void) {
            self._dragX = dragX
            self.onEnd = onEnd
        }
        
        func body(content: Content) -> some View {
            content
                .offset(x: max(0, dragX))
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            dragX = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            let dismissed = value.translation.width > 120 || value.predictedEndTranslation.width > 220
                            onEnd(dismissed)
                        }
                )
        }
    }
    private func canChatWithUser() -> Bool {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return false }

        let myUID = user.uid

        // they follow me
        let theyFollowMe = followersList.contains { $0.uid == myUID }
        // I follow them
        let iFollowThem = followingList.contains { $0.uid == currentUserID }
        return theyFollowMe && iFollowThem
    }

    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            // Accent background behind content, but NOT into the top safe area
            selectedAccent.color.opacity(0.08)
                .ignoresSafeArea(edges: [.bottom])

            // All your existing content moved inside here
            ZStack {
                // ===== Main scaffold (top bar + header + content) =====
                mainScaffold
                    .blur(radius: showBlockOverlay ? 12 : 0)
                    .allowsHitTesting(!showBlockOverlay)
                
                // ===== Block overlay (centered card, taps swallowed) =====
                if showBlockOverlay {
                    BlockGate(
                        iBlockedThem: iBlockedThem,
                        onUnblock: {
                            publishFunctionality.unblockUser(userToUnblockUID: currentUserID) { result in
                                switch result {
                                case .success:
                                    if let idx = sharedData.blockedUserIDs.firstIndex(of: currentUserID) {
                                        sharedData.blockedUserIDs.remove(at: idx)
                                    }
                                case .failure(let error):
                                    print("❌ Failed to unblock:", error.localizedDescription)
                                }
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(20)
                }
                
                // ===== Chat overlay =====
                if showChat {
                    let dim = max(0, 0.5 - Double(min(chatDragX, 200) / 400))
                    let canChatWithaotehrUser = canChatWithUser()

                    Color.black.opacity(dim)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showChat = false
                            }
                        }
                        .zIndex(30)
                    
                    MessageView(
                        peerUID: currentUserID,
                        peerDisplayName: userName,
                        selectedImage: selectedImage,
                        showChat: $showChat,
                        canSend: canChatWithaotehrUser
                    )
                    .ignoresSafeArea(edges: .top)
                    .ignoresSafeArea(.keyboard)
                    .modifier(ChatDrag(dragX: $chatDragX) { dismissed in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            if dismissed { showChat = false }
                            chatDragX = 0
                        }
                    })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(40)
                }
            }
        }
        .preferredColorScheme(selectedAppearance.colorScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        
        // ===== System surfaces =====
        .alert("cooldown".localized(), isPresented: $showCooldownAlert) {
            Button("ok".localized(), role: .cancel) { }
        } message: {
            Text(cooldownMessage)
        }
        .overlay(alignment: .bottom) {
            reportActionSheet
        }
        .background(
            SheetDismissObserver {
                if history.count > 1 {
                    _ = popToPreviousUser()
                    return false
                } else { return true }
            }
        )
        .interactiveDismissDisabled(history.count > 1)

        .sheet(item: $selectedModelCard) { selected in
            
            BuildView(
                model: selected,
                isPreviewingModel: true,
                favouriteModels: favouriteModels,
                isInSheet: true
            )
        }
        .sheet(item: $authorToPresent) { selection in
            NavigationStack {
                OtherPersonAccountView(
                    publishedModels: publishedModels,
                    favouriteModels: favouriteModels,
                    userID: selection.id
                )
                .background(Color(UIColor.systemBackground))
            }
        }
        .onAppear {
            loadUser(initialUserID)
            checkIfBlockedByViewedUser(viewedUID: initialUserID)
            fetchMissingAvatars(for: followersList.map { $0.uid } + followingList.map { $0.uid })
        }
        .onChange(of: followersList.count) { _ in
            fetchMissingAvatars(for: followersList.map(\.uid))
        }
        .onChange(of: followingList.count) { _ in
            fetchMissingAvatars(for: followingList.map(\.uid))
        }
        .onChange(of: currentUserID) { newID in
            loadUser(newID)
            checkIfBlockedByViewedUser(viewedUID: newID)
        }
    }

    @ViewBuilder
    private var reportActionSheet: some View {
        if let target = reportTarget {
            UserActionSheet(
                currentUserID: target,
                accent: selectedAccent.color,
                onCancel: {
                    reportTarget = nil
                },
                onReportName: {
                    sendReport(tag: "account_name", reason: userName)
                },
                onReportBio: {
                    sendReport(tag: "account_biography", reason: bio)
                },
                onReportAvatar: {
                    sendReport(tag: "account_image", reason: "image")
                },
                onBlockAction: {
                    sharedData.blockedUserIDs.append(target)
                    dismiss()
                },
                onUnBlockAction: {
                    if let idx = sharedData.blockedUserIDs.firstIndex(of: target) {
                        sharedData.blockedUserIDs.remove(at: idx)
                    }
                    reportTarget = nil
                }
            )
            .zIndex(100)
        }
    }

    private func sendReport(tag: String, reason: String) {
        forumFunctionality.sendUserReport(
            forumTag: tag,
            reason: reason,
            reportedUserUID: currentUserID
        ) { result in
            switch result {
            case .success(let id): print("Report filed: \(id)")
            case .failure(let error): print("Report failed: \(error.localizedDescription)")
            }
        }
        reportTarget = nil
    }
    @ViewBuilder
    private var content: some View {
        switch feedSection {
        case .posts:
            BlogPager(
                posts: $posts,
                userID: currentUserID,
                otherPersonView: true,
                index: $currentPostIndex,
                onSend: { _, _ in
                },
                onDeleteIn: { _, _, _ in
                }
            )
            .onChange(of: posts.count) { _ in
                // keep index in range if your list changes live
                currentPostIndex = min(currentPostIndex, max(posts.count - 1, 0))
            }
            
        case .models:
            ModelsWheelView(models: models, selectedID: $centeredID, favouriteModels: favouriteModels, selectedModelCard: $selectedModelCard, isPreviewingModel: $isFavouriteModel, isFavouriteModel: $isFavouriteModel) { _ in}
                .onAppear {
                    centeredID = centeredID ?? models.first?.id
                }
        case .following:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(followingList) { userData in
                        FollowingCard(
                            usersData: userData,
                            avatarURL: avatarURLCache[userData.uid]
                        ) {
                            retarget(to: userData.uid)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            
        case .followers:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(followersList) { userData in
                        FollowingCard(
                            usersData: userData,
                            avatarURL: avatarURLCache[userData.uid]
                        ) {
                            retarget(to: userData.uid)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
    private func checkIfBlockedByViewedUser(viewedUID: String) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            isBlockedByOther = false
            return
        }

        let myUID = user.uid

        let db = Firestore.firestore()
        db.collection("Followers").document(viewedUID).getDocument { snap, error in
            if let _ = error { return } // keep previous state on error
            let blocked = snap?.get("Blocked_Users") as? [String] ?? []
            DispatchQueue.main.async {
                self.isBlockedByOther = blocked.contains(myUID)
            }
        }
    }
    
    @ViewBuilder
    private var topBar: some View {
        HStack {
            // Left chevron
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedAccent.color)
                    .contentShape(Circle())
            }

            Spacer()

            // Right side group (only if not own profile)
            if currentUserID != Auth.auth().currentUser?.uid {
                HStack(spacing: 16) {
                    /*
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            showChat = true
                            chatDragX = 0
                        }
                    } label: {
                        Image(systemName: "message.fill")
                            .imageScale(.large)
                            .foregroundStyle(selectedAccent.color)
                            .contentShape(Circle())
                    }
                    */

                    Button { reportTarget = currentUserID } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .foregroundStyle(selectedAccent.color)
                            .contentShape(Circle())
                    }
                }
            }
        }
        .opacity(showChat ? 0.0 : 1.0)
        .allowsHitTesting(!showChat)
    }

    

    
    private func retarget(to newID: String) {
        guard newID != currentUserID else { return }
        resetUI()
        history.append(newID)
        currentUserID = newID
        
    }
    
    @discardableResult
    private func popToPreviousUser() -> String {
        guard history.count > 1 else { return currentUserID }
        _ = history.popLast()
        let prev = history.last ?? initialUserID
        resetUI()
        currentUserID = prev
        return prev
    }
    
    private func resetUI() {
        userName = ""
        bio = ""
        userEmail = ""
        selectedImage = nil
        posts = []
        models = []
        isFollowing = false
        followingList = []
        followersList = []
        followingCount = 0
        followersCount = 0
        feedSection = .posts
    }
    
    private func loadUser(_ id: String) {
        
        fetchProfileAndPosts()
        
        fetchOtherUserProfileImage(userID: id) { img in
            DispatchQueue.main.async { selectedImage = img }
        }
        
        fetchFollowState()
        fetchFollowNumbers()
        
        fetchUsersModels()
    }
    
    private func fetchUsersModels() {
        models = publishedModels
            .filter { _, model in
                model.creator == currentUserID
            }
            .map { $0.value }
            .sorted { $0.publishDate > $1.publishDate }
    }
    
    private func fetchFollowNumbers() {
        let ref = Firestore.firestore().collection(Coll.followers).document(currentUserID)
        
        ref.getDocument { snapshot, error in
            if let error = error {
                
                return
            }
            let followersMap = (snapshot?.get("Followers") as? [String: Any]) ?? [:]
            let followingMap = (snapshot?.get("Following") as? [String: Any]) ?? [:]
            
            let followerIDs = Array(followersMap.keys)
            let followingIDs = Array(followingMap.keys)
            
            DispatchQueue.main.async {
                self.followersCount = followerIDs.count
                self.followingCount = followingIDs.count
            }
            
            
            fetchUserSummaries(for: followerIDs) { users in
                DispatchQueue.main.async { self.followersList = users }
            }
            fetchUserSummaries(for: followingIDs) { users in
                DispatchQueue.main.async { self.followingList = users }
            }
        }
    }
    
    func fetchOtherUserProfileImage(userID: String, completion: @escaping (UIImage?) -> Void) {
        let cacheID = "ProfileImages/\(userID)/ProfileImage.jpg"
        let base = Storage.storage().reference().child("ProfileImages").child(userID)
        let candidates = ["ProfileImage.jpg", "ProfileImage.png"]
        
        // 1) Disk first (instant)
        if let cached = ImageDiskCache.shared.load(identifier: cacheID) {
            completion(cached)
            // Background refresh (optional, silent)
            base.child("ProfileImage.jpg").getData(maxSize: 5 * 1024 * 1024) { data, _ in
                if let data, let fresh = UIImage(data: data) {
                    ImageDiskCache.shared.save(fresh, identifier: cacheID, quality: 0.9)
                }
            }
            return
        }
        
        // 2) Try known filenames
        func tryRefs(_ refs: [StorageReference]) {
            guard let ref = refs.first else {
                // 3) Fallback: listAll → pick newest
                base.listAll { result, error in
                    guard error == nil, let items = result?.items, !items.isEmpty else {
                        completion(nil); return
                    }
                    var metas: [(StorageReference, StorageMetadata)] = []
                    let g = DispatchGroup()
                    for item in items {
                        g.enter()
                        item.getMetadata { meta, _ in
                            if let meta { metas.append((item, meta)) }
                            g.leave()
                        }
                    }
                    g.notify(queue: .main) {
                        guard let best = metas.sorted(by: { ($0.1.updated ?? .distantPast) > ($1.1.updated ?? .distantPast) }).first?.0 else {
                            completion(nil); return
                        }
                        best.getData(maxSize: 5 * 1024 * 1024) { data, _ in
                            guard let data, let img = UIImage(data: data) else { completion(nil); return }
                            ImageDiskCache.shared.save(img, identifier: cacheID, quality: 0.9)
                            completion(img)
                        }
                    }
                }
                return
            }
            
            ref.getData(maxSize: 5 * 1024 * 1024) { data, _ in
                if let data, let img = UIImage(data: data) {
                    ImageDiskCache.shared.save(img, identifier: cacheID, quality: 0.9)
                    completion(img)
                } else {
                    tryRefs(Array(refs.dropFirst()))
                }
            }
        }
        
        tryRefs(candidates.map { base.child($0) })
    }
    
    private func fetchMissingAvatars(for uids: [String]) {
        let all = Set(uids)
        let missing = all
            .subtracting(avatarImageCache.keys)   // show immediately if we already decoded
            .subtracting(avatarFetchFailures)
        
        for uid in missing {
            let cacheID = "ProfileImages/\(uid)/ProfileImage.jpg"
            
            if let disk = ImageDiskCache.shared.load(identifier: cacheID) {
                // use cached bitmap instantly
                DispatchQueue.main.async { self.avatarImageCache[uid] = disk }
                // (optional) also populate URL for AsyncImage paths
                Storage.storage().reference()
                    .child("ProfileImages").child(uid).child("ProfileImage.jpg")
                    .downloadURL { url, _ in
                        if let url { DispatchQueue.main.async { self.avatarURLCache[uid] = url } }
                    }
                continue
            }
            
            fetchAvatarIfNeeded(uid: uid)
        }
    }
    private func fetchAvatarIfNeeded(uid: String) {
        guard !uid.isEmpty else { return }
        if avatarFetchFailures.contains(uid) { return }
        if avatarImageCache[uid] != nil { return } // already have bitmap
        
        let cacheID = "ProfileImages/\(uid)/ProfileImage.jpg"
        let base = Storage.storage().reference().child("ProfileImages").child(uid)
        let candidates = ["ProfileImage.jpg", "ProfileImage.png"]
        
        // Disk first
        if let disk = ImageDiskCache.shared.load(identifier: cacheID) {
            DispatchQueue.main.async { self.avatarImageCache[uid] = disk }
            base.child("ProfileImage.jpg").downloadURL { url, _ in
                if let url { DispatchQueue.main.async { self.avatarURLCache[uid] = url } }
            }
            return
        }
        
        func setCaches(from data: Data, ref: StorageReference) {
            if let img = UIImage(data: data) {
                ImageDiskCache.shared.save(img, identifier: cacheID, quality: 0.9)
                DispatchQueue.main.async { self.avatarImageCache[uid] = img }
                ref.downloadURL { url, _ in
                    if let url { DispatchQueue.main.async { self.avatarURLCache[uid] = url } }
                }
            } else {
                DispatchQueue.main.async { self.avatarFetchFailures.insert(uid) }
            }
        }
        
        func tryRefs(_ refs: [StorageReference]) {
            guard let ref = refs.first else {
                base.listAll { result, error in
                    guard error == nil, let items = result?.items, !items.isEmpty else {
                        DispatchQueue.main.async { self.avatarFetchFailures.insert(uid) }
                        return
                    }
                    var metas: [(StorageReference, StorageMetadata)] = []
                    let g = DispatchGroup()
                    for item in items {
                        g.enter()
                        item.getMetadata { meta, _ in
                            if let meta { metas.append((item, meta)) }
                            g.leave()
                        }
                    }
                    g.notify(queue: .main) {
                        guard let best = metas.sorted(by: { ($0.1.updated ?? .distantPast) > ($1.1.updated ?? .distantPast) }).first?.0 else {
                            self.avatarFetchFailures.insert(uid); return
                        }
                        best.getData(maxSize: 5 * 1024 * 1024) { data, _ in
                            if let data { setCaches(from: data, ref: best) }
                            else { DispatchQueue.main.async { self.avatarFetchFailures.insert(uid) } }
                        }
                    }
                }
                return
            }
            
            ref.getData(maxSize: 5 * 1024 * 1024) { data, _ in
                if let data { setCaches(from: data, ref: ref) }
                else { tryRefs(Array(refs.dropFirst())) }
            }
        }
        
        tryRefs(candidates.map { base.child($0) })
    }
    
    
    private func fetchUserSummaries(for uids: [String], completion: @escaping ([UserData]) -> Void) {
        guard !uids.isEmpty else { completion([]); return }
        let db = Firestore.firestore()
        var results: [UserData] = []
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
                let postsCount = Self.postsCount(from: data)
                
                let modelsMap = publishedModels.values.filter { $0.creator == uid }.count
                
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
    
    private var blogSwitcher: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .posts }
            } label: {
                segmentLabel("posts".localized(), selected: feedSection == .posts)
            }
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { feedSection = .models }
            } label: {
                segmentLabel("models".localized(), selected: feedSection == .models)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
    
    private func segmentLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.white.opacity(0.25),
                        lineWidth: selected ? 1.25 : 0.75
                    )
            )
    }
    
    private func fetchProfileAndPosts() {
        let db = Firestore.firestore()
        db.collection("Followers").document(currentUserID).getDocument { snapshot, error in
            if let error = error {
                
                return
            }
            guard let data = snapshot?.data() else {
                
                return
            }
            
            
            let fetchedName  = (data["UserName"] as? String) ?? ""
            let fetchedBio   = (data["Bio"] as? String) ?? ""
            
            
            var postsByID: [String:[String:Any]] = [:]
            
            
            if let postsMap = data["Posts"] as? [String: Any] {
                for (key, value) in postsMap {
                    if let dict = value as? [String: Any] {
                        postsByID[key] = dict
                    }
                }
            }
            
            
            if postsByID.isEmpty {
                for (key, value) in data {
                    if key.hasPrefix("Posts."),
                       let dict = value as? [String: Any] {
                        let id = String(key.dropFirst("Posts.".count))
                        postsByID[id] = dict
                    }
                }
            }
            
            var loaded: [Post] = postsByID.compactMap { (postID, dict) in
                let title = dict["Title"] as? String ?? "Untitled"
                let text  = dict["Text"]  as? String ?? ""
                let date  = (dict["Date"] as? Timestamp)?.dateValue() ?? .distantPast
                let liked  = dict["Likedby"] as? [String] ?? [""]
                return Post(id: postID, title: title, preview: text, date: date, likes: 0, likedby: liked)
            }.sorted { $0.date > $1.date }
            
            DispatchQueue.main.async {
                self.userName = fetchedName
                self.bio = fetchedBio
                self.posts = loaded
                print("POSTS ARE: \(posts)")
            }
        }
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
        let w = UIScreen.main.bounds.width
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let compact = hSize == .compact
        
        // Breakpoints
        let small  = w < 340
        let medium = w < 420
        let large  = w >= 600 || isPad
        
        // Responsive metrics
        let pad: CGFloat        = large ? 24 : (medium ? 18 : 14)
        let gap: CGFloat        = large ? 12 : (small ? 6 : 8)
        let cardRadius: CGFloat = large ? 22 : 16
        let avatarSize: CGFloat = large ? 84 : (medium ? 72 : 60)
        
        // Honor Dynamic Type a bit more for bio height
        let bioHeight: CGFloat  = {
            switch dynType {
            case .xSmall, .small, .medium: return large ? 120 : 92
            case .large:                   return large ? 140 : 110
            default:                       return large ? 160 : 128
            }
        }()
        
        // Title sizing
        let titleFont: Font = {
            if large { return .system(.largeTitle, design: .rounded).weight(.heavy) }
            if medium { return .system(.title2, design: .rounded).weight(.heavy) }
            return .system(.title3, design: .rounded).weight(.heavy)
        }()
        
        // Precompute bio metrics for a consistent three-line block
        let bioFont = Font.system(.headline, design: .rounded).weight(.semibold)
        let lineHeight: CGFloat = UIFont.preferredFont(forTextStyle: .headline).lineHeight
        let threeLineHeight: CGFloat = lineHeight * 3 + 2 * 2 // (2 is lineSpacing)
        
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: gap) {
                
                // AVATAR (responsive size)
                avatar
                    .frame(width: avatarSize, height: avatarSize)
                    .accessibilityHidden(false)
                
                // NAME (fixed height area to avoid jumps)
                Text(userName.isEmpty ? "" : userName)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .frame(height: 40, alignment: .leading)
                
                // BIO (consistent height whether empty or not)
                Text(bio.isEmpty ? "" : bio)
                    .font(bioFont)
                    .foregroundStyle(.gray)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .frame(height: max(threeLineHeight, bioHeight), alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer(minLength: 0)
        }
        .padding(pad)
        .background(Color.clear)
        .clipShape(Rectangle()) // or just remove this line
        .compositingGroup()
        
        .overlay(alignment: .topTrailing) {
            ViewThatFits {
                // Wide: one row
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            feedSection = .followers
                        }
                    } label: {
                        statChip(
                            icon: "person.2.fill",
                            title: "followers".localized(),
                            value: "\(followersCount)",
                            isSelected: feedSection == .followers
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            feedSection = .following
                        }
                    } label: {
                        statChip(
                            icon: "person.crop.circle.badge.checkmark",
                            title: "following".localized(),
                            value: "\(followingCount)",
                            isSelected: feedSection == .following
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            feedSection = .posts
                        }
                    } label: {
                        statChip(
                            icon: "text.word.spacing",
                            title: "posts".localized(),
                            value: "\(posts.count)",
                            isSelected: feedSection == .posts
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            feedSection = .models
                        }
                    } label: {
                        statChip(
                            icon: "app.fill",
                            title: "models".localized(),
                            value: "\(models.count)",
                            isSelected: feedSection == .models
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Compact: two rows
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                feedSection = .followers
                            }
                        } label: {
                            statChip(
                                icon: "person.2.fill",
                                title: "followers".localized(),
                                value: "\(followersCount)",
                                isSelected: feedSection == .followers,
                                size: setchipSize
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                feedSection = .following
                            }
                        } label: {
                            statChip(
                                icon: "person.crop.circle.badge.checkmark",
                                title: "following".localized(),
                                value: "\(followingCount)",
                                isSelected: feedSection == .following,
                                size: setchipSize
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                feedSection = .posts
                            }
                        } label: {
                            statChip(
                                icon: "text.word.spacing",
                                title: "posts".localized(),
                                value: "\(posts.count)",
                                isSelected: feedSection == .posts,
                                size: setchipSize
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                feedSection = .models
                            }
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
                    }
                }
            }
            .padding(pad)
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    
    private func handleFollowTap() {
        guard !isLoadingFollow else { return }
        let now = Date().timeIntervalSince1970

        
        if followCooldownUntil > now {
            showCooldown(remaining: followCooldownUntil - now)
            return
        }

        
        if followCooldownUntil != 0, followCooldownUntil <= now {
            followCooldownUntil = 0
        }

        
        if now - followLastTap > spamWindow {
            followSpamCount = 0
        }
        followSpamCount += 1
        followLastTap = now

        if followSpamCount >= spamThreshold {
            followCooldownUntil = now + cooldownWindow
            followSpamCount = 0
            showCooldown(remaining: cooldownWindow, justStarted: true)
            return
        }

        
        toggleFollow()
    }

    private func showCooldown(remaining: TimeInterval, justStarted: Bool = false) {
        let minutesLeft = Int(ceil(max(remaining, 0) / 60))
        let leftText = minutesLeft == 1 ? "1_minute".localized() : "\(minutesLeft) \("minutes".localized())"
        cooldownMessage = "\("cooldown_30_minutes".localized()) \(leftText) \("left".localized())."
        showCooldownAlert = true
    }

    private var avatar: some View {
        ZStack {
            if selectedImage == nil{
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
                if let uiImage = selectedImage {
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
            if let currentUID = Auth.auth().currentUser?.uid, currentUID != currentUserID {
                Button {
                    handleFollowTap()
                } label: {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: isFollowing ? "checkmark" : "plus")
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            ZStack {
                                Image(systemName: "plus")
                                    .opacity(isFollowing ? 0 : 1)
                                    .scaleEffect(isFollowing ? 0.85 : 1)

                                Image(systemName: "checkmark")
                                    .opacity(isFollowing ? 1 : 0)
                                    .scaleEffect(isFollowing ? 1 : 0.85)
                            }
                        }
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(selectedAccent.color)
                    .frame(width: 12, height: 12)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.primary.opacity(0.6), lineWidth: 0.5))
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
                .buttonStyle(.plain)
                .padding(4)
                .contentShape(Circle())
            }
        }
    }
    private var setchipSize: ChipSize {
        UIScreen.main.bounds.width < 400 ? .compact : .medium
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
    
    private func toggleFollow() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let currentUID = user.uid

        guard currentUID != currentUserID else {
            
            return
        }
        
        isLoadingFollow = true
        let db = Firestore.firestore()
        
        
        
        let targetDoc = db.collection(Coll.followers).document(currentUserID)
        let meDoc     = db.collection(Coll.followers).document(currentUID)
        
        let batch = db.batch()
        
        if isFollowing {
            
            batch.setData(["Followers": [currentUID: FieldValue.delete()]], forDocument: targetDoc, merge: true)
            batch.setData(["Following": [currentUserID: FieldValue.delete()]],   forDocument: meDoc,     merge: true)
        } else {
            
            batch.setData(["Followers": [currentUID: true]], forDocument: targetDoc, merge: true)
            batch.setData(["Following": [currentUserID: true]],     forDocument: meDoc,     merge: true)
        }
        
        batch.commit { error in
            DispatchQueue.main.async {
                self.isLoadingFollow = false
                if let error = error {
                    print("")
                    return
                }
                self.isFollowing.toggle()
                self.followersCount += self.isFollowing ? 1 : -1
                if self.followersCount < 0 { self.followersCount = 0 }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                
                if self.isFollowing {
                    let author_name = sharedData.ALLUSERNAMES[currentUID] ?? ""
                    publishFunctionality.notifyFollowerThatIfollow(recepient_uid: currentUserID, author_uid: currentUID, author_name: author_name) { result in
                        switch result {
                        case .success():
                            print("")
                        case .failure(let error):
                            print("")
                        }
                    }
                }
            }
        }
    }
        
    private func fetchFollowState() {
        guard let currentUID = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore().collection(Coll.followers).document(currentUserID)

        ref.getDocument { snapshot, error in
            if let error = error {
                
                return
            }
            let followersMap = (snapshot?.get("Followers") as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                self.isFollowing = followersMap.keys.contains(currentUID)
                self.followersCount = followersMap.count
            }
        }
    }

    private var followButton: some View {
        Button {
            guard !isLoadingFollow else { return }
            toggleFollow()
        } label: {
            HStack(spacing: 6) {
                if isLoadingFollow {
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.footnote.weight(.semibold))
                }
                Text(isFollowing ? "Following" : "Follow")
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .circular)
                    .fill(isFollowing ? Color.secondary.opacity(0.15) : .clear)
                    .background(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: isFollowing
                                    ? [Color.gray.opacity(0.5), Color.gray.opacity(0.3)]
                                    : [Color.cyan, Color.purple],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.2), value: isFollowing)
        .accessibilityLabel(isFollowing ? "Unfollow" : "Follow")
        .accessibilityHint("Double tap to toggle following state")
    }
}

struct UserActionSheet: View {
    let currentUserID: String
    let accent: Color
    var onCancel: () -> Void

    // new callbacks
    var onReportName: () -> Void
    var onReportBio: () -> Void
    var onReportAvatar: () -> Void
    var onBlockAction: () -> Void
    var onUnBlockAction: () -> Void

    @EnvironmentObject var sharedData: SharedData
    @State private var shown = false
    @GestureState private var dragY: CGFloat = 0
    @State private var showingReportOptions = false

    private let corner: CGFloat = 22

    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    var body: some View {
        ZStack(alignment: .bottom) {
            // SCRIM
            Color.black.opacity(shown ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) { shown = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onCancel() }
                }

            // SHEET CONTENT
            VStack(spacing: 14) {
                // Grabber
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                // MARK: Report Section
                VStack(spacing: 10) {
                    // The main "Report" toggle button
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showingReportOptions.toggle()
                        }
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        #endif
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.bubble")
                            Text("report".localized())
                                .fontWeight(.semibold)
                            Spacer()
                            
                            Image(systemName: showingReportOptions ? "chevron.down" : "chevron.up")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                                .id(showingReportOptions) // forces transition on swap

                        }

                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    // Expandable sub-options, sliding open
                    if showingReportOptions {
                        VStack(spacing: 8) {
                            Button {
                                onReportName()
                                dismissSheet()
                            } label: {
                                reportRow(icon: "textformat", title: "report_name".localized())
                            }

                            Button {
                                onReportBio()
                                dismissSheet()
                            } label: {
                                reportRow(icon: "person.text.rectangle", title: "report_biography".localized())
                            }

                            Button {
                                onReportAvatar()
                                dismissSheet()
                            } label: {
                                reportRow(icon: "photo", title: "report_image".localized())
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if sharedData.blockedUserIDs.contains(currentUserID) {
                        Button {
                            onUnBlockAction()
                            dismissSheet()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                Text("unblock_user".localized()).fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green.opacity(0.18))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            onBlockAction()
                            dismissSheet()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                Text("block_user".localized()).fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.18))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0).frame(height: 10)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in:
                RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: -2)
            .offset(y: (shown ? 0 : 500) + max(0, dragY))
            .gesture(
                DragGesture(minimumDistance: 5)
                    .updating($dragY) { value, state, _ in
                        if value.translation.height > 0 { state = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.velocity.height > 600 {
                            dismissSheet()
                        }
                    }
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { shown = true }
        }
    }

    private func dismissSheet() {
        withAnimation(.spring()) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onCancel() }
    }

    // MARK: Reusable row builder
    @ViewBuilder
    private func reportRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.primary)
            Text(title).fontWeight(.semibold)
                .foregroundStyle(Color.primary)
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.18))
        )
    }
}

