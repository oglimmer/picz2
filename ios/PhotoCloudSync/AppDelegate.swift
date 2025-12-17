import BackgroundTasks
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let processTaskId = "com.oglimmer.photosync.process"
    private static let refreshTaskId = "com.oglimmer.photosync.refresh"

    // MARK: - Early Registration (called from App init)

    static func registerBackgroundTasksEarly() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processTaskId, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                print("AppDelegate: Failed to cast task to BGProcessingTask")
                return
            }
            AppDelegate.handleProcessing(task: processingTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                print("AppDelegate: Failed to cast task to BGAppRefreshTask")
                return
            }
            AppDelegate.handleRefresh(task: refreshTask)
        }
        print("AppDelegate: Background tasks registered early")
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        scheduleBackgroundTasks()
        // Ensure background URLSession is ready to receive callbacks
        Uploader.shared.configureSession()
        // Setup push notifications
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationDidBecomeActive(_: UIApplication) {
        // Clear badge when app becomes active
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            print("AppDelegate: Cleared badge and all notifications")
        }
    }

    func applicationDidEnterBackground(_: UIApplication) {
        scheduleBackgroundTasks()
    }

    // MARK: - BackgroundTasks

    private func scheduleBackgroundTasks() {
        // Cancel any existing tasks first
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processTaskId)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskId)

        // Processing task: longer, network + CPU allowed
        let processingReq = BGProcessingTaskRequest(identifier: Self.processTaskId)
        processingReq.requiresNetworkConnectivity = true
        processingReq.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(processingReq)
            print("AppDelegate: Successfully scheduled processing task")
        } catch {
            print("AppDelegate: Processing task failed: \(error.localizedDescription)")
        }

        // Light refresh task: quick checks
        let refreshReq = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        refreshReq.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(refreshReq)
            print("AppDelegate: Successfully scheduled refresh task for 15 min from now")
        } catch {
            print("AppDelegate: Refresh task failed: \(error.localizedDescription)")
        }
    }

    private static func handleProcessing(task: BGProcessingTask) {
        print("AppDelegate: BGProcessingTask started")
        SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: "Started")

        // Reschedule tasks for next execution
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.scheduleBackgroundTasks()
            }
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let op = BlockOperation {
            let group = DispatchGroup()
            group.enter()
            SyncCoordinator.shared.performBackgroundSync {
                group.leave()
            }
            group.wait()
        }

        task.expirationHandler = {
            print("AppDelegate: BGProcessingTask expired")
            SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: "Expired")
            queue.cancelAllOperations()
        }

        op.completionBlock = {
            let success = !op.isCancelled
            print("AppDelegate: BGProcessingTask completed - success: \(success)")
            SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: success ? "Completed" : "Cancelled")
            task.setTaskCompleted(success: success)
        }

        queue.addOperation(op)
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        print("AppDelegate: BGAppRefreshTask started")
        SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Started")

        // Reschedule tasks for next execution
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.scheduleBackgroundTasks()
            }
        }

        task.expirationHandler = {
            print("AppDelegate: BGAppRefreshTask expired")
            SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Expired")
        }

        // Perform background sync - refresh tasks run more frequently than processing tasks
        SyncCoordinator.shared.performBackgroundSync {
            print("AppDelegate: Refresh task completed")
            SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Completed")
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Background URLSession bridging

    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    func application(_: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void)
    {
        backgroundCompletionHandlers[identifier] = completionHandler
        Uploader.shared.configureSession(with: identifier)
        Uploader.shared.onAllBackgroundEventsComplete = { sessionId in
            if let handler = self.backgroundCompletionHandlers.removeValue(forKey: sessionId) {
                handler()
            }
        }
    }

    // MARK: - Remote Notifications

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("AppDelegate: Registered for remote notifications")
        PushNotificationManager.shared.registerDeviceToken(deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("AppDelegate: Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    {
        let userInfo = response.notification.request.content.userInfo

        // Clear badge when user taps notification
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            print("AppDelegate: Cleared badge and all notifications after tap")
        }

        if let shareToken = userInfo["albumShareToken"] as? String {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenAlbumFromPush"),
                object: nil,
                userInfo: ["shareToken": shareToken],
            )
        }

        completionHandler()
    }
}
