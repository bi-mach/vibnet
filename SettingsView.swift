//
//  SettingsView.swift
//  Vibro
//
//  Created by lyubcsenko on 01/08/2025.
//

import SwiftUI
import GoogleSignIn
import FirebaseAuth
import CoreBluetooth
import FirebaseStorage
import Foundation
import ObjectiveC.runtime
import FirebaseFirestore
import SceneKit


@MainActor
final class USDZPreloader: ObservableObject {
    static let shared = USDZPreloader()
    private var cache: [String: SCNScene] = [:]

    func preload(named file: String) {
        guard cache[file] == nil else { return }
        cache[file] = Self.buildScene(fileName: file)
    }

    func scene(for file: String) -> SCNScene? { cache[file] }

    // ✅ One single source of truth for loading + configuring
    static func buildScene(fileName: String) -> SCNScene? {
        let scene: SCNScene?
        if let s = SCNScene(named: "\(fileName).usdc") {
            scene = s
        } else if let url = Bundle.main.url(forResource: fileName, withExtension: "usdc") {
            scene = try? SCNScene(url: url, options: nil)
        } else if let s = SCNScene(named: "\(fileName).usdz") {
            scene = s
        } else if let url = Bundle.main.url(forResource: fileName, withExtension: "usdz") {
            scene = try? SCNScene(url: url, options: nil)
        } else {
            scene = nil
        }

        guard let scene else { return nil }

        scene.background.contents = UIColor.clear
        let root = scene.rootNode

        // Camera
        if root.childNode(withName: "sheetCamera", recursively: true) == nil {
            let cameraNode = SCNNode()
            cameraNode.name = "sheetCamera"
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.wantsHDR = false
            cameraNode.position = SCNVector3(0, 0, 3)
            root.addChildNode(cameraNode)
        }



        // --- Collect geometry nodes currently under root ---
        let geometryNodes = root.childNodes { node, _ in node.geometry != nil }


        // ✅ Force material to black plastic (PBR)
        let plastic = SCNMaterial()
        plastic.lightingModel = .physicallyBased
        plastic.diffuse.contents = UIColor.black
        plastic.metalness.contents = 0.0          // plastic = non-metal
        plastic.roughness.contents = 0.95
        plastic.specular.contents = UIColor(white: 0.15, alpha: 1.0)
        plastic.normal.contents = nil
        plastic.emission.contents = UIColor.black
        plastic.isDoubleSided = false

        for node in geometryNodes {
            guard let g = node.geometry else { continue }
            // Apply same material to all submaterials
            g.materials = Array(repeating: plastic, count: max(g.materials.count, 1))
        }


        // --- Put geometry under a dedicated model container (clean parenting) ---
        let modelNode = SCNNode()
        modelNode.name = "modelNode"

        if geometryNodes.count == 1 {
            modelNode.addChildNode(geometryNodes[0]) // reparent into modelNode
        } else {
            geometryNodes.forEach { modelNode.addChildNode($0) } // reparent all into modelNode
        }
        

        // --- Wrapper node that spins (so base rotation doesn't get overwritten) ---
        let spinNode = SCNNode()
        spinNode.name = "spinNode"
        root.addChildNode(spinNode)
        spinNode.addChildNode(modelNode)

        // --- Measure bounds in world space (using modelNode subtree) ---
        let nodesToMeasure =
            modelNode.childNodes { node, _ in node.geometry != nil }
            + (modelNode.geometry != nil ? [modelNode] : [])

        var minV = SCNVector3(Float.greatestFiniteMagnitude,
                              Float.greatestFiniteMagnitude,
                              Float.greatestFiniteMagnitude)
        var maxV = SCNVector3(-Float.greatestFiniteMagnitude,
                              -Float.greatestFiniteMagnitude,
                              -Float.greatestFiniteMagnitude)

        for node in nodesToMeasure {
            let (bmin, bmax) = node.boundingBox

            let corners = [
                SCNVector3(bmin.x, bmin.y, bmin.z),
                SCNVector3(bmin.x, bmin.y, bmax.z),
                SCNVector3(bmin.x, bmax.y, bmin.z),
                SCNVector3(bmin.x, bmax.y, bmax.z),
                SCNVector3(bmax.x, bmin.y, bmin.z),
                SCNVector3(bmax.x, bmin.y, bmax.z),
                SCNVector3(bmax.x, bmax.y, bmin.z),
                SCNVector3(bmax.x, bmax.y, bmax.z),
            ].map { node.convertPosition($0, to: root) }

            for c in corners {
                minV.x = Swift.min(minV.x, c.x); minV.y = Swift.min(minV.y, c.y); minV.z = Swift.min(minV.z, c.z)
                maxV.x = Swift.max(maxV.x, c.x); maxV.y = Swift.max(maxV.y, c.y); maxV.z = Swift.max(maxV.z, c.z)
            }
        }

        let centerWorld = SCNVector3((minV.x + maxV.x) / 2,
                                     (minV.y + maxV.y) / 2,
                                     (minV.z + maxV.z) / 2)

        let centerInModel = modelNode.convertPosition(centerWorld, from: root)
        modelNode.pivot = SCNMatrix4MakeTranslation(centerInModel.x, centerInModel.y, centerInModel.z)

        // --- Apply transforms to model (NOT the spinner) ---
        modelNode.scale = SCNVector3(0.025, 0.025, 0.025)

        // ✅ Stand it up (main attempt)
        // Stand up + flip upright
        // Stand upright (feet down)
        modelNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)




        // --- Spin ONLY the wrapper ---
        let spin = SCNAction.customAction(duration: 8) { node, t in
            let angle = Float(t / 8.0) * Float.pi * 2
            node.simdOrientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        }
        spinNode.runAction(.repeatForever(spin))

        return scene
    }
}
struct USDZView: View {
    let fileName: String
    let preloadedScene: SCNScene?

    init(fileName: String, preloadedScene: SCNScene? = nil) {
        self.fileName = fileName
        self.preloadedScene = preloadedScene
    }

    var body: some View {
        Group {
            if let scene = preloadedScene ?? USDZPreloader.shared.scene(for: fileName) {
                TransparentSceneView(fileName: fileName, preloadedScene: scene)
            } else if let scene = USDZPreloader.buildScene(fileName: fileName) {
                TransparentSceneView(fileName: fileName, preloadedScene: scene)
            } else {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .opacity(0.6)
            }
        }
        .compositingGroup()
    }
}
struct TransparentSceneView: UIViewRepresentable {
    let fileName: String
    let preloadedScene: SCNScene?
    
    init(fileName: String, preloadedScene: SCNScene? = nil) {
        self.fileName = fileName
        self.preloadedScene = preloadedScene
    }
    
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.isPlaying = true
        v.rendersContinuously = true
        v.autoenablesDefaultLighting = true
        let scene = preloadedScene ?? USDZPreloader.shared.scene(for: fileName)
        if let scene {
            v.scene = scene
        } else {
            // fallback: load if not preloaded
            v.scene = SCNScene(named: "\(fileName).usdc") ?? SCNScene(named: "\(fileName).usdz")
        }
        
        return v
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) { }

}
final class LocalizationManager {
    static let shared = LocalizationManager()
    private let languageKey = "SelectedLanguage"   // optional override

    /// Localizations in your app bundle (without "Base"), normalized to lowercased codes
    var supportedLanguages: [String] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .map { $0.lowercased() }
    }

    /// The *effective* language: saved override if present, else system-preferred.
    var currentLanguage: String {
        if let override = UserDefaults.standard.string(forKey: languageKey), !override.isEmpty {
            return override
        }
        return Self.systemAppLanguageCode(supported: supportedLanguages)
    }

    /// Explicitly force a language (user-picked in settings UI)
    func setLanguage(_ language: String) {
        UserDefaults.standard.set(language, forKey: languageKey)
        Bundle.setLanguage(language)             // your swizzled Bundle helper
        NotificationCenter.default.post(name: .init("LanguageChanged"), object: nil)
    }

    /// Remove override and let iOS pick (per-app language respected)
    func useSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: languageKey)
        Bundle.setLanguage(nil) // now valid
        NotificationCenter.default.post(name: .init("LanguageChanged"), object: nil)
    }

    static func systemAppLanguageCode(supported: [String]) -> String {
        let preferred = Bundle.main.preferredLocalizations.first
                    ?? Locale.preferredLanguages.first
                    ?? "en"

        let normalized: String
        if #available(iOS 16.0, *) {
            if let code = Locale(identifier: preferred).language.languageCode?.identifier {
                normalized = code.lowercased()
            } else {
                normalized = preferred.split(separator: "-").first.map(String.init)?.lowercased() ?? "en"
            }
        } else {
            normalized = preferred.split(separator: "-").first.map(String.init)?.lowercased() ?? "en"
        }

        guard !supported.isEmpty else { return normalized }
        if supported.contains(normalized) { return normalized }
        if supported.contains("en") { return "en" }
        return supported.first! // last-chance fallback
    }

}
private var kLangBundleKey: UInt8 = 0
extension Bundle {
    /// Pass a language code (e.g. "en", "de") to force, or `nil` to clear and use system/per-app language.
    static func setLanguage(_ language: String?) {
        // Clear override → use system
        guard let language, !language.isEmpty else {
            objc_setAssociatedObject(Bundle.main, &kLangBundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            object_setClass(Bundle.main, Bundle.self) // restore default
            return
        }

        // Load the lproj bundle
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            return
        }

        objc_setAssociatedObject(Bundle.main, &kLangBundleKey, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Install proxy bundle once
        if object_getClass(Bundle.main) !== LangProxyBundle.self {
            object_setClass(Bundle.main, LangProxyBundle.self)
        }
    }


    private final class LangProxyBundle: Bundle {
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            if let langBundle = objc_getAssociatedObject(Bundle.main, &kLangBundleKey) as? Bundle {
                return langBundle.localizedString(forKey: key, value: value, table: tableName)
            }
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}
// MARK: Language Picker
struct LanguagePickerView: View {
    let supportedLanguages = Bundle.main.localizations.filter { $0 != "Base" }
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(supportedLanguages, id: \.self) { langCode in
                    let languageName = Locale(identifier: langCode).localizedString(forIdentifier: langCode) ?? langCode
                    Button(action: {
                        selectedLanguage = langCode
                        LocalizationManager.shared.setLanguage(langCode)
                        dismiss()
                    }) {
                        HStack {
                            Text(languageName.capitalized)
                            Spacer()
                            if selectedLanguage == langCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("select_language".localized())
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if selectedLanguage.isEmpty {
                if let deviceLang = Locale.preferredLanguages.first?.prefix(2),
                   supportedLanguages.contains(String(deviceLang)) {
                    selectedLanguage = String(deviceLang)
                    LocalizationManager.shared.setLanguage(selectedLanguage)
                }
            }
        }
    }
}

struct FAQItem: Identifiable {
    let id = UUID()
    var question: String
    var answer: String
    var isExpanded: Bool = false
}

struct DeviceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @Environment(\.colorScheme) private var colorScheme
    private var isSystemDark: Bool {
        selectedAppearance == .system && colorScheme == .dark
    }
    private var foreground: Color {
        if isSelected {
            // Special cases
            if selectedAccent == .default &&
                (selectedAppearance == .dark || isSystemDark) {
                return .black
            } else {
                return .white
            }
        } else {
            return selectedAccent.color
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(foreground)
                .lineLimit(1)                 // 👈 never wrap
                .minimumScaleFactor(0.7)      // 👈 shrink text if needed
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? selectedAccent.color : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedAccent.color, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

enum Device {
    case iphone, vibro
}

extension View {
    func rowLeading(_ inset: CGFloat) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, inset)
    }
}

private struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

struct CircularToolbarButton: View {
    let systemName: String
    var accent: Color? = nil
    let action: () -> Void
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent ?? selectedAccent.color)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .shadow(radius: 2, y: 1)
        .contentShape(Rectangle())    
        .accessibilityAddTraits(.isButton)
    }
}

private struct SettingsRowLabel: View {
    let text: String
    let systemName: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .imageScale(.large)
                .frame(width: 28, height: 28)
            Text(text)
                .font(.body)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct LinkRow: View {
    let title: String
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SettingsRowLabel(text: title, systemName: systemName)
        }
        .buttonStyle(.plain)
    }
}

extension AppearanceOption {
    /// Given the system scheme, compute the app’s effective scheme.
    func resolve(using systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return systemScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum AppearanceOption: String, CaseIterable, Codable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "system".localized()
        case .light: return "light".localized()
        case .dark: return "dark".localized()
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension AppIconOption {
    func mapped(to background: IconBackground) -> AppIconOption? {
        switch (self, background) {

        // Base swap
        case (.default, .black): return .black
        case (.black, .white):   return .default

        // Keep same hue when possible
        case (.white_blue,   .black): return .black_blue
        case (.white_yellow, .black): return .black_yellow
        case (.white_orange, .black): return .black_orange
        case (.white_green,  .black): return .black_green
        case (.white_purple, .black): return .black_purple
        case (.white_pink,   .black): return .black_pink

        case (.black_blue,   .white): return .white_blue
        case (.black_yellow, .white): return .white_yellow
        case (.black_orange, .white): return .white_orange
        case (.black_green,  .white): return .white_green
        case (.black_purple, .white): return .white_purple
        case (.black_pink,   .white): return .white_pink

        default:
            return nil
        }
    }
}


enum AccentColorOption: String, CaseIterable, Codable {
    case `default`, orange, yellow, green, blue, pink, purple

    var displayName: String {
        switch self {
        case .default: return "default".localized()
        case .orange: return "orange".localized()
        case .yellow: return "yellow".localized()
        case .green: return "green".localized()
        case .blue: return "blue".localized()
        case .pink: return "pink".localized()
        case .purple: return "purple".localized()
        }
    }

    var color: Color {
        switch self {
        case .default: return .primary
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .purple: return .purple
        }
    }
}

enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "AppIcon"
    case black      = "AppIcon-White"
    case black_pink      = "AppIcon-Black-Pink"
    case black_orange    = "AppIcon-Black-Orange"
    case black_yellow    = "AppIcon-Black-Yellow"
    case black_green     = "AppIcon-Black-Green"
    case black_purple    = "AppIcon-Black-Purple"
    case black_blue      = "AppIcon-Black-Blue"
    case white_blue      = "AppIcon-White-Blue"
    case white_yellow      = "AppIcon-White-Yellow"
    case white_orange      = "AppIcon-White-Orange"
    case white_green     = "AppIcon-White-Green"
    case white_purple     = "AppIcon-White-Purple"
    case white_pink     = "AppIcon-White-Pink"

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .default: return "default".localized()
        case .black: return "black".localized()
        case .black_pink:    return "pink".localized()
        case .black_orange:  return "orange".localized()
        case .black_yellow:  return "yellow".localized()
        case .black_green:   return "green".localized()
        case .black_purple:  return "purple".localized()
        case .black_blue:    return "blue".localized()
        case .white_blue:    return "blue".localized()
        case .white_yellow:  return "yellow".localized()
        case .white_orange:  return "orange".localized()
        case .white_green:   return "green".localized()
        case .white_purple:  return "purple".localized()
        case .white_pink:    return "pink".localized()
        }
    }

    /// Name of the **preview image** in Assets.xcassets (not the app icon set!)
    var previewAssetName: String {
        switch self {
        case .default: return "AppIcon-Preview"
        case .black: return "AppIcon-White-Preview"
        case .black_pink:    return "AppIcon-Black-Pink-Preview"
        case .black_orange:  return "AppIcon-Black-Orange-Preview"
        case .black_yellow:  return "AppIcon-Black-Yellow-Preview"
        case .black_green:   return "AppIcon-Black-Green-Preview"
        case .black_purple:  return "AppIcon-Black-Purple-Preview"
        case .black_blue:      return "AppIcon-Black-Blue-Preview"
        case .white_blue:      return  "AppIcon-White-Blue-Preview"
        case .white_yellow:      return "AppIcon-White-Yellow-Preview"
        case .white_orange:      return "AppIcon-White-Orange-Preview"
        case .white_green:     return "AppIcon-White-Green-Preview"
        case .white_purple:     return "AppIcon-White-Purple-Preview"
        case .white_pink:     return "AppIcon-White-Pink-Preview"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .black:   return "AppIcon-White"                   // ← primary ("AppIcon")
        case .default: return nil     // ← MUST exist in AlternateIcons, or choose another valid key
        default:       return rawValue
        }
    }
}
enum IconBackground: String, CaseIterable, Identifiable {
    case black
    case white
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: return "black".localized()
        case .white: return "white".localized()
        }
    }
}

extension AppIconOption {
    /// For sorting: base item (Default/White) first, then colors starting at Blue.
    fileprivate var isBaseForBackground: Bool {
        switch self {
        case .default, .black: return true
        default: return false
        }
    }

    /// Color priority within a background family
    fileprivate var huePriority: Int {
        switch self {
        case .black_blue, .white_blue:     return 0   // Blue first
        case .black_yellow, .white_yellow: return 1
        case .black_orange, .white_orange: return 2
        case .black_green, .white_green:   return 3
        case .black_purple, .white_purple: return 4
        case .black_pink, .white_pink:     return 5
        // Base (Default/White) gets -1 so it appears before the colors (optional)
        case .default, .black:             return -1
        }
    }
}

extension AppIconOption {
    /// Which background family this option belongs to
    var background: IconBackground {
        switch self {
        case .default,
             .white_blue,
             .white_yellow,
             .white_orange,
             .white_green,
             .white_purple,
             .white_pink:
            return .white

        case .black_pink,
             .black_orange,
             .black_yellow,
             .black_green,
             .black_purple,
             .black_blue,
             .black: // treat default as part of black set
            return .black

        @unknown default:
            // Fallback in case new icons are added later
            return .black
        }
    }
}


struct AppIconPickerRow: View {
    @Binding var selectedIcon: AppIconOption
    @State private var showSheet = false
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system


    var body: some View {
        HStack {
            Text("app_icon".localized())
                .font(.headline)

            Spacer()

            Button {
                showSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(selectedIcon.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text(selectedIcon.displayName)
                        .foregroundStyle(.secondary)


                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSheet) {
                AppIconPickerSheet(selectedIcon: $selectedIcon, isPresented: $showSheet)
            }
        }

    }
}


extension AppIconOption {
    /// If icon has black background -> force Dark mode, else Light mode
    var derivedAppearance: AppearanceOption {
        switch self.background {
        case .black: return .dark
        case .white: return .light
        }
    }
}

enum IconPreflightResult {
    case ok(String)
    case warn(String)
    case fail(String)
}
extension AppIconOption {
    /// Derive accent from icon "color". Base icons => .default
    var derivedAccent: AccentColorOption {
        switch self {
        case .black_blue, .white_blue:       return .blue
        case .black_yellow, .white_yellow:   return .yellow
        case .black_orange, .white_orange:   return .orange
        case .black_green, .white_green:     return .green

        // If you want to support these too, keep them:
        case .black_pink, .white_pink:       return .pink
        case .black_purple, .white_purple:   return .purple

        // Base icons (your “black/white default”)
        case .default, .black:               return .default
        }
    }
}
extension View {
    @ViewBuilder
    func presentationGrayBackgroundIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(Color(.systemGray5))
        } else {
            self
        }
    }
}

struct AppIconPickerSheet: View {
    @Binding var selectedIcon: AppIconOption
    @Binding var isPresented: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var showIconAlert = false
    @State private var iconMessage = ""

    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @State private var pageResetID = UUID()

    @State private var selectedBackground: IconBackground? = nil
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                
                Spacer().frame(height: 20)
                HStack {
                    Text("background".localized())
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("", selection: $selectedBackground) {
                        ForEach(IconBackground.allCases) { bg in
                            Text(bg.displayName).tag(bg)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                .padding(.horizontal)
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(filteredOptions) { option in
                                AppIconOptionCell(
                                    option: option,
                                    isSelected: option == selectedIcon
                                )
                                .id(option.id)
                                .onTapGesture {
                                    withAnimation(.snappy) {
                                        selectIcon(option, showToast: true)
                                        proxy.scrollTo(option.id, anchor: .center)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(selectedIcon.id, anchor: .center)
                        }
                    }
                    .onChange(of: selectedBackground) { _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo(selectedIcon.id, anchor: .center)
                        }
                    }
                    .onChange(of: selectedIcon) { newIcon in
                        DispatchQueue.main.async {
                            proxy.scrollTo(newIcon.id, anchor: .center)
                        }
                    }
                }
                
                Spacer()
            }
            // ✅ This makes the content area always systemGray5
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemGray5))
        }
        // ✅ This makes the *sheet material behind the nav stack* also systemGray5 (iOS 16+)
        .presentationGrayBackgroundIfAvailable()
        .preferredColorScheme(selectedAppearance.colorScheme)   // ✅ makes env colorScheme change
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.4)])
        .presentationDragIndicator(.hidden)
        
        .onAppear {
            // ✅ If user wants .system appearance, derive background from device scheme
            applySystemBackgroundIfNeeded()
            
            // Keep your existing "restore from icon" logic if you want,
            // but DO NOT overwrite selectedBackground when appearance is .system.
            let accent = selectedIcon.derivedAccent
            if selectedAccent != accent { selectedAccent = accent }
            
            let appearance = selectedIcon.derivedAppearance
            if selectedAppearance != appearance { selectedAppearance = appearance }
            
            // If not .system, it’s safe to sync background from icon
            if selectedAppearance != .system {
                let bg = selectedIcon.background
                if selectedBackground != bg { selectedBackground = bg }
            }
        }
        .onChange(of: colorScheme) { _ in
            // ✅ When device switches Light/Dark while using .system
            applySystemBackgroundIfNeeded()
        }
        .onChange(of: selectedAppearance) { newValue in
            // ✅ When user toggles appearance back to .system
            if newValue == .system {
                applySystemBackgroundIfNeeded()
            }
        }
        .onChange(of: selectedBackground) { newBg in
            guard let bg = newBg else { return }

            if let mapped = selectedIcon.mapped(to: bg) {
                selectIcon(mapped)
            } else {
                coerceSelectionIntoCurrentBackground()
                selectIcon(selectedIcon)
            }
        }

    

    }
    private func applySystemBackgroundIfNeeded() {
        guard selectedAppearance == .system else { return }

        let target: IconBackground = (colorScheme == .dark) ? .black : .white
        guard selectedBackground != target else { return }

        selectedBackground = target

        // Optional: also coerce icon to match the new background immediately
        // so the row doesn’t go empty / mismatched.
        if let mapped = selectedIcon.mapped(to: target) {
            selectIcon(mapped)
        } else {
            coerceSelectionIntoCurrentBackground()
            selectIcon(selectedIcon)
        }
    }
    private var filteredOptions: [AppIconOption] {
        AppIconOption.allCases
            .filter { $0.background == selectedBackground }
            .sorted {
                // Base first (Default/White), then by huePriority
                if $0.isBaseForBackground != $1.isBaseForBackground {
                    return $0.isBaseForBackground && !$1.isBaseForBackground
                }
                return $0.huePriority < $1.huePriority
            }
    }
    private func selectIcon(_ icon: AppIconOption, showToast: Bool = false) {
        // ✅ Always keep the segmented control in sync with the selected icon
        if selectedBackground != icon.background {
            selectedBackground = icon.background
        }

        guard icon != selectedIcon else { return }

        selectedIcon = icon
        selectedAccent = icon.derivedAccent
        selectedAppearance = icon.derivedAppearance

        applyAlternateIcon(icon) { msg in
            guard showToast else { return }
            iconMessage = msg
            showIconAlert = true
        }
    }





    private func coerceSelectionIntoCurrentBackground() {
        guard !filteredOptions.contains(selectedIcon) else { return }
        if let first = filteredOptions.first {
            selectedIcon = first
        }
    }

    func applyAlternateIcon(_ option: AppIconOption, show: @escaping (String)->Void) {
    #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else {
            show("This device doesn’t support alternate icons.")
            return
        }

        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            if let error = error {
                show("Failed to set icon: \(error.localizedDescription)")
            } else {
                show("Icon changed to \(option.displayName).")
            }
        }
    #else
        show("Alternate icons are only supported on iOS.")
    #endif
    }
}


struct BlockedUsersSheet: View {
    @Binding var blockedUIDs: [String]
    var unblockAction: (_ uid: String, _ completion: @escaping (_ error: Error?) -> Void) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isBusy: Set<String> = []
    @State private var lastError: String?

    // Name resolution state
    @State private var nameCache: [String: String] = [:]           // uid -> displayName
    @State private var pendingLookups: Set<String> = []            // uids currently being fetched

    var body: some View {
        NavigationView {
            Group {
                if blockedUIDs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .imageScale(.large)
                            .font(.system(size: 36))
                        Text("no_blocked_users".localized())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(blockedUIDs, id: \.self) { uid in
                            HStack(spacing: 12) {
                                // Leading avatar placeholder (optional)
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(nameCache[uid] ?? "…")
                                            .font(.body)
                                            .lineLimit(1)

                                        if pendingLookups.contains(uid) && nameCache[uid] == nil {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    unblock(uid)
                                } label: {
                                    if isBusy.contains(uid) {
                                        ProgressView()
                                    } else {
                                        Text("unblock_user".localized())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                                .disabled(isBusy.contains(uid))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    unblock(uid)
                                } label: {
                                    Text("unblock_user".localized())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .tint(.green)
                                .disabled(isBusy.contains(uid))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("blocked_users".localized())
            .alert(lastError ?? "", isPresented: Binding(
                get: { lastError != nil },
                set: { if !$0 { lastError = nil } }
            )) {
                Button("ok".localized(), role: .cancel) { lastError = nil }
            }
            .onAppear {
                refreshNames()
            }
            .onChange(of: blockedUIDs) { _ in
                refreshNames()
            }
        }
    }

    // MARK: - Actions

    private func unblock(_ uid: String) {
        guard !isBusy.contains(uid) else { return }
        isBusy.insert(uid)
        unblockAction(uid) { error in
            isBusy.remove(uid)
            if let error = error {
                lastError = error.localizedDescription
            } else {
                // Optionally clear cache entry when unblocked & removed externally by parent
                nameCache.removeValue(forKey: uid)
                pendingLookups.remove(uid)
            }
        }
    }

    // MARK: - Name fetching

    private func refreshNames() {
        // Fetch only missing names and avoid duplicate concurrent fetches
        let targets = blockedUIDs.filter { nameCache[$0] == nil && !pendingLookups.contains($0) }
        fetchUserNamesBatching(uids: targets)
    }

    /// Batches in chunks of 10 due to Firestore `in` query limits.
    private func fetchUserNamesBatching(uids: [String]) {
        guard !uids.isEmpty else { return }

        let db = Firestore.firestore()
        let chunks: [[String]] = stride(from: 0, to: uids.count, by: 10).map {
            Array(uids[$0..<min($0 + 10, uids.count)])
        }

        // Mark all as pending right away to prevent duplicate requests
        pendingLookups.formUnion(uids)

        for chunk in chunks {
            db.collection("Followers")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snap, error in
                    if let error = error {
                        print("[BlockedUsersSheet] name fetch error:", error.localizedDescription)
                        // Let UI retry later by removing from pending (keep cache empty)
                        DispatchQueue.main.async {
                            self.pendingLookups.subtract(chunk)
                        }
                        return
                    }

                    var updates: [String: String] = [:]

                    // Fill results we got
                    snap?.documents.forEach { doc in
                        let raw = doc.get("UserName") as? String
                        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
                        updates[doc.documentID] = (name?.isEmpty == false) ? name! : ""
                    }

                    // For any requested UID missing from the snapshot, record a graceful fallback
                    let foundIDs = Set(snap?.documents.map { $0.documentID } ?? [])
                    let missing = Set(chunk).subtracting(foundIDs)
                    for uid in missing {
                        // You could choose to keep nil to retry later; here we store the UID as fallback
                        updates[uid] = uid
                    }

                    DispatchQueue.main.async {
                        self.nameCache.merge(updates) { _, new in new }
                        self.pendingLookups.subtract(chunk)
                    }
                }
        }
    }
}


struct AppIconOptionCell: View {
    let option: AppIconOption
    let isSelected: Bool
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    var body: some View {
        VStack(spacing: 8) {
            Image(option.previewAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? selectedAccent.color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                )
                .shadow(radius: isSelected ? 8 : 2, y: isSelected ? 4 : 1)

            Text(option.displayName)
                .font(.footnote)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: 96)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(6)
    }
}
private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SegmentCell<Icon: View>: View {
    let icon: Icon
    let title: String
    let iconScale: CGFloat   // e.g. 0.7

    @State private var textHeight: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let H = g.size.height
            let W = g.size.width
            let S = min(W, H) * iconScale
            let gap = max(0, (H - S - textHeight) / 2)

            ZStack {
                // Icon centered vertically regardless of label size
                icon
                    .frame(width: S, height: S)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, gap)
                    .padding(.bottom, gap + textHeight)
                    .allowsHitTesting(false)
            }
            .overlay(
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)   // or any custom Color
                    .background(
                        GeometryReader { t in
                            Color.clear
                                .preference(key: TextHeightKey.self, value: t.size.height)
                        }
                    )
                    .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
                    .padding(.bottom, gap),                 // <- same as top empty space
                alignment: .bottom
            )
            .contentShape(Rectangle())
        }
    }
}


struct ShapeSelector: View {
    @Binding var selection: DisplayMethod
    var accent: Color
    var height: CGFloat = 140
    var cornerRadius: CGFloat = 18
    
    @Namespace private var anim
    
    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 3
            let contentW = geo.size.width - inset * 2
            let contentH = geo.size.height - inset * 2
            
            // 1-pixel on current screen
            let px = 1 / UIScreen.main.scale
            
            // Split width exactly, accounting for the center hairline
            let segmentW = (contentW - px) / 2
            
            let outer = max(0, cornerRadius - 2)
            let leftOuterSel  = selection == .sphere ? outer : 0
            let rightOuterSel = selection == .plane  ? outer : 0
            let leftOuterUn   = selection == .plane  ? outer : 0
            let rightOuterUn  = selection == .sphere ? outer : 0
            
            ZStack {
                // Unselected background
                UnevenRoundedRectangle(
                    topLeadingRadius: leftOuterUn, bottomLeadingRadius: leftOuterUn,
                    bottomTrailingRadius: rightOuterUn, topTrailingRadius: rightOuterUn,
                    style: .continuous
                )
                .fill(accent.opacity(0.05))
                .frame(width: segmentW, height: contentH)
                .frame(maxWidth: .infinity,
                       alignment: selection == .sphere ? .trailing : .leading)
                
                // Selected highlight
                UnevenRoundedRectangle(
                    topLeadingRadius: leftOuterSel, bottomLeadingRadius: leftOuterSel,
                    bottomTrailingRadius: rightOuterSel, topTrailingRadius: rightOuterSel,
                    style: .continuous
                )
                .fill(accent.opacity(0.18))
                .frame(width: segmentW, height: contentH)
                .frame(maxWidth: .infinity,
                       alignment: selection == .sphere ? .leading : .trailing)
                .matchedGeometryEffect(id: "slider", in: anim)
                
                // Content: make the two buttons split space evenly
                HStack(spacing: 0) {
                    Button { selection = .sphere } label: {
                        SegmentCell(icon: StaticRotatingSphereView(accent: accent),
                                    title: "sphere_title".localized(),
                                    iconScale: 0.7)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // REMOVE Divider() from layout; draw center line as overlay instead
                    
                    Button { selection = .plane } label: {
                        SegmentCell(icon: StaticPlainGrid3DView(accent: accent).opacity(0.3),
                                    title: "plain".localized(),
                                    iconScale: 0.7)
                    }
                    .disabled(true)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 1-pixel center hairline that doesn't affect layout
                Rectangle().frame(width: px, height: contentH).opacity(0.15)
            }
            // Fix the drawing box to the computed size, then pad once
            .frame(width: contentW, height: contentH)
            .padding(inset)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: selection)
        }
        .frame(height: height)
    }
}


struct CheckXToggleStyle: ToggleStyle {
    var accent: Color
    
    @AppStorage("selectedOption") private var selectedOption: Int = 1
    @AppStorage("motorFirst") private var motorFirst: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy) {
                configuration.isOn.toggle()
                motorFirst = configuration.isOn   // keep in sync with AppStorage
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 8) {
                if configuration.isOn {
                    Image(
                        selectedOption == 1 ? "line" :
                        selectedOption == 3 ? "3menu" :
                        "2line"
                    )
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(90))
                        
                } else {
                    Image("delay")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isButton)
    }
}




struct SettingsView: View {
    @EnvironmentObject var sharedData: SharedData   
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isSignedIn = false
    @State private var userName: String = ""
    @State private var userEmail: String = ""
    @State private var ColorScheme: Bool = UserDefaults.standard.object(forKey: "ColorScheme") as? Bool
    ?? (UITraitCollection.current.userInterfaceStyle == .dark)
    @EnvironmentObject var functions: Functions
    @State private var isScanning = false
    @State private var activeBlinkCircleIndex = 0
    @State private var targetPeripherals:[String] = ["Vibro1", "Vibro2"]
    @State private var showPeripheralSelection = false
    @State private var selectedPeripheral: CBPeripheral?

    @EnvironmentObject var personalModelsFunctions: PersonalModelsFunctions
    
    @State private var selectedDevice: Device = .iphone
    @State private var handleUserLeave: Bool = false
    
    
    @State private var TapCircleSize: CGFloat = 0.0
    @State private var isPhotoPickerPresented: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var imageOffset: CGSize = .zero
    @State private var isAdjustingImage = false
    @State private var circleOffset = CGSize.zero
    @State private var handlingSigningOut: Bool = false
    @AppStorage("savedImageData") private var savedImageData: String = ""
    @AppStorage("ScrollsAutoplay") private var ScrollsAutoplay: Bool = true
    @State private var showLanguageSheet = false
    @State private var selectedLanguage = LocalizationManager.shared.currentLanguage
    private let firstRunKey = "HasCompletedWelcomeGate"
    private let signedInKey = "IsSignedIn"
    @State private var showWelcomeGate = false
    private let defaults = UserDefaults.standard
    @AppStorage("selectedAppearance") private var selectedAppearance: AppearanceOption = .system
    @AppStorage("selectedAccent") private var selectedAccent: AccentColorOption = .default
    @AppStorage("selectedIcon") private var selectedIcon: AppIconOption = .default
    let sideInset: CGFloat = 20
    @State private var handlingDeletion: Bool = false
    private let appleHelper = AppleSignInHelper()
    @State private var showBlockedSheet = false
    @EnvironmentObject var publishFunctionality: PublishFunctionality
    @AppStorage("selectedDisplayMethod") private var selectedDisplayMethod: DisplayMethod = .sphere
    @State private var showLoading = false
    @AppStorage("selectedOption") private var selectedOption: Int = 1
    @AppStorage("motorFirst") private var motorFirst: Bool = true
    @AppStorage("useMicrophone") private var useMicrophone = false

    @State private var isRequesting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showEULA = false
    @State private var showBuy = false
    @State private var usdzPage = 0

    // Example data (use your own)
    private let usdzItems: [(title: String, file: String)] = [
        ("iPhone", "Box"),
        ("Other", "other_model")
    ]
    @State private var dragX: CGFloat = 0
    @GestureState private var isDragging = false
    @AppStorage("tapData") private var tapDataJSON: Data = Data()
    @AppStorage("onAppModelDescription") private var onAppModelDescription: Data = Data()
    @AppStorage("singleModelImageData") private var singleModelImageData: Data = Data()
    @AppStorage("NoHands") private var NoHands: Bool = false
    @State private var refreshID = UUID()
    private let appleEmailKey = "appleEmail"

    private func refreshPage() {
        refreshID = UUID()
    }
    @AppStorage("useAICompanion") private var useAICompanion: Bool = false
    @State private var showCwCLoginAlert = false
    @State private var deletingChatHistory = false
    @State private var showSubscriptionView = false
    @AppStorage ("selectedPlan") private var selectedPlan = "Basic"
    let api = AIRespondsAPI()
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmText = ""
    var body: some View {
        Group {
            ZStack(alignment: .top) {
                // Accent background only behind content, not into top safe area
                selectedAccent.color.opacity(0.08)
                    .ignoresSafeArea(edges: [.bottom])   // <- no .top, so header area uses system background
                
                NavigationStack {
                    GeometryReader { geometry in
                        let circleSize = min(geometry.size.width, geometry.size.height) * 0.28
                        
                        ScrollView {
                            VStack(alignment: .center, spacing: 20) {
                                
                                Text("personalization".localized())
                                    .font(.title)
                                    .frame(maxWidth: .infinity, alignment: .leading) // <- Ensures it's aligned left
                                // MARK: - Avatar / Activation Image
                                SectionCard {
                                    HStack(spacing: 12) {
                                        Text("connection_device".localized())
                                            .font(.headline)
                                        Spacer()
                                        
                                        DeviceChip(title: "iPhone", isSelected: selectedDevice == .iphone) {
                                            withAnimation(.snappy) { selectedDevice = .iphone }
                                        }
                                        
                                        if isScanning {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(.ultraThinMaterial)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(selectedAccent.color.opacity(0.6), lineWidth: 1)
                                                )
                                                .accessibilityLabel("Scanning".localized())
                                        } else {
                                            DeviceChip(title: "Vib", isSelected: selectedDevice == .vibro) {
                                                showPeripheralSelection = true
                                            }
                                        }
                                    }
 

                                    AppIconPickerRow(selectedIcon: $selectedIcon)

                                    HStack {
                                        Text("no_hands".localized())
                                            .font(.headline)
                                        Spacer()
                                        Toggle(isOn: $NoHands) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: selectedAccent.color)) // 👈 custom tint
                                    }
                                    
                                    
                                    HStack {
                                        Text("usemicrophone".localized())
                                            .font(.headline)
                                        Spacer()
                                        Toggle(isOn: Binding(
                                            get: { useMicrophone },
                                            set: { newValue in
                                                // Only handle the ON transition; OFF is immediate.
                                                guard newValue == true, isRequesting == false else {
                                                    useMicrophone = false
                                                    return
                                                }
                                                
                                                isRequesting = true
                                                Task {
                                                    let outcome = await VoicePermissionRequester.requestAll()
                                                    switch outcome {
                                                    case .allGranted:
                                                        // ✅ Persist ON only when BOTH permissions are granted
                                                        useMicrophone = true
                                                    case .micDenied:
                                                        useMicrophone = false
                                                        alertMessage = "mic_rec_perm_required".localized()
                                                        showAlert = true
                                                    case .speechDenied:
                                                        useMicrophone = false
                                                        alertMessage = "speech_rec_perm_required".localized()
                                                        showAlert = true
                                                    case .error(let msg):
                                                        useMicrophone = false
                                                        alertMessage = msg.isEmpty ? "could_request_voice_permission".localized() : msg
                                                        showAlert = true
                                                    }
                                                    isRequesting = false
                                                }
                                            }
                                        )) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: selectedAccent.color))
                                        .disabled(isRequesting) // prevent rapid taps while asking
                                    }
                                    .alert("permission_required".localized(), isPresented: $showAlert) {
                                        Button("ok".localized(), role: .cancel) { }
                                    } message: {
                                        Text(alertMessage)
                                    }
                                    /*
                                    HStack {
                                        Text("cwc".localized())
                                            .font(.headline)
                                        Spacer()
                                        Toggle(isOn: $useAICompanion) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: selectedAccent.color))
                                        .onChange(of: useAICompanion) { value in
                                            if value {
                                                if let user = Auth.auth().currentUser, !user.isAnonymous {
                                                    
                                                } else {
                                                    // User is not logged in OR is anonymous
                                                    showCwCLoginAlert = true
                                                    useAICompanion = false
                                                }
                                            }
                                        }
                                    }
                                    */
                                    
                                    HStack {
                                        Text("scrolls_auto_play".localized())
                                            .font(.headline)
                                        Spacer()
                                        Toggle(isOn: $ScrollsAutoplay) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: selectedAccent.color)) // 👈 custom tint
                                    }
                                    

                                    
                                    
                                    
                                    
                                    /*
                                     VStack(alignment: .leading){
                                     Text("network_type")
                                     .font(.headline)
                                     
                                     HStack(alignment: .center) {
                                     Spacer()
                                     ShapeSelector(
                                     selection: $selectedDisplayMethod,
                                     accent: selectedAccent.color,
                                     height: UIScreen.main.bounds.height * 0.15
                                     )
                                     
                                     .frame(width: min(UIScreen.main.bounds.width * 0.7, 420))
                                     Spacer()
                                     }
                                     .padding(.vertical, 8)
                                     }
                                     */
                                    
                                    
                                }
                                
                                // MARK: - Connection / Device
                                Text("Chatbot".localized())
                                    .font(.title)
                                    .frame(maxWidth: .infinity, alignment: .leading) // <- Ensures it's aligned left
                                
                                SectionCard {
                                    
                                    HStack {
                                        Text("Subscription".localized())
                                            .font(.headline)

                                        Spacer()

                                        Button(action: {
                                            showSubscriptionView = true
                                        }) {
                                            HStack(spacing: 4) {
                                                Text(selectedPlan == "Basic" ? "basic".localized() : "plus".localized())
                                                    .font(.headline)
                                                    .foregroundColor(.secondary)

                                                Image(systemName: "chevron.right")
                                                    .font(.headline)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Button(role: .destructive) {
                                        deletingChatHistory = true
                                        Task {
                                            do {
                                                let response = try await api.deleteChat()
                                                print(":", response.status)
                                                deletingChatHistory = false
                                            } catch {
                                                print("Error:", error)
                                                deletingChatHistory = false
                                            }
                                        }
                                    } label: {
                                        SettingsRowLabel(text: "Delete_chatbot_history".localized(), systemName: "trash")
                                    }
                                    
                                }
                                
                                // MARK: - Connection / Device
                                Text("account".localized())
                                    .font(.title)
                                    .frame(maxWidth: .infinity, alignment: .leading) // <- Ensures it's aligned left
                                
                                // MARK: - Auth
                                SectionCard {
                                    if
                                        let user = Auth.auth().currentUser,
                                        !user.isAnonymous
                                    {
                                        
                                        VStack(spacing: 8) {
                                            // Key–value rows that expand full width
                                            HStack(spacing: 12) {
                                                Text("user".localized())
                                                    .font(.headline)
                                                Spacer()
                                                Text(userEmail)
                                                    .textSelection(.enabled)
                                            }
                                            
                                            // 🔒 Blocked users sheet opener
                                            Button {
                                                showBlockedSheet = true
                                            } label: {
                                                SettingsRowLabel(
                                                    text: "blocked_users".localized(),
                                                    systemName: "person.crop.circle.badge.xmark" // <- requested icon
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .sheet(isPresented: $showBlockedSheet) {
                                                BlockedUsersSheet(
                                                    blockedUIDs: $sharedData.blockedUserIDs,
                                                    unblockAction: { uid, completion in
                                                        publishFunctionality.unblockUser(userToUnblockUID: uid) { result in
                                                            switch result {
                                                            case .success:
                                                                // remove locally too
                                                                if let idx = sharedData.blockedUserIDs.firstIndex(of: uid) {
                                                                    sharedData.blockedUserIDs.remove(at: idx)
                                                                }
                                                                completion(nil)
                                                            case .failure(let error):
                                                                completion(error)
                                                            }
                                                        }
                                                    }
                                                )
                                            }
                                            
                                            Button {
                                                handleGoogleSignOut()
                                                selectedPlan = "Basic"
                                                tapDataJSON = Data()
                                                onAppModelDescription = Data()
                                                singleModelImageData = Data()
                                                sharedData.publishedFavModels.removeAll()
                                                sharedData.personalModelsData.removeAll()
                                                useAICompanion = false
                                            } label: {
                                                SettingsRowLabel(text: "log_out".localized(), systemName: "rectangle.portrait.and.arrow.right")
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button(role: .destructive) {
                                                deleteConfirmText = ""
                                                showDeleteConfirm = true
                                            } label: {
                                                SettingsRowLabel(text: "delete_acc".localized(), systemName: "trash")
                                            }

                                        }
                                        
                                        
                                    } else {
                                        Button {
                                            showWelcomeGate = true
                                            tapDataJSON = Data()
                                            onAppModelDescription = Data()
                                            singleModelImageData = Data()
                                            selectedPlan = "Basic"
                                        } label: {
                                            SettingsRowLabel(text: "log_in".localized(),
                                                             systemName: "person.crop.circle.badge.plus")
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Opens sign in.".localized())
                                    }
                                }
                                
                                Text("about".localized())
                                    .font(.title)
                                    .frame(maxWidth: .infinity, alignment: .leading) // <- Ensures it's aligned left
                                SectionCard {
                                    VStack(spacing: 0) {
                                        
                                        LinkRow(
                                            title: "terms_of_use".localized(),
                                            systemName: "doc.text",
                                            action: {
                                                showEULA = true
                                            }
                                        )
                                        LinkRow(
                                            title: "privacy".localized(),
                                            systemName: "hand.raised",
                                            action: {
                                                if let url = URL(string: "https://www.bi-mach.com/vibnet/privacy-policy") {
                                                    openURL(url)
                                                }
                                            }
                                        )
                                        
                                        
                                        LinkRow(
                                            title: "support".localized(),
                                            systemName: "envelope",
                                            action: {
                                                if let url = URL(string: "mailto:support@bi-mach.com") {
                                                    openURL(url)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: geometry.size.width * 1.2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                        }
                        .onChange(of: selectedDisplayMethod) { _ in
                            showLoading = true
                        }
                        
                        
                        .sheet(isPresented: $isPhotoPickerPresented) {
                            PhotoPicker(
                                selectedImage: $selectedImage,
                                isAdjusting: $isAdjustingImage,
                                onSave: saveImageToAppStorage
                            )
                        }
                        .fullScreenCover(isPresented: $showSubscriptionView) {
                            SubscriptionView(
                                onSubscribe: { plan in
                                    print("Selected plan:", plan)
                                },
                                onRestore: {
                                    print("Restore purchases")
                                }
                            )
                            .ignoresSafeArea()
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
                        // Dim + popup
                        .overlay(
                            Group {
                                if showDeleteConfirm {
                                    Color.black.opacity(0.45)
                                        .ignoresSafeArea()
                                        .onTapGesture { }

                                    VStack(spacing: 18) {

                                        Text(selectedPlan == "Basic"
                                             ? "basic_account_deletion".localized()
                                             : "plus_account_deletion".localized())
                                            .font(.headline)
                                            .multilineTextAlignment(.center)

                                        TextField("DELETE_ACCOUNT".localized(), text: $deleteConfirmText)
                                            .textInputAutocapitalization(.characters)
                                            .disableAutocorrection(true)
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(selectedAccent.color.opacity(0.6))
                                            )

                                        HStack(spacing: 12) {

                                            Button {
                                                showDeleteConfirm = false
                                            } label: {
                                                Text("cancel".localized())
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                            }
                                            .foregroundStyle(Color.gray)

                                            Button(role: .destructive) {

                                                guard deleteConfirmText == "DELETE_ACCOUNT".localized() else { return }

                                                showDeleteConfirm = false
                                                handleDeletion()

                                                selectedPlan = "Basic"
                                                tapDataJSON = Data()
                                                onAppModelDescription = Data()
                                                singleModelImageData = Data()
                                                sharedData.publishedFavModels.removeAll()
                                                sharedData.personalModelsData.removeAll()
                                                useAICompanion = false

                                            } label: {
                                                Text("delete_acc".localized())
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                            }
                                            .foregroundStyle(Color.red.opacity(deleteConfirmText == "DELETE_ACCOUNT".localized() ? 1 : 0.3))
                                            .disabled(deleteConfirmText != "DELETE_ACCOUNT".localized())
                                        }

                                    }
                                    .padding(20)
                                    .frame(maxWidth: 320)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .shadow(radius: 12)
                                }
                                if handlingSigningOut {
                                    ZStack {
                                        
                                        VStack(spacing: 12) {
                                            RotatingSphereView()
                                                .frame(
                                                    width: UIScreen.main.bounds.width * 0.5,
                                                    height: UIScreen.main.bounds.width * 0.5
                                                )
                                            Text("signing_out".localized())
                                                .font(.headline)
                                        }
                                        .padding(24)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(radius: 10)
                                    }
                                    .transition(.opacity)
                                }
                                
                                if handlingDeletion {
                                    ZStack {
                                        
                                        VStack(spacing: 12) {
                                            RotatingSphereView()
                                                .frame(
                                                    width: UIScreen.main.bounds.width * 0.5,
                                                    height: UIScreen.main.bounds.width * 0.5
                                                )
                                            Text("DeletingAccount".localized())
                                                .font(.headline)
                                        }
                                        .padding(24)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(radius: 10)
                                    }
                                    .transition(.opacity)
                                }
                                
                                if deletingChatHistory {
                                    ZStack {
                                        
                                        VStack(spacing: 12) {
                                            RotatingSphereView()
                                                .frame(
                                                    width: UIScreen.main.bounds.width * 0.5,
                                                    height: UIScreen.main.bounds.width * 0.5
                                                )
                                            Text("DeletingChatHistory".localized())
                                                .font(.headline)
                                        }
                                        .padding(24)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(radius: 10)
                                    }
                                    .transition(.opacity)
                                }
                                if showLoading {
                                    ZStack {
                                        
                                        VStack(spacing: 12) {
                                            if selectedDisplayMethod == .sphere {
                                                RotatingSphereView()
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
                                }
                                if showCwCLoginAlert {
                                    Color.black.opacity(0.4)
                                        .ignoresSafeArea()
                                        .onTapGesture { showCwCLoginAlert = false }
                                    
                                    CustomAlertVertical(
                                        title: "you_must_be_logged_in_to_use".localized(),
                                        message: "cwc_full".localized(),
                                        buyAction: {
                                            
                                            showCwCLoginAlert = false
                                            showWelcomeGate = true
                                        },
                                        cancelAction: {
                                            showCwCLoginAlert = false
                                        }
                                    )
                                }
                                
                                if showPeripheralSelection {
                                    Color.black.opacity(0.45)
                                        .ignoresSafeArea()
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                                showPeripheralSelection = false
                                            }
                                        }
                                    
                                    // bottom sheet
                                    VStack(spacing: 10) {
                                        
                                        VStack(spacing: 16) {
                                            Text("select_a_device".localized())
                                                .font(.headline)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 8)
                                            
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                LazyHStack(spacing: 14) {
                                                    
                                                    USDZView(
                                                        fileName: usdzItems[0].file,
                                                        preloadedScene: USDZPreloader.shared.scene(for: usdzItems[0].file)
                                                    )
                                                    .frame(width: UIScreen.main.bounds.width - 80, height: 220)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                    
                                                }
                                                .padding(.horizontal, 8)
                                            }
                                            .frame(height: UIScreen.main.bounds.height * 0.35)
                                            
                                            
                                            Divider().opacity(0.3)
                                            
                                            Button {
                                                if let url = URL(string: "https://bi-mach.com/shop/p/vib") {
                                                    openURL(url)
                                                    withAnimation(.easeInOut) { selectedDevice = .iphone }
                                                }
                                            } label: {
                                                Label("Buy".localized(), systemImage: "bag")
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(selectedAccent.color)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                            }
                                        }
                                        
                                        .padding(.vertical, 16)
                                        .padding(.horizontal, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .fill(.regularMaterial)
                                        )
                                        .padding(.horizontal, 10)
                                        
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                                showPeripheralSelection = false
                                                selectedDevice = .iphone
                                            }
                                        } label: {
                                            Text("cancel".localized())
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(selectedAccent.color)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .fill(.regularMaterial)
                                        )
                                        .padding(.horizontal, 10)
                                    }
                                    .padding(.bottom, 20)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                
                            
                                }
                            }
                        )
                        .onAppear {
                            USDZPreloader.shared.preload(named: usdzItems[0].file)
                            loadUserState()
                            TapCircleSize = circleSize
                            fetchUserTapImage { img in
                                if let img = img {
                                    selectedImage = img
                                }
                            }
                        }
                        .sheet(isPresented: $showLanguageSheet) {
                            LanguagePickerView(selectedLanguage: $selectedLanguage)
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        topInsetBar
                    }
                }
            }
            
            .sheet(isPresented: $showEULA) {
                EULASheetOld(
                    preview: true,
                    onAgree: {
                        
                    },
                    onCancel: {
                        
                    }
                )
            }
            .overlay {
                /*
                ZStack(alignment: .bottom) {
                    // dim background
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                showPeripheralSelection = false
                            }
                        }
                    
                    // bottom sheet
                    VStack(spacing: 10) {
                        
                        VStack(spacing: 16) {
                            Text("select_a_device".localized())
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    
                                    USDZView(
                                        fileName: usdzItems[0].file,
                                        preloadedScene: USDZPreloader.shared.scene(for: usdzItems[0].file)
                                    )
                                    .frame(width: UIScreen.main.bounds.width - 80, height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    
                                }
                                .padding(.horizontal, 8)
                            }
                            .frame(height: UIScreen.main.bounds.height * 0.35)
                            
                            
                            Divider().opacity(0.3)
                            
                            Button {
                                if let url = URL(string: "https://bi-mach.com/shop/p/vib") {
                                    openURL(url)
                                    withAnimation(.easeInOut) { selectedDevice = .iphone }
                                }
                            } label: {
                                Label("Buy".localized(), systemImage: "bag")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(selectedAccent.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                        
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .padding(.horizontal, 10)
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                showPeripheralSelection = false
                                selectedDevice = .iphone
                            }
                        } label: {
                            Text("cancel".localized())
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selectedAccent.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .padding(.horizontal, 10)
                    }
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .opacity(showPeripheralSelection ? 1.0 : 0.0)
                .allowsHitTesting(showPeripheralSelection)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showPeripheralSelection)
                */
            }
            
            
            .preferredColorScheme(selectedAppearance.colorScheme)
            .animation(.easeInOut, value: selectedAccent)
            .animation(.easeInOut, value: selectedAppearance)
        }
        .id(refreshID)   // ✅ forces full rebuild of this screen
    }
    
    private var topInsetBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedAccent.color)
            }

            Text("settings".localized())
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .background(Color(.systemBackground))   // same opaque backing
        .overlay(Divider(), alignment: .bottom)
    }


    
    private func deleteTapImage() {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }

        let email = user.email ?? user.uid   // fallback to uid-based path if needed

        // Adjust this path if your storage layout differs
        let ref = Storage.storage().reference()
            .child("Users")
            .child(email)
            .child("TapImage.jpg")

        ref.delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Delete failed:", error.localizedDescription)
                    return
                }
                ImageDiskCache.shared.remove(identifier: ref.fullPath)
                selectedImage = nil
            }
        }
    }
    private func tapImageReference(for user: User) -> StorageReference {
        let ownerId = user.email ?? user.uid     // never ""
        return Storage.storage().reference()
            .child("Users")
            .child(ownerId)
            .child("TapImage.jpg")               // or .png — but be consistent
    }

    private func uploadTapImageToFirebase(_ image: UIImage) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }


        let ref = tapImageReference(for: user)   // <- same helper used by loader

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            print("[TapImage] Failed to convert image to JPEG.")
            return
        }
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(data, metadata: meta) { _, error in
            if let error = error {
                print("[TapImage] Upload error: \(error.localizedDescription)")
                return
            }
            // ✅ Save to disk with the exact same identifier
            ImageDiskCache.shared.save(image, identifier: ref.fullPath, quality: 0.9)
            print("[TapImage] Uploaded & cached:", ref.fullPath)
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
    
    private func saveImageToAppStorage(_ image: UIImage) {
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            uploadTapImageToFirebase(image)
        }
    }
    
    func fetchUserTapImage(completion: @escaping (UIImage?) -> Void) {
        guard
            let user = Auth.auth().currentUser,
            !user.isAnonymous
        else { return }


        let currentUID = user.uid
        let email = user.email ?? ""
        
        let storageRef = Storage.storage().reference()
            .child("Users")
            .child(email)
            .child("TapImage.jpg")
        
        // Step 3: Download the image data
        storageRef.getData(maxSize: 5 * 1024 * 1024) { data, error in
            if let error = error {
                print("Error downloading image: \(error)")
                completion(nil)
                return
            }
            
            if let data = data, let image = UIImage(data: data) {
                completion(image)
            } else {
                completion(nil)
            }
        }
        
    }
    
    private func startVibroFlow() {
        selectedDevice = .vibro
        isScanning = true
        showPeripheralSelection = false
        /*
        bluetoothManager.userInitiatedStartScanning {
            withAnimation {
                isScanning = false
                showPeripheralSelection = true
            }
        }
        */
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isScanning = false
                showPeripheralSelection = true
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

    
    func handleDeletion() {
        handlingDeletion = true
        // Perform sign-outs
        print("User signed out.")
        personalModelsFunctions.deleteAccount { success in
            DispatchQueue.main.async {
                handlingDeletion = false
                if success {
                    dismiss()
                    GIDSignIn.sharedInstance.signOut()
                    do { try Auth.auth().signOut() } catch {
                        print("Firebase signOut error: \(error)")
                    }
                    isSignedIn = false
                    saveUserState(userName: "", userEmail: "")
                    userName = ""
                    userEmail = ""
                } else {
                    dismiss()
                    GIDSignIn.sharedInstance.signOut()
                    do { try Auth.auth().signOut() } catch {
                        print("Firebase signOut error: \(error)")
                    }
                    isSignedIn = false
                    saveUserState(userName: "", userEmail: "")
                    userName = ""
                    userEmail = ""
                }
            }
        }

    
    }
    
    func handleGoogleSignOut() {
        handlingSigningOut = true

        // Perform sign-outs
        GIDSignIn.sharedInstance.signOut()
        do { try Auth.auth().signOut() } catch {
            print("Firebase signOut error: \(error)")
        }

        // Clear local state
        isSignedIn = false
        saveUserState(userName: "", userEmail: "")
        userName = ""
        userEmail = ""
        print("User signed out.")
        

        // Give the UI a moment to show the popup, then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            handlingSigningOut = false
            selectedAppearance = AppearanceOption.system
            selectedAccent = AccentColorOption.default
            refreshPage()              // ✅ add
            
        }
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
    
    private func loadUserState() {
        let defaults = UserDefaults.standard
        if let savedUserName = defaults.string(forKey: "GoogleUserName"),
           let savedUserEmail = defaults.string(forKey: "GoogleUserEmail") {
            userName = savedUserName
            userEmail = savedUserEmail
            isSignedIn = defaults.bool(forKey: "IsSignedIn")
        } else {
            print("No saved user state found.")
        }
    }
}
struct CustomAlertVertical: View {
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
            
            VStack {
                
                Button("log_in".localized(), action: buyAction)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
                    .foregroundStyle(selectedAccent.color)
                
                Button("cancel".localized(), action: cancelAction)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(selectedAccent.color.opacity(0.7))
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))

                
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
        .shadow(radius: 10)
        .padding(.horizontal, 40)
    }
}
