import SwiftUI

extension Notification.Name {
    static let cloudKitDataDidChange = Notification.Name("cloudKitDataDidChange")
}

#if os(macOS)
import AppKit

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        NSApplication.shared.registerForRemoteNotifications()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
    }
}
#elseif os(iOS)
import UIKit

private final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
        completionHandler(.newData)
    }
}
#endif

@main struct MyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
