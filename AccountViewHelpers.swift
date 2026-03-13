//
//  AccountViewHelpers.swift
//  Vibro
//
//  Created by lyubcsenko on 22/09/2025.
//
import SwiftUI
import FirebaseAuth
import Firebase
import FirebaseStorage
import FirebaseFirestore
import CoreHaptics
import PhotosUI


enum FeedSection { case posts, models, following, followers}

struct UserData: Identifiable {
    let id: String
    let uid: String
    let userName: String
    let followers: Int
    var posts: Int
    var models: Int
}
enum ChipSize {
    case regular, medium, compact
    
    var icon: CGFloat {
        switch self {
        case .regular: return 13
        case .medium:  return 12
        case .compact: return 11
        }
    }
    var title: CGFloat {
        switch self {
        case .regular: return 11
        case .medium:  return 10.5
        case .compact: return 10
        }
    }
    var value: CGFloat {
        switch self {
        case .regular: return 11
        case .medium:  return 10.5
        case .compact: return 10
        }
    }
    var hSpacing: CGFloat {
        switch self {
        case .regular: return 6
        case .medium:  return 5
        case .compact: return 4
        }
    }
    var hPad: CGFloat {
        switch self {
        case .regular: return 12
        case .medium:  return 10
        case .compact: return 9
        }
    }
    var vPad: CGFloat {
        switch self {
        case .regular: return 7
        case .medium:  return 5.5
        case .compact: return 4
        }
    }
    var borderSel: CGFloat {
        switch self {
        case .regular: return 1.2
        case .medium:  return 1.1
        case .compact: return 1.0
        }
    }
    var border: CGFloat {
        switch self {
        case .regular: return 0.75
        case .medium:  return 0.7
        case .compact: return 0.6
        }
    }
    var shadowR: CGFloat {
        switch self {
        case .regular: return 6
        case .medium:  return 5
        case .compact: return 4
        }
    }
    var shadowRY: CGFloat {
        switch self {
        case .regular: return 4
        case .medium:  return 3.5
        case .compact: return 3
        }
    }
    var shadowRUnsel: CGFloat {
        switch self {
        case .regular: return 3
        case .medium:  return 2.5
        case .compact: return 2
        }
    }
    var shadowRYUnsel: CGFloat {
        switch self {
        case .regular: return 2
        case .medium:  return 2
        case .compact: return 2
        }
    }
}
struct CardFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}




struct PageSwipeLock: ViewModifier {
    let isLocked: Bool
    let threshold: CGFloat = 16

    func body(content: Content) -> some View {
        if isLocked {
            content
                .highPriorityGesture(
                    DragGesture(minimumDistance: threshold),
                    including: .gesture // this reliably preempts the page view's pan
                )
        } else {
            content
        }
    }
}


extension View {
    func lockPageSwipe(_ isLocked: Bool) -> some View {
        modifier(PageSwipeLock(isLocked: isLocked))
    }
}

extension View {
    @ViewBuilder
    func liftOverHeader(_ lift: Bool, by amount: CGFloat) -> some View {
        if lift {
            self
                .padding(.top, -amount)   // move up over the header
                .zIndex(10)              // render above the header
        } else {
            self
        }
    }
}


struct BlogCard: View {
    enum Mode {
        case view
        case edit(title: Binding<String>, body: Binding<String>, onCancel: () -> Void, onDone: () -> Void)
        
    }
    @FocusState private var focusedField: Field?
    private enum Field { case title, body }

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #endif
    private var cardHeight: CGFloat {
        #if os(iOS)
        if isPad { return 320 } // iPad gets a bit more breathing room
        let h = UIScreen.main.bounds.height
        switch h {
        case ..<670:   return 160   // iPhone SE / mini-like
        case ..<740:   return 200   // 6.1–6.3"
        default:       return 240   // tall phones
        }
        #else
        return 240
        #endif
    }
    @State private var likes: Int
    @State private var didLike: Bool = false
    let post: Post
    let userID: String
    let mode: Mode
    let showsAddButton: Bool
    let fromOtherPersonView: Bool
    let onAdd: (() -> Void)?
    let onDelete: ((String, String, @escaping (Error?) -> Void) -> Void)?
    init(
        post: Post,
        userID: String,
        mode: Mode = .view,
        showsAddButton: Bool = false,
        fromOtherPersonView: Bool = false,        // NEW (default off)
        onAdd: (() -> Void)? = nil,           // NEW
        onDelete: ((String, String, @escaping (Error?) -> Void) -> Void)? = nil   // NEW default
    ) {
        self.post = post
        self.userID = userID
        self.mode = mode
        self.showsAddButton = showsAddButton
        self.fromOtherPersonView = fromOtherPersonView
        self.onAdd = onAdd
        self.onDelete = onDelete

        _likes = State(initialValue: max(post.likedby.filter { !$0.isEmpty }.count, post.likes))
        let me = (Auth.auth().currentUser?.isAnonymous == false)
            ? Auth.auth().currentUser?.uid ?? ""
            : ""

        _didLike = State(initialValue: post.likedby.contains(me))
    }

    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @EnvironmentObject var forumFunctionality: ForumFunctionality
    @State private var showReportDialog = false

    // Original relative-time, plus an overload for a custom date
    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let seconds = Int(interval)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if seconds < 60 {
            // Show “1 second ago”, “2 seconds ago”, etc. (vs “Just now”)
            return "\(seconds) second\(seconds == 1 ? "" : "s") ago"
        } else if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    private var relativeTimeString: String { relativeTime(from: post.date) }
    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }
    private var isCreator: Bool {
        Auth.auth().currentUser?.isAnonymous == false &&
        Auth.auth().currentUser?.uid == userID

    }
    
    @EnvironmentObject var sharedData: SharedData

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let dynamicHeight = max(160, proxy.size.height - gap)
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    switch mode {
                    case .view:
                        // Title (non-scrollable)
                        Text(post.title)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Body (scrollable)
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(post.preview)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 56) // leave room for bottom bar
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    case .edit(let title, let body, _, _):
                        // Header (non-scrollable)
                        TextField("title".localized(), text: title)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .tint(.primary)              // cursor & accent color
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                            .overlay(alignment: .leading) {
                                if title.wrappedValue.isEmpty {
                                    Text("title".localized())
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .allowsHitTesting(false)
                                }
                            }
                            .focused($focusedField, equals: .title)
                            .onChange(of: title.wrappedValue) { new in
                                if new.count > 120 {
                                    DispatchQueue.main.async {
                                        title.wrappedValue = String(new.prefix(120))
                                    }
                                }
                            }
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: body)
                                .font(.body)
                                .tint(.primary)              // cursor & accent color
                                .scrollContentBackground(.hidden)   // keep if you want clear bg
                                .foregroundStyle(.primary)          // make editable text readable
                                .focused($focusedField, equals: .body)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .padding(.bottom, 56)               // keep your bottom bar gap if needed
                            
                            if body.wrappedValue.isEmpty {
                                Text("write_new_post".localized())
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)        // don’t block taps to the editor
                            }
                        }
                        .contentShape(Rectangle())                  // make the whole area tappable
                        .onTapGesture { focusedField = .body }
                        .frame(maxHeight: .infinity)
                        
                        
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                
                .frame(height: dynamicHeight) // <-- uses headerHeight
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .allowsHitTesting(false)
                            .preference(key: CardFrameKey.self,
                                        value: geo.frame(in: .named("pagerSpace")))
                    }
                )
                
                // Non-blocking long press (you already had this)
                .overlay {
                    if !isEditing {
                        LongPressPassthrough(minimumDuration: 0.6, allowableMovement: 30) {
                            showReportDialog = true
                        }
                    }
                }
                
                .contextMenu {
                    // DELETE — only visible to creator
                    if isCreator {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDelete?(userID, post.id) { err in
                                if let err = err {
                                    print("Delete failed: \(err.localizedDescription)")
                                } else {
                                    print("Post deleted: \(post.id)")
                                }
                            }
                        } label: {
                            Label("delete".localized(), systemImage: "trash")
                        }
                    }

                    // REPORT — available to everyone
                    Button(role: .destructive) {
                        if
                            let user = Auth.auth().currentUser,
                            !user.isAnonymous
                        {
                            let currentUID = user.uid
                            forumFunctionality.sendUserReport(
                                forumTag: "post",
                                reason: post.id,
                                reportedUserUID: userID
                            ) { result in
                                switch result {
                                case .success(let id): print("Post report filed: \(id)")
                                case .failure(let error): print("Post report failed: \(error.localizedDescription)")
                                }
                            }
                        }


                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("report".localized(), systemImage: "exclamationmark.bubble")
                    }

                    // SHARE — optional, nice addition
                    if let shareURL = URL(string: "https://links.bi-mach.com/post/\(userID)/\(post.id)") {
                        ShareLink(item: shareURL, subject: Text("Check out this post")) {
                            Label("share".localized(), systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Group {
                    switch mode {
                    case .view:
                        HStack {
                            Text(relativeTimeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button {
                                guard
                                    let user = Auth.auth().currentUser,
                                    !user.isAnonymous
                                else { return }

                                let currentUID = user.uid

                                let oldDidLike = didLike
                                let oldLikes = likes
                                didLike.toggle()
                                likes += didLike ? 1 : -1
                                togglePostLike(authorUID: userID,
                                               postID: post.id,
                                               userUID: currentUID) { result in
                                    switch result {
                                    case .success(let nowLiked):
                                        didLike = nowLiked
                                        likes = oldLikes + (nowLiked ? 1 : -1)
                                    case .failure:
                                        didLike = oldDidLike
                                        likes = oldLikes
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: didLike ? "heart.fill" : "heart")
                                        .foregroundStyle(selectedAccent.color)
                                    Text("\(likes)")
                                        .font(.subheadline)
                                        .foregroundStyle(selectedAccent.color)
                                }
                            }
                            .buttonStyle(.plain)
                            
                        }
                        
                    case .edit:
                        HStack {
                            Text(relativeTime(from: Date().addingTimeInterval(-1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    // Optional: make it feel anchored within the card
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .opacity(0.9)
                        .blur(radius: 0.1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                
            }

        
        }
    }


    // MARK: - Like toggle (unchanged)
    func togglePostLike(authorUID: String,
                        postID: String,
                        userUID: String,
                        completion: @escaping (Result<Bool, Error>) -> Void) {
        let db = Firestore.firestore()
        let docRef = db.collection("Followers").document(authorUID)

        docRef.getDocument { snapshot, error in
            if let error = error { completion(.failure(error)); return }

            let data = snapshot?.data() ?? [:]

            // Detect which layout is used for this post
            let postsNested = data["Posts"] as? [String: Any]
            let nestedTarget = postsNested?[postID] as? [String: Any]
            let flatTarget   = data["Posts.\(postID)"] as? [String: Any]

            enum Layout { case nested, flat, none }
            let layout: Layout = nestedTarget != nil ? .nested : (flatTarget != nil ? .flat : .none)

            // Read current likedby, regardless of layout
            let rawLikedBy: [String]
            switch layout {
            case .nested:
                rawLikedBy = (nestedTarget?["Likedby"] as? [String]) ?? []
            case .flat:
                rawLikedBy = (flatTarget?["Likedby"] as? [String]) ?? []
            case .none:
                rawLikedBy = []
            }

            var likedBy = rawLikedBy.filter { !$0.isEmpty }
            let alreadyLiked = likedBy.contains(userUID)

            // Compute new count
            let newCount = max(likedBy.count + (alreadyLiked ? -1 : 1), 0)

            // Build update keys depending on layout
            let likedByKey: AnyHashable
            let likesCountKey: AnyHashable

            switch layout {
            case .nested, .none:
                likedByKey = "Posts.\(postID).Likedby"
                likesCountKey = "Posts.\(postID).postLikes"
            case .flat:
                likedByKey = FieldPath([ "Posts.\(postID)", "Likedby" ])
                likesCountKey = FieldPath([ "Posts.\(postID)", "postLikes" ])
            }

            // First: update the array using arrayUnion/arrayRemove at the correct path
            let arrayChange: Any = alreadyLiked
                ? FieldValue.arrayRemove([userUID])
                : FieldValue.arrayUnion([userUID])

            docRef.updateData([ likedByKey: arrayChange ]) { err in
                if let err = err {
                    completion(.failure(err)); return
                }

                // Second: write the exact count so counter matches array
                docRef.updateData([ likesCountKey: newCount ]) { err2 in
                    if let err2 = err2 {
                        completion(.failure(err2))
                    } else {
                        completion(.success(!alreadyLiked))
                    }
                }
            }
        }
    }
}
struct BlogPager: View {
    @EnvironmentObject var sharedData: SharedData
    @Binding var posts: [Post]
    let userID: String
    let otherPersonView: Bool
    @Binding var index: Int
    var onSend: ((String, String) -> Void)?
    var onCreate: ((Post) -> Void)? = nil
    var onDeleteIn: ((String, String, @escaping (Error?) -> Void) -> Void)?
    var chevronSize: CGFloat = 28
    private let draftTag = -999  // keep distinct


    @State private var isCreating = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    
    // Paging animation
    private let pageAnimDuration: TimeInterval = 0.25
    var animation: Animation { .easeInOut(duration: pageAnimDuration) }

    // Auto-scroll cadence (long-press)
    @State private var cadence: TimeInterval = 0.33          // will be reset when starting
    private let minCadence: TimeInterval = 0.16              // clamp: don't go faster than ~6 pps
    private let rampFactor: Double = 0.90                    // 10% faster each tick

    @State private var isEditing = false
    
    @State private var lastStepAt: Date = .distantPast
    @State private var autoTimer: Timer? = nil
    @State private var autoDirection: Int = 0
    private let autoInterval: TimeInterval = 0.09  // fast speed
    private var isAtFirst: Bool { index <= 0 }
    private var isAtLast: Bool  { index >= max(posts.count - 1, 0) }
    let totalH = UIScreen.main.bounds.height
    @State private var currentCardFrame: CGRect = .zero
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TabView(selection: $index) {
                    
                    ForEach(posts.indices, id: \.self) { i in
                        let showPlus = (i == 0 && !isCreating)
                        
                        BlogCard(
                            post: posts[i],
                            userID: userID,
                            mode: .view,
                            showsAddButton: showPlus,
                            fromOtherPersonView: otherPersonView,
                            onAdd: { startCompose() },
                            onDelete: { uid, postID, done in
                                onDeleteIn?(uid, postID) { err in
                                    if err == nil, let removeIdx = posts.firstIndex(where: { $0.id == postID }) {
                                        posts.remove(at: removeIdx)
                                        index = min(index, max(posts.count - 1, 0))
                                    }
                                    done(err)
                                }
                            }
                        )
                        .tag(i)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .frame(minHeight: 160)   // ✅ again, min height clamp
                    }
                }
                .preference(key: IsCreatingKey.self, value: isCreating)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(isCreating ? nil : animation, value: index)
                .coordinateSpace(name: "pagerSpace")
                .lockPageSwipe(isCreating)
                .onPreferenceChange(CardFrameKey.self) { rect in
                    currentCardFrame = rect
                }
                .padding(.vertical, UIScreen.main.bounds.height * 0.02)   // ⬅️ same top & bottom padding as the wheel's sideInsetz
 =
                if isCreating {
                    BlogCard(
                        post: draftPost,
                        userID: userID,
                        mode: .edit(
                            title: $draftTitle,
                            body: $draftBody,
                            onCancel: cancelCompose,
                            onDone: {
                                let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !title.isEmpty || !body.isEmpty else { cancelCompose(); return }
                                onSend?(title, body)
                                cancelCompose()
                            }
                        ),
                        showsAddButton: false,
                        fromOtherPersonView: otherPersonView,
                        onAdd: nil,
                        onDelete: nil
                    )
                    .offset(y: isCreating ? 12 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Blog pager")
        .onAppear {
            print("DBG | isCreating=\(isCreating) selection=\(index) tags=\( (isCreating ? [draftTag] : []) + Array(posts.indices) ) posts.count=\(posts.count)")
            clampIndexForCurrentPosts()
        }
        .onChange(of: posts.count) { _ in clampIndexForCurrentPosts() }
        .onChange(of: userID) { _ in clampIndexForCurrentPosts() }

        .onDisappear { stopAutoScroll() }
        .overlay(alignment: .bottomTrailing) {
            let titleTrimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyTrimmed  = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let bothFilled   = !titleTrimmed.isEmpty && !bodyTrimmed.isEmpty
            let isAuthorized = Auth.auth().currentUser?.isAnonymous == false


            let fabKey = (!isCreating ? "plus" : (bothFilled ? "check" : "x"))

            Group {
                if !isCreating {
                    fabButton(systemName: "plus", accessibility: "Create new post") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        startCompose()
                    }
                } else if bothFilled {
                    fabButton(systemName: "checkmark", accessibility: "Post") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSend?(titleTrimmed, bodyTrimmed)
                        cancelCompose()
                    }
                } else {
                    fabButton(systemName: "xmark", accessibility: "Discard post") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        cancelCompose()
                    }
                }
            }
            .id(fabKey) // ✅ forces a proper transition when icon changes
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                removal:   .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92))
            ))
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: fabKey)

            // ✅ nice “float up/down” when entering create mode
            .offset(y: isCreating ? -10 : 0)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isCreating)

            .opacity(isAuthorized && !otherPersonView ? 1.0 : 0.0)
            .allowsHitTesting(isAuthorized && !otherPersonView)
            .padding(.trailing, 16)
            .padding(.bottom, 40)
            .zIndex(1000)
        }

    }
    @ViewBuilder
    private func sideControl(isLeft: Bool) -> some View {
        let enabled = isLeft ? !isAtFirst : !isAtLast
        let dir = isLeft ? -1 : 1
        
        Button {
            // Prevent single-step while turbo is active
            guard enabled, !isCreating, autoTimer == nil else { return }
            step(dir)
        } label: {
            Image(systemName: isLeft ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(enabled ? 1 : 0.35)
                .shadow(radius: 1)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLeft ? "Previous blog" : "Next blog")
        .disabled(!enabled || isCreating)
        .onLongPressGesture(
            minimumDuration: 0.5,
            maximumDistance: 40,
            pressing: { isPressing in
                // Only responsible for stopping when finger lifts/cancels
                if !isPressing { stopAutoScroll() }
            },
            perform: {
                // Fires after 0.5s; now it's legit a long press
                guard enabled, !isCreating else { return }
                startAutoScroll(direction: dir)
            }
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        // Also stop if we *arrive* at an edge via any means (swipe/tap)
        .onChange(of: index) { _ in
            if isAtFirst || isAtLast { stopAutoScroll() }
        }
    
    
    }

    // MARK: - Paging
    private func step(_ delta: Int) {
        guard !posts.isEmpty else { return }
        let new = index + delta
        index = min(max(new, 0), max(posts.count - 1, 0))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func startAutoScroll(direction: Int) {
        stopAutoScroll()
        autoDirection = direction

        // Start slightly slower than the page animation, then ramp up
        cadence = max(pageAnimDuration + 0.07, 0.32)

        scheduleAutoTimer(direction: direction)
    }

    private func scheduleAutoTimer(direction: Int) {
        autoTimer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { _ in
            guard !isCreating, !posts.isEmpty else { stopAutoScroll(); return }

            // stop at edges
            if (direction < 0 && isAtFirst) || (direction > 0 && isAtLast) {
                stopAutoScroll()
                return
            }

            step(direction)

            // accelerate (but never below minCadence)
            let next = max(minCadence, cadence * rampFactor)
            if abs(next - cadence) > 0.0001 {
                cadence = next
                autoTimer?.invalidate()
                scheduleAutoTimer(direction: direction)
            }
        }
        if let t = autoTimer { RunLoop.current.add(t, forMode: .common) }
    }

    private func stopAutoScroll() {
        autoTimer?.invalidate()
        autoTimer = nil
        autoDirection = 0
    }
    private func startCompose() {
        draftTitle = ""
        draftBody = ""
        withAnimation(.spring()) {
            isCreating = true
        }
    }

    private func cancelCompose() {
        withAnimation(.spring()) {
            isCreating = false
        }
        draftTitle = ""
        draftBody = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopAutoScroll()
    }


    private var draftPost: Post {
        Post(
            id: "DRAFT-\(UUID().uuidString)",
            title: draftTitle,
            preview: draftBody,
            date: Date(),          // 👈 moved before likes/likedby
            likes: 0,
            likedby: []
        )
    }
    
    private func clampIndexForCurrentPosts() {
        if isCreating {
            index = draftTag
            return
        }
        if posts.isEmpty {
            index = 0
        } else {
            index = max(0, min(index, posts.count - 1))
        }
    }
    @ViewBuilder
    private func fabButton(systemName: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)

                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

}

// 1) PreferenceKey somewhere in your file
struct IsCreatingKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}


struct LongPressPassthrough: UIViewRepresentable {
    var minimumDuration: TimeInterval = 0.6
    var allowableMovement: CGFloat = 30
    var onBegan: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = true

        let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = minimumDuration
        lp.allowableMovement = allowableMovement

        // 👇 These are the keys: do not block the TabView's pan
        lp.cancelsTouchesInView = false
        lp.delaysTouchesBegan = false
        lp.delaysTouchesEnded = false

        view.addGestureRecognizer(lp)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        let onBegan: () -> Void
        init(onBegan: @escaping () -> Void) { self.onBegan = onBegan }

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            if gr.state == .began { onBegan() }
        }
    }
}
]
