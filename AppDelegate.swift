






import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import GoogleSignIn
import UserNotifications
import FirebaseFirestore



@objc(AppDelegate)
class AppDelegate: NSObject, UIApplicationDelegate,
                   UNUserNotificationCenterDelegate, MessagingDelegate {

    private var cachedFCM: String?
    private var currentUID: String?
    static var shared: AppDelegate!
    // MARK: - Launch
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self


        SpherePreloader.warmUp()
        return true
    }
    
    var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        return orientationLock
    }

    // MARK: - Universal Links (https://links.bi-mach.com/...)
    // iOS will invoke this when a Universal Link is tapped.
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }

        DeepLinkRouter.shared.handle(url: url)
        return true
    }

    // MARK: - (Optional) Custom URL scheme support e.g. myapp://post/123
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        DeepLinkRouter.shared.handle(url: url)
        return true
    }

    // MARK: - Push: APNs/FCM
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, _ in
            self.cachedFCM = token
            self.tryClaimAndSaveToken()
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.cachedFCM = fcmToken
        self.tryClaimAndSaveToken()
    }

    // MARK: - Push: handle tap on a notification deep link (optional)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // If you include a URL in notification payload (e.g. userInfo["url"])
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            DeepLinkRouter.shared.handle(url: url)
        }
    }

    // MARK: - Token bookkeeping
    private func tryClaimAndSaveToken() {
        guard let uid = currentUID, let token = cachedFCM else { return }
        saveToken(uid: uid, token: token)   // client-side claim
    }

    private func unassignTokenFromPreviousUser() {
        guard let uid = currentUID, let token = cachedFCM else { return }
        let db = Firestore.firestore()
        db.collection("Followers").document(uid)
          .collection("deviceTokens").document(token)
          .delete { err in
              if let err = err { print("[Push] cleanup failed:", err.localizedDescription) }
          }
    }

    private func saveToken(uid: String, token: String) {
        let db = Firestore.firestore()
        db.collection("Followers").document(uid)
          .collection("deviceTokens").document(token)
          .setData([
              "createdAt": FieldValue.serverTimestamp(),
              "platform": "iOS",
              "bundleId": Bundle.main.bundleIdentifier ?? ""
          ], merge: true) { err in
              if let err = err { print("[Push] save failed:", err.localizedDescription) }
          }
    }
}
