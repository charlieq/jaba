import SwiftUI
import UserNotifications

@main
struct JABAApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            LocationListView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refresh() }
            case .background:
                Task { await BackgroundRefresh.schedule() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await JABAApp.handleBackgroundRefresh()
        }
    }

    static func handleBackgroundRefresh() async {
        await BackgroundRefresh.schedule()
        await AppModel.shared.backgroundRefresh()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }
}

/// Shows alerts as banners even while JABA is open.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
