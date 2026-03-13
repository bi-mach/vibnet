






import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Firebase
import FirebaseFirestore
import Foundation
import Speech
import GoogleSignIn
import CoreHaptics
import PhotosUI
import CoreBluetooth
import FirebaseAuth
import SceneKit
import simd
import UIKit
import AuthenticationServices
import CryptoKit
import WebKit
import Combine

public struct AppNotification: Identifiable, Equatable {
    public let id: String
    public let title: String
    public var content: String
    public var date: Date
    public var type: String?
    public var author: String?
    public var postID: String?
    public var isRead: Bool

    public init(
        id: String,
        title: String,
        content: String,
        date: Date,
        type: String? = nil,
        author: String? = nil,
        postID: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.date = date
        self.type = type
        self.author = author
        self.postID = postID
        self.isRead = isRead
    }
}

private enum Coll {
    static let users = "Users"
    static let followers = "Followers"
}

enum PendingAction {
    case account
    case forum
}

struct FollowerDoc: Codable {
    let userName: String
    enum CodingKeys: String, CodingKey { case userName = "UserName" }
}

struct AuthorSelection: Identifiable { let id: String }

private struct CompatListSpacing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.contentMargins(.vertical, 8)
        } else if #available(iOS 16, *) {
            content.listRowSpacing(8)           
        } else {
            content                             
        }
    }
}

private extension View {
    func compatListSpacing() -> some View { self.modifier(CompatListSpacing()) }
}
private enum DragMode { case undecided, vertical, horizontal }


struct NotificationsOverlay: View {
    @EnvironmentObject var notifService: NotificationsService
    @EnvironmentObject private var sharedData: SharedData
    @Binding var isPresented: Bool
    let notifications: [AppNotification]
    let onMarkRead: (String) -> Void
    let onShowAuthor: (String) -> Void
    let onDelete: (String) -> Void

    @State private var deletingIDs: Set<String> = []

    private func deleteSafely(_ id: String) {
        guard !deletingIDs.contains(id) else { return }
        deletingIDs.insert(id)

        
        DispatchQueue.main.async {
            onDelete(id)
            deletingIDs.remove(id)
        }
    }
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    var body: some View {
        NavigationStack {
            List {
                ForEach(notifications) { n in
                    let authorName = n.author.flatMap { sharedData.ALLUSERNAMES[$0] }

                    NotificationRow(
                        notification: n,
                        authorName: authorName,
                        onTap: {
                            if !n.isRead { onMarkRead(n.id) }
                            if let author = n.author, !author.isEmpty { onShowAuthor(author) }
                        },
                        onTapBadReview: {

                        },
                        onToggleRead: { notifService.toggleNotificationRead(n.id) },
                        onDelete: { deleteSafely(n.id) } 
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .disabled(deletingIDs.contains(n.id)) 
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .compatListSpacing()
            .animation(nil, value: notifications)
            .navigationTitle("notifications_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(UIColor.systemBackground), for: .navigationBar)
        }
    }
}



private struct NotificationRow: View {
    @Environment(\.colorScheme) private var scheme
    let notification: AppNotification
    let authorName: String?
    let onTap: () -> Void
    let onTapBadReview: () -> Void
    let onToggleRead: () -> Void
    let onDelete: () -> Void
    private let halfThreshold = UIScreen.main.bounds.width * 0.5
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .frame(width: 8, height: 8)
                .opacity(notification.isRead ? 0 : 1)
                .padding(.top, 6)
                .foregroundStyle(selectedAccent.color)

            VStack(alignment: .leading, spacing: 6) {
                Spacer().frame(height: 8)

                if notification.type == "new_friend_request" {
                    Text(notification.content.isEmpty ? " " : notification.content)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if notification.type == "new_post"{
                    Text(notification.title.isEmpty ? " " : notification.title)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    Text(notification.content.isEmpty ? " " : notification.content)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if notification.type == "new_model_from_following" {
                    Text(notification.title.isEmpty ? " " : notification.title)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                
                    
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if notification.type == "your_model_was_liked" {
                    Text(notification.title.isEmpty ? " " : notification.title)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    
                    Text(notification.content.isEmpty ? " " : notification.content)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if notification.type == "model_review_status" {
                    Text(notification.title.isEmpty ? " " : notification.title)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    
                    Text(notification.content.isEmpty ? " " : notification.content)
                        .font(.body.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(3)
                    
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())               
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.secondary.opacity(0.15))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.secondary.opacity(scheme == .dark ? 0.2 : 0.08))
                )
        )
        .onTapGesture {onTap()
            
        }

        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            
            Button {
                onDelete()                         
            } label: {
                
                Label("", systemImage: "")
                    .labelStyle(.iconOnly)
                    .opacity(0.01)
            }
            .tint(.red)                            
            .frame(width: halfThreshold)           
            .accessibilityHidden(true)

            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("delete".localized(), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onToggleRead() } label: {
                Label(notification.isRead ? "Unread" : "Read",
                      systemImage: notification.isRead ? "circlebadge.fill" : "checkmark.circle")
            }
            .tint(selectedAccent.color)
        }

        .accessibilityElement(children: .combine)
        .accessibilityHint(
            notification.isRead
            ? "Double tap to open. Swipe left to delete or mark unread."
            : "Double tap to open. Swipe left to delete or mark read."
        )
    }
}


struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EULASheet: View {
    @Environment(\.openURL) private var openURL
    private let termsWebsiteURL = URL(string: "https://www.bi-mach.com/terms-of-use")!

    private var bundledHTMLName: String {
        let lang = Locale.preferredLanguages.first ?? ""

        if lang.hasPrefix("ar") { return "TermsOfUse_arabic" }
        else if lang.hasPrefix("zh") { return "TermsOfUse_chinese_simplified" }
        else if lang.hasPrefix("hr") { return "TermsOfUse_croatian" }
        else if lang.hasPrefix("cs") { return "TermsOfUse_czech" }
        else if lang.hasPrefix("da") { return "TermsOfUse_danish" }
        else if lang.hasPrefix("nl") { return "TermsOfUse_dutch" }
        else if lang.hasPrefix("fi") { return "TermsOfUse_finnish" }
        else if lang.hasPrefix("de") { return "TermsOfUse_german" }
        else if lang.hasPrefix("he") { return "TermsOfUse_hebrew" }
        else if lang.hasPrefix("hi") { return "TermsOfUse_hindi" }
        else if lang.hasPrefix("hu") { return "TermsOfUse_hungarian" }
        else if lang.hasPrefix("it") { return "TermsOfUse_italian" }
        else if lang.hasPrefix("ja") { return "TermsOfUse_japanese" }
        else if lang.hasPrefix("ko") { return "TermsOfUse_korean" }
        else if lang.hasPrefix("pl") { return "TermsOfUse_polish" }
        else if lang.hasPrefix("ro") { return "TermsOfUse_romanian" }
        else if lang.hasPrefix("ru") { return "TermsOfUse_russian" }
        else if lang.hasPrefix("sk") { return "TermsOfUse_slovak" }
        else if lang.hasPrefix("es") { return "TermsOfUse_spanish" }
        else if lang.hasPrefix("sv") { return "TermsOfUse_swedish" }
        else if lang.hasPrefix("th") { return "TermsOfUse_thai" }
        else if lang.hasPrefix("tr") { return "TermsOfUse_turkish" }
        else if lang.hasPrefix("uk") { return "TermsOfUse_ukrainian" }
        else if lang.hasPrefix("vi") { return "TermsOfUse_vietnamese" }
        else { return "TermsOfUse" }
    }

    let preview: Bool
    var onAgree: () -> Void
    var onCancel: () -> Void

    @State private var hasChecked = false
    @State private var exportURL: URL?

    @State private var detent: PresentationDetent = .height(230)

    private var localHTMLURL: URL? {
        Bundle.main.url(forResource: bundledHTMLName, withExtension: "html")
    }

    private var isExpanded: Bool { detent == .large }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // Top-centre title + chevron (no animation)
                HStack {
                    Spacer()
                    Text("terms_of_use".localized())
                        .font(.headline)

                    Button {

                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.headline)
                            .padding(.leading, 6)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 10)

                Divider()

                // ✅ Keep this ALWAYS in the tree (prevents flash/recreate)
                Group {
                    if let fileURL = localHTMLURL {
                        LocalHTMLWebView(fileURL: fileURL)
                    } else {
                        ScrollView {
                            Text("Terms file missing from app bundle. Please add \(bundledHTMLName).html to your target.")
                                .padding()
                        }
                    }
                }
                .opacity(isExpanded ? 1 : 0)                  // hide when collapsed
                .allowsHitTesting(isExpanded)                 // no scrolling/taps when collapsed
                .accessibilityHidden(!isExpanded)             // optional
                .transaction { $0.animation = nil }   // <-- scoped here only
                if !preview {
                    if isExpanded { Divider() }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: hasChecked ? "checkmark.square.fill" : "square")
                                .onTapGesture { hasChecked.toggle() }

                            Text("i_have_read_and_agree_to_terms_of_use".localized())
                                .onTapGesture { hasChecked.toggle() }
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Button("cancel".localized(), action: onCancel)
                            Spacer()
                            Button("agree".localized(), action: onAgree)
                                .buttonStyle(.borderedProminent)
                                .disabled(!hasChecked)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isExpanded {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { openURL(termsWebsiteURL) } label: {
                            Image(systemName: "globe").imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Terms on Website")
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Image(systemName: "square.and.arrow.down").imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Download")
                        } else {
                            Button { exportURL = makeExportURL() } label: {
                                Image(systemName: "square.and.arrow.down").imageScale(.large)
                            }
                            .disabled(localHTMLURL == nil)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Download")
                        }
                    }
                }
            }
            .onChange(of: bundledHTMLName) { _ in
                exportURL = nil
            }
        }
        .presentationDetents([.height(230), .large], selection: $detent)
        .presentationDragIndicator(.hidden)

        // ✅ kill implicit animations tied to detent changes
        .transaction { $0.animation = nil }
    }

    private func makeExportURL() -> URL? {
        guard let sourceURL = localHTMLURL else { return nil }
        do {
            let data = try Data(contentsOf: sourceURL)
            let tempDir = FileManager.default.temporaryDirectory
            let safeName = bundledHTMLName.replacingOccurrences(of: " ", with: "_")
            let destURL = tempDir.appendingPathComponent("\(safeName).html")
            try data.write(to: destURL, options: [.atomic])
            return destURL
        } catch {
            print("Failed to create export URL: \(error)")
            return nil
        }
    }
}
struct EULASheetOld: View {
    @Environment(\.openURL) private var openURL
    private let termsWebsiteURL = URL(string: "https://www.bi-mach.com/terms-of-use")!

    private var bundledHTMLName: String {
        let lang = Locale.preferredLanguages.first ?? ""
        
        if lang.hasPrefix("ar") {
            return "TermsOfUse_arabic"
        } else if lang.hasPrefix("zh") {
            return "TermsOfUse_chinese_simplified"
        } else if lang.hasPrefix("hr") {
            return "TermsOfUse_croatian"
        } else if lang.hasPrefix("cs") {
            return "TermsOfUse_czech"
        } else if lang.hasPrefix("da") {
            return "TermsOfUse_danish"
        } else if lang.hasPrefix("nl") {
            return "TermsOfUse_dutch"
        } else if lang.hasPrefix("fi") {
            return "TermsOfUse_finnish"
        } else if lang.hasPrefix("de") {
            return "TermsOfUse_german"
        } else if lang.hasPrefix("he") {
            return "TermsOfUse_hebrew"
        } else if lang.hasPrefix("hi") {
            return "TermsOfUse_hindi"
        } else if lang.hasPrefix("hu") {
            return "TermsOfUse_hungarian"
        } else if lang.hasPrefix("it") {
            return "TermsOfUse_italian"
        } else if lang.hasPrefix("ja") {
            return "TermsOfUse_japanese"
        } else if lang.hasPrefix("ko") {
            return "TermsOfUse_korean"
        } else if lang.hasPrefix("pl") {
            return "TermsOfUse_polish"
        } else if lang.hasPrefix("ro") {
            return "TermsOfUse_romanian"
        } else if lang.hasPrefix("ru") {
            return "TermsOfUse_russian"
        } else if lang.hasPrefix("sk") {
            return "TermsOfUse_slovak"
        } else if lang.hasPrefix("es") {
            return "TermsOfUse_spanish"
        } else if lang.hasPrefix("sv") {
            return "TermsOfUse_swedish"
        } else if lang.hasPrefix("th") {
            return "TermsOfUse_thai"
        } else if lang.hasPrefix("tr") {
            return "TermsOfUse_turkish"
        } else if lang.hasPrefix("uk") {
            return "TermsOfUse_ukrainian"
        } else if lang.hasPrefix("vi") {
            return "TermsOfUse_vietnamese"
        } else {
            return "TermsOfUse" // fallback to default (probably English)
        }
    }
    
    
    let preview: Bool
    var onAgree: () -> Void
    var onCancel: () -> Void
    
    @State private var hasChecked = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    private var localHTMLURL: URL? {
        Bundle.main.url(forResource: bundledHTMLName, withExtension: "html")
    }
    @State private var exportURL: URL?
    
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let fileURL = localHTMLURL {
                    LocalHTMLWebView(fileURL: fileURL)
                } else {
                    ScrollView {
                        Text("Terms file missing from app bundle. Please add \(bundledHTMLName).html to your target.")
                            .padding()
                    }
                }
                
                if !preview {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: hasChecked ? "checkmark.square.fill" : "square")
                                .onTapGesture { hasChecked.toggle() }
                            Text("i_have_read_and_agree_to_terms_of_use".localized())
                                .onTapGesture { hasChecked.toggle() }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Button("cancel".localized(), action: onCancel)
                            Spacer()
                            Button("agree".localized(), action: onAgree)
                                .buttonStyle(.borderedProminent)
                                .disabled(!hasChecked)
                        }
                    }
                    .padding()
                }

            }
            .navigationTitle("terms_of_use".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                // LEFT side – Globe next to title
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        openURL(termsWebsiteURL)
                    } label: {
                        Image(systemName: "globe")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Terms on Website")
                }

                // RIGHT side – Download
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.down")
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Download")
                    } else {
                        Button {
                            exportURL = makeExportURL()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .imageScale(.large)
                        }
                        .disabled(localHTMLURL == nil)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Download")
                    }
                }
            }



            .onChange(of: bundledHTMLName) { _ in
                // If language changes while sheet is open, refresh the export file.
                exportURL = nil
            }
        }
    }
    
    private func makeExportURL() -> URL? {
        guard let sourceURL = localHTMLURL else { return nil }
        do {
            let data = try Data(contentsOf: sourceURL)
            let tempDir = FileManager.default.temporaryDirectory
            let safeName = bundledHTMLName.replacingOccurrences(of: " ", with: "_")
            let destURL = tempDir.appendingPathComponent("\(safeName).html")
            try data.write(to: destURL, options: [.atomic])
            return destURL
        } catch {
            print("Failed to create export URL: \(error)")
            return nil
        }
    }
}

// MARK: - WKWebView wrapper that loads a local HTML file
private struct LocalHTMLWebView: UIViewRepresentable {
    let fileURL: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Optional: prevent text selection/callout etc. by injecting CSS/JS here if you want.
        return WKWebView(frame: .zero, configuration: config)
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if fileURL.isFileURL {
            // Allow read access to the folder that contains the HTML (for linked CSS/JS/images)
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            // Shouldn’t happen for a bundled file, but keep a safe fallback
            if let html = try? String(contentsOf: fileURL, encoding: .utf8) {
                webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
            }
        }
    }
}


struct WelcomeGateView: View {
    var onContinueWithGmail: () -> Void
    var onContinueAsGuest: () -> Void
    var onContinueWithApple: () -> Void    

    @State private var pendingAction: PendingAction = .none
    @State private var showEULA = false
    
    private enum PendingAction { case apple, google, none }
    
    @State private var showToast = false
    @State private var toastOpacity: Double = 1
    @State private var toastWorkItem: DispatchWorkItem?
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @Environment(\.colorScheme) private var systemColorScheme
    
    var body: some View {
        ZStack {
            let userBackgroundColor = selectedAppearance.colorScheme ?? systemColorScheme

            VStack(spacing: 32) {
                Spacer()

                
                Image(systemColorScheme == .dark ? "LOGO_White_XB" : "LOGO_Black_XB")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.primary.opacity(0.35), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 8)

                
                VStack(spacing: 8) {
                    Text("welcome_in_vibro".localized())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                
                VStack(spacing: 12) {
                    
                    Button(action: { handleTapped(.apple) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .semibold))
                            Text("continue_with_apple".localized())
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)   // shrink down to 75% if needed
                                .allowsTightening(true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(userBackgroundColor == .dark ? .black : .white)
                        .foregroundStyle(userBackgroundColor == .dark ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(
                            color: userBackgroundColor == .dark
                                ? Color.white.opacity(0.2)
                                : Color.black.opacity(0.2),
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                    }
                    
                    Button(action: { handleTapped(.google) }){
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("continue_with_gmail".localized())
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(userBackgroundColor == .dark ? .black : .white)
                        .foregroundStyle(userBackgroundColor == .dark ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(
                            color: userBackgroundColor == .dark
                                ? Color.white.opacity(0.2)
                                : Color.black.opacity(0.2),
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                    }
                    
                    Button(action: onContinueAsGuest) {
                        Text("continue_without_signing_in".localized())
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        userBackgroundColor == .dark
                                            ? Color.black.opacity(0.85)
                                            : Color.white.opacity(0.85),
                                        lineWidth: 1.5
                                    )

                            )
                    }
                    .foregroundStyle(userBackgroundColor == .dark ? .white : .black)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                
                
                Spacer()
            }

            
            if showToast {
                Text("currently_not_available".localized())
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                    .opacity(toastOpacity)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showToast)
        .sheet(isPresented: $showEULA) {
            EULASheet(
                preview: false,
                onAgree: {
                    showEULA = false
                    proceedAfterAcceptance()
                },
                onCancel: {
                    pendingAction = .none
                    showEULA = false
                }
            )
        }
    }
    
    private func handleTapped(_ action: PendingAction) {
        pendingAction = action
        showEULA = true
    
    }
    private func proceedAfterAcceptance() { run(pendingAction); pendingAction = .none }
    private func run(_ action: PendingAction) {
        switch action {
        case .apple: onContinueWithApple()
        case .google: onContinueWithGmail()
        case .none: break
        }
    }

    
    
    private func showNotAvailableToast() {
        toastWorkItem?.cancel()
        toastOpacity = 1
        showToast = true

        withAnimation(.easeOut(duration: 2)) {
            toastOpacity = 0
        }

        let work = DispatchWorkItem {
            showToast = false
            toastOpacity = 1
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}

import StoreKit


struct SubscriptionView: View {

    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var onSubscribe: (_ plan: String) -> Void
    var onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedPlan") private var selectedPlan = "Basic"

    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {

        let userColorScheme = selectedAppearance.colorScheme ?? systemColorScheme

        VStack(spacing: 32) {

            Spacer()

            Image(systemColorScheme == .dark ? "LOGO_White_XB" : "LOGO_Black_XB")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .shadow(color: Color.primary.opacity(0.35), radius: 12, x: 0, y: 6)
                .padding(.bottom, 8)

            // MARK: Plans
            HStack(spacing: 16) {

                planCard(
                    title: "Basic",
                    price: "Free",
                    subtitle: "",
                    description: "15 Chatbot messages per day",
                    plan: "Basic"
                )

                planCard(
                    title: "Plus",
                    price: "$19.99",
                    subtitle: "Monthly",
                    description: "150 Chatbot messages per day",
                    plan: "Plus"
                )
            }
            .padding(.horizontal, 24)

            // MARK: Footer
            Text("Choose your Chatbot plan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Restore Purchases") {
                Task {
                    try? await AppStore.sync()
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 50)
        }
        .padding(.top, 40)
    }

    func purchasePlus() async {
        do {

            print("Loading product...")

            let products = try await Product.products(for: ["Plus_Sub"])

            print("Products found:", products.count)

            guard let product = products.first else {
                print("❌ Product not found")
                return
            }

            let result = try await product.purchase()

            print("Purchase result:", result)

            switch result {

            case .success(let verification):
                switch verification {
                case .verified(_):
                    print("✅ Purchase verified")
                    selectedPlan = "Plus"
                    dismiss()

                case .unverified:
                    print("⚠️ Purchase unverified")
                }

            case .userCancelled:
                print("User cancelled")

            case .pending:
                print("Pending approval")

            @unknown default:
                break
            }

        } catch {
            print("StoreKit error:", error)
        }
    }
    @ViewBuilder
    private func planCard(
        title: String,
        price: String,
        subtitle: String,
        description: String,
        plan: String
    ) -> some View {

        let isCurrent = selectedPlan == plan
        let isForbidden = selectedPlan == "Plus" && plan == "Basic"
        let textColor: Color = {
            if selectedAccent == .default {
                return systemColorScheme == .dark ? .black : .white
            } else {
                return .white
            }
        }()
        VStack(spacing: 6) {

            Text(title)
                .font(.headline)
                .foregroundStyle(textColor)
            Text(price)
                .font(.title3.bold())
                .foregroundStyle(textColor)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(textColor.opacity(0.85))
            }

            if !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(selectedAccent.color)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.3))
            }
        }
        .opacity(isForbidden ? 0.4 : 1) // visually disabled
        .onTapGesture {

            if isForbidden { return }

            if isCurrent {
                dismiss()
                return
            }

            if plan == "Plus" {
                Task {
                    await purchasePlus()
                }
            } else {
                selectedPlan = plan
            }
        }
    
    }
    
}
extension Color {
    func lighter(_ amount: Double = 0.2) -> Color {
        self.opacity(1 - amount)
    }

    func darker(_ amount: Double = 0.2) -> Color {
        self.opacity(1 + amount)
    }
}
struct UpdateGateView: View {
    let title: String
    let message: String
    let appStoreURL: URL
    let isMandatory: Bool
    let onDefer: () -> Void   

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    var body: some View {
        ZStack {
            let userBackgroundColor = selectedAppearance.colorScheme ?? systemColorScheme

            VStack(spacing: 24) {
                Spacer()

                Image(systemColorScheme == .dark ? "LOGO_White_XB" : "LOGO_Black_XB")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(userBackgroundColor == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)


                VStack(spacing: 12) {
                    Button {
                        openURL(appStoreURL)
                    } label: {
                        Text("update_now".localized())
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(userBackgroundColor == .dark ? .black : .white)
                            .foregroundStyle(userBackgroundColor == .dark ? .white : .black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(
                                color: userBackgroundColor == .dark
                                ? Color.white.opacity(0.2)
                                : Color.black.opacity(0.2),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                    }
                    
                    
                    Button {
                        onDefer()
                    } label: {
                        Text("not_yet".localized())
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .foregroundStyle(Color.secondary)
                
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                Spacer()
            }
        }
        
        .interactiveDismissDisabled(isMandatory)
    }
}


enum LocalPush {
    static func show(appNotification n: AppNotification) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // ✅ Do NOT trigger permission prompt on launch
            guard settings.authorizationStatus == .authorized else {
                return
            }
            
            
            let content = UNMutableNotificationContent()
            content.title = "New post"
            content.body  = n.content.isEmpty ? "Tap to view" : n.content
            content.sound = .default
            content.userInfo = [
                "type": n.type ?? "new_post",
                "postID": n.postID ?? "",
                "author": n.author ?? "",
                "notifID": n.id
            ]
            
            
            
            let req = UNNotificationRequest(identifier: "notif.\(n.id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { err in
                if let err {  }
            }
        }
    }
}

public final class NotificationsService: ObservableObject {
    @Published public var notifications: [AppNotification] = []

    private var notifListener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var knownIDs = Set<String>()
    private var didPrime = false   
    private var seededFromServer = false
    public init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            if let user = user {
                self.startNotificationsListener(for: user.uid)
                self.fetchNotificationsOnce(for: user.uid)
            } else {
                self.stopNotificationsListener()
                self.knownIDs.removeAll()
                self.didPrime = false
                self.seededFromServer = false
                DispatchQueue.main.async { self.notifications = [] }
            }
        }
    }
    deinit {
        stopNotificationsListener()
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
    }

    
    public func deleteNotification(_ id: String,
                                   optimistic: Bool = true,
                                   completion: ((Error?) -> Void)? = nil) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            completion?(nil) 
            return
        }

        let uid = user.uid


        let ref = Firestore.firestore().collection(Coll.followers).document(uid)

        
        if optimistic {
            DispatchQueue.main.async {
                self.notifications.removeAll { $0.id == id }
                self.knownIDs.remove(id)
            }
        }

        
        let literal = FieldPath(["Notifications.\(id)"]) 
        let nested  = FieldPath(["Notifications", id])   

        ref.updateData([
            literal: FieldValue.delete(),
            nested : FieldValue.delete()
        ]) { error in
            if let error {
                
                
            }
            completion?(error)
        }
    }

    
    
    public func fetchNotificationsOnce(for uid: String) {
        let ref = Firestore.firestore().collection(Coll.followers).document(uid)
        ref.getDocument { [weak self] snap, error in
            guard let self else { return }
            if let error { return }
            let data = snap?.data() ?? [:]
            let items = self.parseNotifications(from: data).sorted { $0.date > $1.date }
            DispatchQueue.main.async {
                self.notifications = items
                
                self.knownIDs = Set(items.map { $0.id })
                self.didPrime = true
            }
        }
    }
    
    public func fetchNotificationsOnce() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let uid = user.uid

        fetchNotificationsOnce(for: uid)
    }

    public func startNotificationsListener(for uid: String) {
        let ref = Firestore.firestore().collection(Coll.followers).document(uid)

        notifListener?.remove()
        
        notifListener = ref.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { return }
            guard let snap else { return }

            let isServer = !snap.metadata.isFromCache
            let data = snap.data() ?? [:]
            let items = self.parseNotifications(from: data).sorted { $0.date > $1.date }

            
            DispatchQueue.main.async {
                self.notifications = items
            }

            
            if isServer && !self.seededFromServer {
                self.knownIDs = Set(items.map(\.id))
                self.seededFromServer = true
                return
            }

            
            if !isServer && !self.seededFromServer {
                return
            }

            
            guard isServer else { return }

            let currentIDs = Set(items.map(\.id))
            let currentUID =
                Auth.auth().currentUser?.isAnonymous == false
                ? Auth.auth().currentUser?.uid
                : nil

            let newOnes = items.filter { n in
                !self.knownIDs.contains(n.id) && !n.isRead && n.author != currentUID
            }
            self.knownIDs = currentIDs

            newOnes.forEach { LocalPush.show(appNotification: $0) }
        }
    }

    public func startNotificationsListener() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let uid = user.uid

        startNotificationsListener(for: uid)
    }

    public func stopNotificationsListener() {
        notifListener?.remove()
        notifListener = nil
    }

    public func markNotificationRead(_ id: String) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let uid = user.uid

        let ref = Firestore.firestore().collection(Coll.followers).document(uid)

        ref.getDocument { snap, err in
            if let err = err {
                
                return
            }
            let data = snap?.data() ?? [:]

            let literalFieldName = "Notifications.\(id)"                
            let literalExists = data[literalFieldName] != nil

            if literalExists {
                UIApplication.shared.applicationIconBadgeNumber -= 1
                let fp = FieldPath([literalFieldName, "isRead"])
                ref.updateData([fp: true]) { err in
                    if let err = err {  }
                }
            } else {
                UIApplication.shared.applicationIconBadgeNumber -= 1
                let nested = FieldPath(["Notifications", id, "isRead"])
                ref.updateData([nested: true]) { err in
                    if let err = err {  }
                }
            }
        }
    }
    public func setNotificationRead(_ id: String, to isRead: Bool) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else {
            return
        }

        let uid = user.uid

        let ref = Firestore.firestore().collection(Coll.followers).document(uid)

        
        DispatchQueue.main.async {
            if let i = self.notifications.firstIndex(where: { $0.id == id }) {
                let wasRead = self.notifications[i].isRead
                self.notifications[i].isRead = isRead

                
                if isRead && !wasRead {
                    UIApplication.shared.applicationIconBadgeNumber = max(0, UIApplication.shared.applicationIconBadgeNumber - 1)
                } else if !isRead && wasRead {
                    UIApplication.shared.applicationIconBadgeNumber += 1
                }
            }
        }

        
        DispatchQueue.main.async {
            ref.getDocument { snap, err in
                if let err = err {
                    
                    return
                }
                let data = snap?.data() ?? [:]

                let literalFieldName = "Notifications.\(id)"      
                let literalExists = data[literalFieldName] != nil

                if literalExists {
                    
                    let fp = FieldPath([literalFieldName, "isRead"])
                    ref.updateData([fp: isRead]) { err in
                        if let err = err {  }
                    }
                } else {
                    
                    let fp = FieldPath(["Notifications", id, "isRead"])
                    ref.updateData([fp: isRead]) { err in
                        if let err = err {  }
                    }
                }
            }
        }
    }

    public func toggleNotificationRead(_ id: String) {
        
        let current = notifications.first(where: { $0.id == id })?.isRead ?? false
        setNotificationRead(id, to: !current)
    }


    
    private func notificationFromDict(id: String, _ dict: [String: Any]) -> AppNotification {
 

        let content = dict["content"] as? String ?? ""
        let ts = (dict["date"] as? Timestamp)?.dateValue() ?? .distantPast
        let type = dict["type"] as? String
        let author = dict["author"] as? String
        let postID = dict["postID"] as? String
        let title = dict["title"] as? String ?? ""
        let isRead = dict["isRead"] as? Bool ?? false

        return AppNotification(
            id: id,
            title: title,
            content: content,
            date: ts,
            type: type,
            author: author,
            postID: postID,
            isRead: isRead
        )
    }

    
    private func parseNotifications(from data: [String: Any]) -> [AppNotification] {
        var byId: [String: AppNotification] = [:]

        
        if let map = data["Notifications"] as? [String: Any] {
            for (id, val) in map {
                if let d = val as? [String: Any] {
                    byId[id] = notificationFromDict(id: id, d)
                }
            }
        }

        
        
        for (key, val) in data where key.hasPrefix("Notifications.") {
            let id = String(key.dropFirst("Notifications.".count))
            if let d = val as? [String: Any] {
                byId[id] = notificationFromDict(id: id, d)
            }
        }

        
        return Array(byId.values)
            .sorted { $0.date > $1.date }
    }

}



struct SoftNeonDivider: View {
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    
    /// Optional accent override
    var accent: Color? = nil
    
    var body: some View {
        Rectangle()
            .fill(accent ?? selectedAccent.color)
            .frame(height: 1.55)
            .blur(radius: 0.1)
    }
}

struct FuturisticChipTime: View {
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    
    let label: String
    let systemImage: String?
    var selected: Bool = false
    let accent: Color
    var valueText: String

    
    private static let dateParser: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yy-MM-dd-HH-mm-ss"
        return df
    }()

    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let rf = RelativeDateTimeFormatter()
        rf.unitsStyle = .full
        return rf
    }()

    var body: some View {
        let relativeTime: String = {
            if let date = Self.dateParser.date(from: valueText) {
                return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
            } else {
                return valueText 
            }
        }()

        return HStack(spacing: 8) {
            if let s = systemImage {
                Image(systemName: s)
                    .imageScale(.small)
            }

            Text(label)
                .foregroundStyle(Color.primary)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            Circle()
                .foregroundStyle(Color.gray)
                .frame(width: 3, height: 3)
                .opacity(0.6)

            Text(relativeTime)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.gray)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().fill(accent.opacity(selected ? 0.18 : 0)))
        .overlay(
            Capsule().strokeBorder(
                selected ? accent : Color.white.opacity(0.25),
                lineWidth: selected ? 1.2 : 0.75
            )
        )
        .contentShape(Capsule())
        
        
    }
}



struct FuturisticChipBackground: ViewModifier {
    var selected: Bool
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().fill(selectedAccent.color.opacity(selected ? 0.18 : 0)))
            .overlay(
                Capsule().strokeBorder(
                    selected ? selectedAccent.color : Color.white.opacity(0.25),
                    lineWidth: selected ? 1.2 : 0.75
                )
            )
            .contentShape(Capsule())
    }
}
extension View {
    func futuristicChipBackground(selected: Bool) -> some View {
        modifier(FuturisticChipBackground(selected: selected))
    }
}


struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: Double
}

struct ParticleEffectView: View {
    var accent: Color? = nil
    @State private var particles: [Particle] = []
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(accent ?? selectedAccent.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                        .animation(.easeOut(duration: particle.speed), value: particle.y)
                }
            }
            .onAppear {
                generateParticles(in: geo.size)
            }
        }
        .background(Color.clear)
    }

    func generateParticles(in size: CGSize) {
        particles.removeAll()
        for _ in 0..<1000 {
            let particle = Particle(
                x: CGFloat.random(in: 0...size.width),
                y: size.height + CGFloat.random(in: 0...100),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.3...1.0),
                speed: Double.random(in: 0.5...1.0)
            )
            particles.append(particle)
        }

        
        DispatchQueue.main.async {
            for i in 0..<particles.count {
                particles[i].y -= CGFloat.random(in: 200...1000)
                particles[i].opacity = 0
            }
        }
    }
}


/// Static, 3-layer 3×3 filled-circle grid with 3D look, rotated 45°.
/// Matches the sizing/“static sphere” behavior: renders once, no animations.
struct StaticPlainGrid3DView: UIViewRepresentable {
    var accent: Color? = nil
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    func makeUIView(context: Context) -> UIView {
        let size = UIScreen.main.bounds.width * 0.1
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        // Centered fixed-size container
        let container = UIView(frame: .init(x: 0, y: 0, width: size, height: size))
        container.backgroundColor = .clear
        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size)
        ])

        // Perspective on the container so *all* descendants get it
        var persp = CATransform3DIdentity
        persp.m34 = -1.0 / 400.0
        container.layer.sublayerTransform = persp

        // ✅ Use CATransformLayer so sublayers keep their 3D depth
        let sceneLayer = CATransformLayer()
        sceneLayer.frame = container.bounds
        container.layer.addSublayer(sceneLayer)

        // Depth planes
        let backGridLayer  = CALayer()
        let midGridLayer   = CALayer()
        let frontGridLayer = CALayer()
        for l in [backGridLayer, midGridLayer, frontGridLayer] {
            l.frame = sceneLayer.bounds
            l.isDoubleSided = false            // optional: hide backfaces
            l.allowsEdgeAntialiasing = true    // nicer edges when rotated
            sceneLayer.addSublayer(l)
        }
        
        
        let tiltX: CGFloat = 0
        let depthStep: CGFloat = 6            // ⬅️ tighter Z spacing (was effectively ~70)
        let zBack: CGFloat  = -depthStep
        let zMid: CGFloat   = 0
        let zFront: CGFloat =  depthStep

        // If you want them visually closer *vertically*, compensate Y by the projected amount.
        // Δy ≈ Δz * sin(tiltX). Set this to 'true' to enable.
        let compensateVertical = true
        let s = CGFloat(sin(tiltX))
        
        if compensateVertical {
            backGridLayer.transform  = CATransform3DTranslate(CATransform3DIdentity, 0, -zBack  * s, zBack)
            midGridLayer.transform   = CATransform3DTranslate(CATransform3DIdentity, 0, -zMid   * s, zMid)
            frontGridLayer.transform = CATransform3DTranslate(CATransform3DIdentity, 0, -zFront * s, zFront)
        } else {
            backGridLayer.transform  = CATransform3DTranslate(CATransform3DIdentity, 0, 0, zBack)
            midGridLayer.transform   = CATransform3DTranslate(CATransform3DIdentity, 0, 0, zMid)
            frontGridLayer.transform = CATransform3DTranslate(CATransform3DIdentity, 0, 0, zFront)
        }

        // Rotate scene (around X, slight Y to separate layers)
        var sceneT = CATransform3DIdentity
        sceneT = CATransform3DRotate(sceneT, .pi/4, 1, 0, 0)            // 45° about X
        sceneLayer.transform = sceneT

        // Grid geometry
        let rows = 3, cols = 3
        let cellW = size / CGFloat(cols)
        let cellH = size / CGFloat(rows)

        // Visuals
        let uiColor = UIColor(accent ?? selectedAccent.color)
        let insetBack: CGFloat  = 0.36
        let insetMid: CGFloat   = 0.20
        let insetFront: CGFloat = 0.10

        func addFilledGrid(to host: CALayer, insetRatio: CGFloat, alpha: CGFloat, addShadow: Bool) {
            for index in 0..<(rows * cols) {
                let r = index / cols, c = index % cols
                let cellFrame = CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH, width: cellW, height: cellH)
                let circleFrame = cellFrame.insetBy(dx: min(cellW, cellH) * insetRatio,
                                                    dy: min(cellW, cellH) * insetRatio)
                let radius = min(circleFrame.width, circleFrame.height) / 2.0
                let center = CGPoint(x: circleFrame.midX, y: circleFrame.midY)

                let circle = CAShapeLayer()
                circle.frame = host.bounds
                circle.contentsScale = UIScreen.main.scale // crisp edges
                circle.path = UIBezierPath(arcCenter: center,
                                           radius: radius,
                                           startAngle: 0,
                                           endAngle: .pi * 2,
                                           clockwise: true).cgPath
                circle.fillColor = uiColor.withAlphaComponent(alpha).cgColor
                circle.strokeColor = nil
                circle.lineWidth = 0
                if addShadow {
                    circle.shadowColor = uiColor.cgColor
                    circle.shadowOpacity = 0.35
                    circle.shadowRadius = max(1.0, size * 0.02 * 1.5)
                    circle.shadowOffset = .zero
                    circle.shadowPath = circle.path
                }
                host.addSublayer(circle)
            }
        }

        // Build all three layers
        addFilledGrid(to: backGridLayer,  insetRatio: insetBack,  alpha: 1.00, addShadow: false)
        addFilledGrid(to: midGridLayer,   insetRatio: insetMid,   alpha: 1.00, addShadow: true)
        addFilledGrid(to: frontGridLayer, insetRatio: insetFront, alpha: 1.00, addShadow: true)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}




struct StaticRotatingSphereView: UIViewRepresentable {
    var accent: Color? = nil
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    // MARK: - Wire sphere builder (unchanged)
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

        // Meridians
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

        // Parallels
        if P > 0 {
            for j in 1...P {
                let phi = -Float.pi/2 + Float.pi * Float(j) / Float(P + 1)
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
        mat.diffuse.contents = color
        mat.transparency = opacity
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.readsFromDepthBuffer = true
        mat.writesToDepthBuffer = false
        geo.firstMaterial = mat

        return SCNNode(geometry: geo)
    }

    func makeUIView(context: Context) -> SCNView {
        let size = UIScreen.main.bounds.width * 0.5
        let scnView = SCNView(frame: CGRect(x: 0, y: 0, width: size, height: size))

        // No interaction and no animation
        scnView.allowsCameraControl = false
        scnView.isUserInteractionEnabled = false
        scnView.isPlaying = false                 // ⛔️ stop SceneKit time
        scnView.rendersContinuously = false       // ✅ render only when needed

        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false

        let scene = SCNScene()
        scnView.scene = scene

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 2)      // was 3
        cameraNode.camera?.fieldOfView = 50               // narrower FOV = closer feel
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar  = 10
        scene.rootNode.addChildNode(cameraNode)

        // Light (subtle; lines are constant-lit anyway)
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(1, 1, 3)
        scene.rootNode.addChildNode(lightNode)

        // Concentric wire spheres
        let outerRadius: CGFloat = 0.4
        let radii: [CGFloat] = [
            outerRadius,
            outerRadius * 0.82,
            outerRadius * 0.65,
            outerRadius * 0.50,
            outerRadius * 0.38
        ]

        let group = SCNNode()
        let n = radii.count

        let minMeridians = 6
        let meridianStep = 4
        let maxOpacity: CGFloat = 1.0
        
        // --- with this: only the innermost sphere ---
        let i = n - 1                       // index of innermost sphere
        let innerRadius = radii[i]
        let m = minMeridians + i * meridianStep
        let p = max(4, m / 2)
        let node = makeWireSphere(
            radius: outerRadius,
            meridians: m,
            parallels: p,
            color: UIColor(accent ?? selectedAccent.color),
            opacity: maxOpacity            // fully visible
        )
        group.addChildNode(node)

        // Fixed scale and pleasant static orientation
        group.scale = SCNVector3(1.0, 1.0, 1.0)          // was 0.85

        // Face camera directly (no rotation)
        group.eulerAngles = SCNVector3Zero
        // or equivalently:
        group.eulerAngles = SCNVector3(0, 0, 0)


        // ⛔️ No rotation animation — removed

        scene.rootNode.addChildNode(group)

        // Force one draw then idle (nice for battery)
        scnView.setNeedsDisplay()
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Nothing to update for static content.
    }
}

struct RotatingSphereView: UIViewRepresentable {
    var accent: Color? = nil
    var successToPublish: Bool? = nil

    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    // ✅ DOT: keep the same cap epsilon used by the wire
    private let capEpsilon: Float = 0.08

    final class Coordinator {
        var innerRadius: CGFloat = 0
        var meridians: Int = 0
        var parallels: Int = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    
    private func makeWireSphere(
        radius: CGFloat,
        meridians: Int,
        parallels: Int,
        color: UIColor,
        opacity: CGFloat
    ) -> SCNNode {
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

        let thetaSpan = Float.pi - 2 * capEpsilon

        // Meridians
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

        // Parallels
        if P > 0 {
            for j in 1...P {
                let phi = -Float.pi/2 + Float.pi * Float(j) / Float(P + 1)
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
        mat.diffuse.contents = color
        mat.transparency = opacity
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.readsFromDepthBuffer = true
        mat.writesToDepthBuffer = false
        geo.firstMaterial = mat

        return SCNNode(geometry: geo)
    }

    // ✅ DOT: random position but guaranteed inside an "empty square" (between wires)
    private func makePublishDot(radius: CGFloat, meridians: Int, parallels: Int) -> SCNNode {
        let r = Float(radius)
        let M = max(3, meridians)
        let P = max(1, parallels)

        // --- pick a random meridian "cell" (halfway between two meridian lines)
        let dLambda = 2.0 * Float.pi / Float(M)
        let i = Int.random(in: 0..<M)
        let lambdaMid = (Float(i) + 0.5) * dLambda

        // --- pick a random latitude "band" BETWEEN parallel rings
        // parallels are drawn at:
        // phi(j) = -π/2 + π*j/(P+1), for j = 1...P
        // so bands are j = 0...P between phi(j) and phi(j+1)
        let bands = P + 1

        // Avoid the two polar-most bands if possible (prevents "only top/bottom" feel)
        let skip = (bands >= 4) ? 1 : 0  // skip 1 band near each pole if we have enough bands
        let j = Int.random(in: skip..<(bands - skip))

        let phi0 = -Float.pi / 2 + Float.pi * Float(j)     / Float(P + 1)
        let phi1 = -Float.pi / 2 + Float.pi * Float(j + 1) / Float(P + 1)
        let phiMid = 0.5 * (phi0 + phi1)

        // position on sphere (matches your parallels math exactly)
        let cosphi = cos(phiMid), sinphi = sin(phiMid)
        let x = r * cosphi * cos(lambdaMid)
        let y = r * sinphi
        let z = r * cosphi * sin(lambdaMid)

        let dot = SCNNode(geometry: SCNSphere(radius: radius * 0.06))
        dot.name = "publishDot"
        dot.position = SCNVector3(x, y, z)

        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        mat.lightingModel = .constant
        mat.readsFromDepthBuffer = false
        mat.writesToDepthBuffer = false
        dot.geometry?.firstMaterial = mat

        // ✅ BLINK
        dot.opacity = 1.0
        dot.removeAction(forKey: "blink")
        let fadeDown = SCNAction.fadeOpacity(to: 0.15, duration: 0.45)
        fadeDown.timingMode = .easeInEaseOut
        let fadeUp = SCNAction.fadeOpacity(to: 1.0, duration: 0.45)
        fadeUp.timingMode = .easeInEaseOut
        dot.runAction(.repeatForever(.sequence([fadeDown, fadeUp])), forKey: "blink")

        return dot
    }




    func makeUIView(context: Context) -> SCNView {
        let size = UIScreen.main.bounds.width * 0.7
        let scnView = SCNView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.isPlaying = true

        let scene = SCNScene()
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(1, 1, 3)
        scene.rootNode.addChildNode(lightNode)

        let outerRadius: CGFloat = 0.5
        let radii: [CGFloat] = [
            outerRadius,
            outerRadius * 0.82,
            outerRadius * 0.65,
            outerRadius * 0.50,
            outerRadius * 0.38
        ]

        let group = SCNNode()
        group.name = "wireGroup" // ✅ DOT: findable later

        let n = radii.count
        let minMeridians = 4
        let meridianStep = 4
        let maxOpacity: CGFloat = 1.0

        // innermost sphere
        let i = n - 1
        let innerRadius = radii[i]
        let m = minMeridians + i * meridianStep
        let p = max(4, m / 2)

        // save for updateUIView
        context.coordinator.innerRadius = innerRadius
        context.coordinator.meridians = m
        context.coordinator.parallels = p

        let node = makeWireSphere(
            radius: innerRadius,
            meridians: m,
            parallels: p,
            color: UIColor(accent ?? selectedAccent.color),
            opacity: maxOpacity
        )
        group.addChildNode(node)

        // ✅ DOT: add initially if successToPublish
        if successToPublish ?? false {
            group.addChildNode(makePublishDot(radius: innerRadius, meridians: m, parallels: p))
        }

        scene.rootNode.addChildNode(group)

        let minScale: CGFloat = 1.0
        group.scale = SCNVector3(minScale, minScale, minScale)

        let expand = SCNAction.scale(to: 1.5, duration: 2.0)
        expand.timingMode = .easeInEaseOut
        let collapse = SCNAction.scale(to: minScale, duration: 2.0)
        collapse.timingMode = .easeInEaseOut
        group.runAction(.repeatForever(.sequence([expand, collapse])))

        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue   = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        spin.duration = 2.0
        spin.repeatCount = .infinity
        group.addAnimation(spin, forKey: "spin")

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard
            let scene = uiView.scene,
            let group = scene.rootNode.childNode(withName: "wireGroup", recursively: true)
        else { return }

        // ✅ DOT: always remove old dot, then re-add if needed
        group.childNode(withName: "publishDot", recursively: false)?.removeFromParentNode()

        if successToPublish ?? false {
            group.addChildNode(
                makePublishDot(
                    radius: context.coordinator.innerRadius,
                    meridians: context.coordinator.meridians,
                    parallels: context.coordinator.parallels
                )
            )
        }
    }
}



struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
struct PageDots: View {
    
    let keys: [Int]
    
    @Binding var current: Int
    var accent: Color? = nil
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    private let totalDots = 8

    
    private let dot: CGFloat = 8       
    private let hit: CGFloat = 22      
    private let gap: CGFloat = 4       

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<totalDots, id: \.self) { idx in
                let keyForDot  = idx + 1
                let isEnabled  = keys.contains(keyForDot)
                let isSelected = isEnabled
                                  && keys.indices.contains(current)
                                  && keys[current] == keyForDot

                let fill: Color = isSelected
                    ? (accent ?? selectedAccent.color)
                : (isEnabled ? .white.opacity(0.75) : .secondary.opacity(0.6))

                Group {
                    if isEnabled {
                        Button {
                            if let newIndex = keys.firstIndex(of: keyForDot) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    current = newIndex
                                }
                            }
                        } label: {
                            Circle()
                                .fill(fill)
                                .frame(width: dot, height: dot)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? .clear : Color.primary.opacity(0.25),
                                                lineWidth: isSelected ? 0 : 0.75)
                                )
                                
                                .frame(width: hit, height: hit)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Circle()
                            .fill(fill)
                            .frame(width: dot, height: dot)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.75)
                            )
                            .frame(width: hit, height: hit)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .background(Color.clear)
    }
}

struct FrostedGradientCapsuleButtonStyle: ButtonStyle {
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    
    var cornerRadius: CGFloat = 12   // 👈 tweak here if you want sharper/softer corners
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        selectedAccent.color,
                        lineWidth: 1.2
                    )
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.12),
                radius: configuration.isPressed ? 6 : 12,
                x: 0, y: 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct ExpandingMemoryCard<Header: View, Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .frame(maxWidth: .infinity, alignment: .leading) 
                .padding(14)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if isExpanded {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading) 
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity) 
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .primary.opacity(0.08), radius: 14, x: 0, y: 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isExpanded)
    }
}

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let size = UIScreen.main.bounds.width * 0.1

        
        let scnView = SCNView()
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.backgroundColor = .clear
        view.addSubview(scnView)

        NSLayoutConstraint.activate([
            scnView.widthAnchor.constraint(equalToConstant: size),
            scnView.heightAnchor.constraint(equalToConstant: size),
            scnView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scnView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        
        let scene = SCNScene()
        scnView.scene = scene

        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(1, 1, 3)
        scene.rootNode.addChildNode(lightNode)

        
        let sphere = SCNSphere(radius: 0.5)
        sphere.segmentCount = 48
        sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue
        sphere.firstMaterial?.specular.contents = UIColor.white

        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue   = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        spin.duration = 2.0
        spin.repeatCount = .infinity
        sphereNode.addAnimation(spin, forKey: "spin")
    }
}



final class AppleSignInHelper: NSObject, ASAuthorizationControllerDelegate {
    private var currentNonce: String?
    private var completion: ((Bool) -> Void)?

    func startSignInWithAppleFlow(completion: @escaping (Bool) -> Void) {
        self.completion = completion

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = appleIDCredential.identityToken,
            let idTokenString = String(data: identityTokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            completion?(false)
            completion = nil
            return
        }

        let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                  idToken: idTokenString,
                                                  rawNonce: nonce)

        Auth.auth().signIn(with: credential) { _, error in
            if let error = error {
                
                self.completion?(false)
            } else {
                self.completion?(true)
            }
            self.completion = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        
        completion?(false)
        completion = nil
    }

    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if result != errSecSuccess {
            fatalError("Unable to generate nonce: \(result)")
        }
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct SheetDismissObserver: UIViewControllerRepresentable {
    
    var shouldAllowDismiss: () -> Bool

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var parent: SheetDismissObserver
        init(_ parent: SheetDismissObserver) { self.parent = parent }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            parent.shouldAllowDismiss()
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            _ = parent.shouldAllowDismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        
        DispatchQueue.main.async {
            vc.presentationController?.delegate = context.coordinator
            vc.parent?.presentationController?.delegate = context.coordinator
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.presentationController?.delegate = context.coordinator
        uiViewController.parent?.presentationController?.delegate = context.coordinator
    }
}


func toggleOrientation() {
    guard let windowScene = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
    else { return }
    
    let isLandscape = windowScene.interfaceOrientation.isLandscape
    let targetMask: UIInterfaceOrientationMask =
        isLandscape ? .portrait : .landscapeRight
    
    let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMask)
    
    do {
        try windowScene.requestGeometryUpdate(prefs)
    } catch {
        
    }
}

enum AppRoute: Hashable, Identifiable {
    case model
    var id: String { "model" }
}


final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private init() {}

    let routeSubject = PassthroughSubject<AppRoute, Never>()

    func handle(url: URL) {
        // Works for: https://your.domain/model/123  or myapp://model/123
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        guard let first = parts.first else { return }
        if first == "model" { routeSubject.send(.model) }
    }
}
@MainActor
final class NavigationModel: ObservableObject {
    @Published var pending: AppRoute?
    private var bag = Set<AnyCancellable>()
    
    init(router: DeepLinkRouter = .shared) {
        router.routeSubject
            .map(Optional.some)                 // AppRoute -> AppRoute?
            .receive(on: DispatchQueue.main)
            .assign(to: &$pending)              // now types match
    }
}
