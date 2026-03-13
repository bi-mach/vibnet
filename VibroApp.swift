//
//  VibroApp.swift
//  Vibro
//
//  Created by lyubcsenko on 16/04/2025.
//

import SwiftUI
import UIKit
import Firebase
import FirebaseDatabase
import CoreHaptics
import PhotosUI
import FirebaseAuth
import Foundation

struct AIRespondResponse: Codable {
    let status: String
}

struct AIRespondRequest: Codable {
    let userId: String
    let message: String
    let language: String
}



@MainActor
func signInAnonymouslyIfNeeded() async throws {
    // If already signed in (anonymous or not), do nothing
    if Auth.auth().currentUser != nil { return }

    // Otherwise sign in anonymously
    _ = try await Auth.auth().signInAnonymously()
}

final class TranslateAPI {

    // ✅ Replace with YOUR real Cloud Run URL
    private let baseURL = URL(string: "https://translate-api-1047255165048.europe-west1.run.app")!

    func translate(
        text: String,
        targetLanguage: String,
        sourceLanguage: String? = nil
    ) async throws -> TranslateResponse {

        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }

        let idToken = try await user.getIDToken(forcingRefresh: true)

        var request = URLRequest(
            url: baseURL.appendingPathComponent("translate"),
            timeoutInterval: 15
        )

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body = TranslateRequest(
            text: text,
            targetLanguageCode: targetLanguage,
            sourceLanguageCode: sourceLanguage
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "error"
            throw NSError(
                domain: "TranslateAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: serverMessage]
            )
        }

        return try JSONDecoder().decode(TranslateResponse.self, from: data)
    }
}


class SharedData: ObservableObject {
    @Published var modelName: String = ""
    @Published var customModelName: String = ""
    @Published var originalModelName: String = ""
    @Published var Trial: Bool = false
    @Published var usesLS: Bool = false
    @Published var favouriteModels: Set<Model> = []
    @Published var listOfFavModels: [String] = []
    
    @Published var orderForConnections: [Int: [Int: Int]] = [:]
    @Published var rateForConnections: [Int: [Int: Double]] = [:]
    @Published var largestShellValue: Int = 0
    @Published var TEMPTapData: [Int: [Int: [TapEntry]]] = [:]
    @Published var TapCircleSize: CGFloat = 0.0
    @Published var personalModelsData: Set<Model> = []
    @Published var publishedModels: [String: Model] = [:]
    @Published var translatedCommandNames: [String: [Int: [Int: String]]] = [:]
    @Published var publishedFavModels: [String: Model] = [:]
    @Published var ALLUSERNAMES: [String: String] = [:]
    @Published var cachedCommandData: [String: [Int: [Int: [TapEntry]]]] = [:]
    @Published var cachedCommandNames: [String: [Int: [Int: String]]]  = [:]
    @Published var GlobalModelsData: [Int: String]  = [:]
    @Published var blockedUserIDs: [String] = []
    @Published var modelImageURLs: [String: URL] = [:]
    @Published var favouriteModelImageURLs: [String: URL] = [:]
    @Published var imageAccentColors: [String: Color] = [:]   // <-- add here
    @Published var publishedAccentColors: [String: Color] = [:]   // <-- add here
    @Published var publishedModelImageURLs: [String: URL] = [:]   // <-- add here
    @Published var hasReloaded: Bool = false
    @Published var headerHeight: CGFloat = .zero
    @Published var bottomOverlayClearance: CGFloat = .zero
    @Published var alreadyUsed: [String] = []
    @Published var myUsername: String = ""
    @Published var appLanguage: String = ""
}
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
}
enum EntryType: String { case m1, m2, servo, delay }

typealias TAPSConfig = [Int: [Int: [TapEntry]]]


struct TapEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let key: Int
    let modelName: String
    let entryType: String
    let value: Double
    var groupId: Int

    // Legacy single value (keep for migration / compatibility if you want)
    var smoothFactor: Double = 0.5

    // ✅ NEW per-side values
    var smoothFactorStart: Double = 0.5
    var smoothFactorEnd: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case key, modelName, entryType, value, id, groupId
        case smoothFactor
        case smoothFactorStart, smoothFactorEnd
    }

    init(key: Int,
         modelName: String,
         entryType: String,
         value: Double,
         groupId: Int = 0,
         smoothFactor: Double = 0.5,              // legacy
         smoothFactorStart: Double? = nil,        // ✅ optional so you can keep old call sites
         smoothFactorEnd: Double? = nil,          // ✅ optional so you can keep old call sites
         id: UUID = UUID()) {
        self.key = key
        self.modelName = modelName
        self.entryType = entryType
        self.value = value
        self.groupId = groupId

        self.smoothFactor = smoothFactor
        let s = smoothFactor
        self.smoothFactorStart = smoothFactorStart ?? s
        self.smoothFactorEnd   = smoothFactorEnd   ?? s

        self.id = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(Int.self, forKey: .key)
        modelName = try c.decode(String.self, forKey: .modelName)
        entryType = try c.decode(String.self, forKey: .entryType)
        value = try c.decode(Double.self, forKey: .value)
        groupId = try c.decodeIfPresent(Int.self, forKey: .groupId) ?? 0
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()

        // 1) read legacy smoothFactor if present, else default
        let legacy = try c.decodeIfPresent(Double.self, forKey: .smoothFactor) ?? 0.5
        smoothFactor = legacy

        // 2) prefer new keys if present, else fall back to legacy
        smoothFactorStart = try c.decodeIfPresent(Double.self, forKey: .smoothFactorStart) ?? legacy
        smoothFactorEnd   = try c.decodeIfPresent(Double.self, forKey: .smoothFactorEnd)   ?? legacy
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(modelName, forKey: .modelName)
        try c.encode(entryType, forKey: .entryType)
        try c.encode(value, forKey: .value)
        try c.encode(groupId, forKey: .groupId)

        // keep writing legacy if you like (optional, but harmless)
        try c.encode(smoothFactor, forKey: .smoothFactor)

        // ✅ write new keys
        try c.encode(smoothFactorStart, forKey: .smoothFactorStart)
        try c.encode(smoothFactorEnd,   forKey: .smoothFactorEnd)
    }

    static func == (lhs: TapEntry, rhs: TapEntry) -> Bool {
        lhs.key == rhs.key &&
        lhs.modelName == rhs.modelName &&
        lhs.entryType == rhs.entryType &&
        lhs.value == rhs.value &&
        lhs.groupId == rhs.groupId &&
        lhs.smoothFactor == rhs.smoothFactor &&
        lhs.smoothFactorStart == rhs.smoothFactorStart &&
        lhs.smoothFactorEnd == rhs.smoothFactorEnd
    }
}
extension TapEntry: CustomStringConvertible {
    var description: String {
        "TapEntry(key:\(key), model:\(modelName), type:\(entryType), value:\(value), groupId:\(groupId), start:\(smoothFactorStart), end:\(smoothFactorEnd))"
    }
}

extension TapEntry {
    func withValue(_ newValue: Double) -> TapEntry {
        .init(
            key: key,
            modelName: modelName,
            entryType: entryType,
            value: newValue,
            groupId: groupId,
            smoothFactor: smoothFactor,
            smoothFactorStart: smoothFactorStart,
            smoothFactorEnd: smoothFactorEnd,
            id: id
        )
    }

    func with(groupId newValue: Int) -> TapEntry {
        .init(
            key: key,
            modelName: modelName,
            entryType: entryType,
            value: value,
            groupId: newValue,
            smoothFactor: smoothFactor,
            smoothFactorStart: smoothFactorStart,
            smoothFactorEnd: smoothFactorEnd,
            id: id
        )
    }

    func withType(_ type: String) -> TapEntry {
        .init(
            key: key,
            modelName: modelName,
            entryType: type,
            value: value,
            groupId: groupId,
            smoothFactor: smoothFactor,
            smoothFactorStart: smoothFactorStart,
            smoothFactorEnd: smoothFactorEnd,
            id: id
        )
    }

    func withSmooth(start: Double, end: Double) -> TapEntry {
        .init(
            key: key,
            modelName: modelName,
            entryType: entryType,
            value: value,
            groupId: groupId,
            smoothFactor: smoothFactor,
            smoothFactorStart: start,
            smoothFactorEnd: end,
            id: id
        )
    }
}


struct ModelSnapshot: Codable {
    var name: String
    var description: String
    var keyword: String
    var creator: String
    var rate: Int
    var creationDate: String
    var publishDate: String
    var justCreated: Bool
    var createdWithVib: Bool

    // ✅ New field (backwards-compatible)
    var commandNames: [Int: [Int: String]] = [:]
}


extension Model {
    static let creationFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yy-MM-dd-HH-mm-ss"
        return df
    }()

    var creationDateValue: Date? {
        Self.creationFormatter.date(from: creationDate)
    }
    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let rf = RelativeDateTimeFormatter()
        rf.unitsStyle = .full // "3 minutes ago"; use .short for "3 min. ago"
        return rf
    }()
    var creationRelative: String {
        guard let date = creationDateValue else { return "—" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}



class Model: Identifiable, ObservableObject, Hashable {
    static func == (lhs: Model, rhs: Model) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id = UUID()
    @Published var name: String
    @Published var description: String
    @Published var keyword: String
    @Published var creator: String
    @Published var rate: Int
    @Published var creationDate: String   // <-- String
    @Published var publishDate: String
    @Published var justCreated: Bool
    @Published var createdWithVib: Bool

    init(name: String, description: String, keyword: String, creator: String, rate: Int, creationDate: String, publishDate: String, justCreated: Bool, createdWithVib: Bool) {
        self.name = name
        self.description = description
        self.keyword = keyword
        self.creator = creator
        self.rate = rate
        self.creationDate = creationDate
        self.publishDate = publishDate
        self.justCreated = justCreated
        self.createdWithVib = createdWithVib
    }
}


struct PersonalModel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let creationDate: String
}

struct Memory: Identifiable, Hashable {
    let id = UUID()
    let date: String
    let name: String
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct TranslateRequest: Codable {
    let text: String
    let targetLanguageCode: String
    let sourceLanguageCode: String?
}

struct TranslateResponse: Codable {
    let translatedText: String
    let detectedSourceLanguage: String?
}




enum FirebaseRefs {
    static let db: Database = {
        // europe-west1 endpoint for your DB
        let db = Database.database(url: "https://bi-mach-vibro-default-rtdb.europe-west1.firebasedatabase.app")
        // Optional: local persistence
        // db.isPersistenceEnabled = true
        return db
    }()
}

struct ForumPost: Identifiable, Equatable {
    let id: String
    let forumTag: String
    let messageType: String
    let text: String
    let userId: String
    let createdAt: TimeInterval   // seconds since 1970
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isAdjusting: Bool
    var onSave: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> some UIViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images // Only show images
        configuration.selectionLimit = 1 // Allow only one image selection
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                return
            }
            
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    if let uiImage = image as? UIImage {
                        self.parent.selectedImage = uiImage
                        self.parent.onSave(uiImage) // Save image to AppStorage
                        self.parent.isAdjusting = true
                    }
                }
            }
        }
    }
}
struct Popup<PopupContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var circleOffset: CGSize
    @Binding var TapCircleSize: CGFloat
    @Binding var userEmail: String
    @AppStorage("savedImageData") private var savedImageData: String = ""
    let popupContent: () -> PopupContent
    let backgroundImage: UIImage?
    let onDone: (UIImage) -> Void  // NEW
    func cropImage(from uiImage: UIImage, geometry: GeometryProxy) -> UIImage? {
        // Normalize the image to handle orientation issues
        let normalizedImage = normalizeImage(uiImage)
        
        // Calculate the circle size based on TapCircleSize
        let circleDiameter = TapCircleSize
        let circleRadius = circleDiameter / 2
        
        // Calculate the cropping rectangle
        let cropX = (geometry.size.width / 2 + circleOffset.width) - circleRadius
        let cropY = (geometry.size.height / 2 + circleOffset.height) - circleRadius
        let cropRect = CGRect(x: cropX, y: cropY, width: circleDiameter, height: circleDiameter)
        
        // Scale cropRect to match the UIImage's scale
        let imageScale = normalizedImage.size.width / geometry.size.width
        let scaledCropRect = CGRect(
            x: cropRect.origin.x * imageScale,
            y: cropRect.origin.y * imageScale,
            width: cropRect.width * imageScale,
            height: cropRect.height * imageScale
        )
        
        // Perform cropping
        guard let cgImage = normalizedImage.cgImage?.cropping(to: scaledCropRect) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            Spacer()
                            VStack {
                                Spacer()
                                
                                GeometryReader { popupGeometry in
                                    let popupRadius = popupGeometry.size.width / 2
                                    let circleRadius = TapCircleSize / 2
                                    let circleDiameter = TapCircleSize
                                    ZStack {
                                        if let uiImage = backgroundImage {
                                            // Display the background image scaled to the full popup size
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(
                                                    width: popupGeometry.size.width,
                                                    height: popupGeometry.size.height
                                                )
                                                .clipped()
                                                .allowsHitTesting(false) // Prevent background from intercepting touches
                                            
                                            // Draw the circle for cropping indication
                                            Circle()
                                                .strokeBorder(Color.blue, lineWidth: 2)
                                                .frame(width: circleDiameter, height: circleDiameter)
                                                .offset(circleOffset)
                                            
                                            // Gesture Area to move the circle
                                            Color.clear
                                                .contentShape(Rectangle()) // Entire view is tappable
                                                .gesture(
                                                    DragGesture(minimumDistance: 0) // Detect taps as drags with 0 distance
                                                        .onEnded { value in
                                                            let tapLocation = value.location
                                                            let newOffset = CGSize(
                                                                width: tapLocation.x - popupGeometry.size.width / 2,
                                                                height: tapLocation.y - popupGeometry.size.height / 2
                                                            )
                                                            
                                                            // Keep circle within bounds
                                                            let minX = -popupRadius + circleRadius
                                                            let maxX = popupRadius - circleRadius
                                                            let minY = -popupRadius + circleRadius
                                                            let maxY = popupRadius - circleRadius
                                                            
                                                            withAnimation(.easeOut(duration: 0.2)) {
                                                                circleOffset = CGSize(
                                                                    width: max(minX, min(maxX, newOffset.width)),
                                                                    height: max(minY, min(maxY, newOffset.height))
                                                                )
                                                            }
                                                        }
                                                )
                                        } else {
                                            Color.white // Fallback background
                                        }
                                    }
                                    .frame(
                                        width: popupGeometry.size.width,
                                        height: popupGeometry.size.height
                                    )
                                }
                                
                                Spacer()
                                
                                // Positioned text and button at the bottom
                                VStack {
                                    Text("Adjust Image Position")
                                        .font(.headline)
                                        .foregroundStyle(Color.black)
                                        .multilineTextAlignment(.center)
                                        .padding(.bottom, 10)
                                    
                                    Button("Done") {
                                        if let uiImage = backgroundImage,
                                           let croppedImage = cropImage(from: uiImage, geometry: geometry) {
                                            onDone(croppedImage)                     // <- update parent
                                            saveImageToServer(croppedImage)          // (optional) keep your @AppStorage write
                                        }
                                        isPresented = false
                                    }
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                                }
                                .padding(.bottom, 20) // Padding at the bottom of the popup
                            }
                            .frame(
                                width: geometry.size.width * 0.6,  // shrink width to 60% of screen
                                height: geometry.size.height * 0.4 // shrink height to 40% of screen
                            )

                            .cornerRadius(20)
                            .shadow(radius: 10)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
    private func saveImageToServer(_ image: UIImage) {
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            savedImageData = imageData.base64EncodedString()
        }
    }
    private func normalizeImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image // No rotation needed
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? image
    }
}

extension View {
    func popup<PopupContent: View>(
        isPresented: Binding<Bool>,
        circleOffset: Binding<CGSize>,
        TapCircleSize: Binding<CGFloat>,
        userEmail: Binding<String>,
        backgroundImage: UIImage?,
        @ViewBuilder content: @escaping () -> PopupContent,
        onDone: @escaping (UIImage) -> Void          // NEW
    ) -> some View {
        modifier(Popup(
            isPresented: isPresented,
            circleOffset: circleOffset,
            TapCircleSize: TapCircleSize,
            userEmail: userEmail,
            popupContent: content,
            backgroundImage: backgroundImage,
            onDone: onDone
        ))
    }
}

class LanguageObserver: ObservableObject {
    @Published var currentLanguage: String = LocalizationManager.shared.currentLanguage

    init() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(languageDidChange),
                                               name: Notification.Name("LanguageChanged"),
                                               object: nil)
    }
    
    @objc func languageDidChange() {
        self.currentLanguage = LocalizationManager.shared.currentLanguage
    }
}




@main
struct VibroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var functions = Functions()
    @StateObject private var personalModelsFunctions = PersonalModelsFunctions()
    @StateObject private var tapsFunctions = TapsFunctions()
    @StateObject private var sharedData = SharedData()
    @StateObject private var forumFunctionality = ForumFunctionality()
    @StateObject private var publishFunctionality = PublishFunctionality()
    @StateObject private var notifService = NotificationsService()

    @AppStorage("SelectedLanguage")
    private var selectedLanguage: String = LocalizationManager.shared.currentLanguage

    @State private var didBootstrap = false
    @State private var isBootstrapped = false
    @State private var showLaunchOverlay = true
    @State private var launchOpacity = 1.0
    @State private var contentOpacity = 0.0

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("[INFO] Firebase configured in VibroApp init.")
        }
        LocalizationManager.shared.useSystemLanguage()
        
        sharedData.appLanguage = currentAppLanguage()
    }


    var body: some Scene {
        WindowGroup {
            ZStack {
                // Your real app UI (behind)
                ContentView()
                    .opacity(contentOpacity)
                    .animation(.easeOut(duration: 0.3), value: contentOpacity)
                    .environmentObject(functions)
                    .environmentObject(personalModelsFunctions)
                    .environmentObject(tapsFunctions)
                    .environmentObject(sharedData)
                    .environmentObject(forumFunctionality)
                    .environmentObject(publishFunctionality)
                    .environmentObject(notifService)

                // LaunchScreen look-alike (on top)
                if !showLaunchOverlay {
                    LaunchScreenView()
                        .ignoresSafeArea()
                        .opacity(launchOpacity)
                        .transition(.identity) // no animation
                }
            }
            .onAppear {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            .task {
                await bootstrapIfNeeded()
            }
            .onChange(of: isBootstrapped) { ready in
                guard ready else { return }

                // Ensure ContentView gets a chance to draw at least one frame
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.3)) {
                        contentOpacity = 1.0
                        launchOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showLaunchOverlay = false
                    }
                }
            }
        }
    }
    private func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        AppDelegate.shared = appDelegate
        sharedData.hasReloaded = true

        do {
            // ✅ Keep LaunchScreenView visible until THIS succeeds:
            _ = try await retrieveDocumentsAsync()

            // Optional: if you also want to wait for published models, keep it:
            try await fetchPublishedModelsAsync()

            // ✅ Remove splash overlay (no animation)
            withAnimation(.none) {
                isBootstrapped = true
            }
        } catch {
            // If you never want to leave the splash on failure, just keep it false.
            // Or log:
            print("[ERROR] Bootstrap failed: \(error)")
        }
    }

    // MARK: - Async wrappers

    private func fetchPublishedModelsAsync() async throws {
        try await withCheckedThrowingContinuation { cont in
            publishFunctionality.fetchAllPublishedModels { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let dict):
                        sharedData.publishedModels = dict
                        for (name, fav) in sharedData.publishedFavModels {
                            if let source = sharedData.publishedModels[name] {
                                fav.rate = source.rate
                            }
                        }
                        cont.resume()
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
        }
    }

    private func retrieveDocumentsAsync() async throws -> [Int: String] {
        try await withCheckedThrowingContinuation { cont in
            retrieveDocuments { result in
                cont.resume(with: result)
            }
        }
    }

    // MARK: - Your original retrieveDocuments (unchanged)
    private func retrieveDocuments(completion: @escaping (Result<[Int: String], Error>) -> Void) {
        let db = Firestore.firestore()
        let collection = db.collection("Models")
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
                    if firstError == nil { firstError = err }
                    return
                }
                guard let data = snap?.data() else { return }

                for (key, value) in data {
                    if key == "Connections" || key == "Rate" || key == "largestShellValue" { continue }
                    if let intKey = Int(key) {
                        if let s = value as? String { mergedModels[intKey] = s }
                        else if let n = value as? NSNumber { mergedModels[intKey] = n.stringValue }
                    }
                }

                if let connections = data["Connections"] as? [String: Any] {
                    for (outerKey, innerDictAny) in connections {
                        guard let outerIntKey = Int(outerKey),
                              let innerMap = innerDictAny as? [String: Any] else { continue }

                        var innerResult = mergedConnections[outerIntKey] ?? [:]
                        for (innerKey, innerValAny) in innerMap {
                            if let innerIntKey = Int(innerKey) {
                                if let v = innerValAny as? Int { innerResult[innerIntKey] = v }
                                else if let num = innerValAny as? NSNumber { innerResult[innerIntKey] = num.intValue }
                            }
                        }
                        mergedConnections[outerIntKey] = innerResult
                    }
                }

                if let rates = data["Rate"] as? [String: Any] {
                    for (outerKey, innerDictAny) in rates {
                        guard let outerIntKey = Int(outerKey),
                              let innerMap = innerDictAny as? [String: Any] else { continue }

                        var innerResult = mergedRates[outerIntKey] ?? [:]
                        for (innerKey, innerValAny) in innerMap {
                            if let innerIntKey = Int(innerKey) {
                                if let v = innerValAny as? Double { innerResult[innerIntKey] = v }
                                else if let num = innerValAny as? NSNumber { innerResult[innerIntKey] = num.doubleValue }
                            }
                        }
                        mergedRates[outerIntKey] = innerResult
                    }
                }

                if let lsv = data["largestShellValue"] as? Int { mergedLargestShellValue = lsv }
                else if let num = data["largestShellValue"] as? NSNumber { mergedLargestShellValue = num.intValue }
            }
        }

        group.notify(queue: .main) {
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
}
private struct LaunchScreenView: View {
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        switch selectedAppearance {
        case .system:
            return (colorScheme == .dark) ? .black : .white
        case .dark:
            return .black
        case .light:   // if your enum is `.white`, change this to `.white`
            return .white
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * 0.45)
            }
        }
    }
}
