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
        Self.scheduleBackgroundTasks()
        // Both background URLSessions must exist before any delegate callback can arrive.
        // This is the only place they are created on a background launch (BGTask / session
        // events), where no scene — and therefore no SyncCoordinator.start() — ever runs.
        Uploader.shared.configureSession()
        TusUploader.shared.configureSession()
        // Setup push notifications
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // NOTE: applicationDidBecomeActive / applicationDidEnterBackground are intentionally
    // absent. This app declares UIApplicationSceneManifest, so UIKit never calls them —
    // scenePhase in ZyncloudApp drives badge clearing and task scheduling instead.

    // MARK: - BackgroundTasks

    static func scheduleBackgroundTasks() {
        // Cancel any existing tasks first
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processTaskId)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskId)

        // Processing task: longer, network + CPU allowed
        let processingReq = BGProcessingTaskRequest(identifier: processTaskId)
        processingReq.requiresNetworkConnectivity = true
        processingReq.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(processingReq)
            print("AppDelegate: Successfully scheduled processing task")
        } catch {
            print("AppDelegate: Processing task failed: \(error.localizedDescription)")
        }

        BackgroundTaskLog.shared.recordScheduled()

        // Light refresh task: quick checks
        let refreshReq = BGAppRefreshTaskRequest(identifier: refreshTaskId)
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
        BackgroundTaskLog.shared.recordRun(.processing)
        SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: "Started")

        // Reschedule tasks for next execution
        scheduleBackgroundTasks()

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

        let completion = SingleShotCompletion { success in
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            print("AppDelegate: BGProcessingTask expired")
            SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: "Expired")
            queue.cancelAllOperations()
            // Cancelling is not enough: the operation blocks on `group.wait()`, so its
            // completionBlock may not run before the system's patience runs out. Complete here
            // as well — the guard makes the duplicate harmless.
            completion.fire(success: false)
        }

        op.completionBlock = {
            let success = !op.isCancelled
            print("AppDelegate: BGProcessingTask completed - success: \(success)")
            SyncLogger.shared.logBackgroundTask(taskType: "Processing Task", message: success ? "Completed" : "Cancelled")
            completion.fire(success: success)
        }

        queue.addOperation(op)
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        print("AppDelegate: BGAppRefreshTask started")
        BackgroundTaskLog.shared.recordRun(.refresh)
        SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Started")

        // Reschedule tasks for next execution
        scheduleBackgroundTasks()

        // Completion is single-shot: expiry and a normal finish can race, and iOS kills the app
        // if the task is never completed while trapping if it is completed twice.
        let completion = SingleShotCompletion { success in
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            print("AppDelegate: BGAppRefreshTask expired")
            SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Expired")
            // Without this the app is SIGKILLed for letting the task expire uncompleted.
            completion.fire(success: false)
        }

        // Perform background sync - refresh tasks run more frequently than processing tasks
        SyncCoordinator.shared.performBackgroundSync {
            print("AppDelegate: Refresh task completed")
            SyncLogger.shared.logBackgroundTask(taskType: "Refresh Task", message: "Completed")
            completion.fire(success: true)
        }
    }

    // MARK: - Background URLSession bridging

    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    func application(_: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void)
    {
        backgroundCompletionHandlers[identifier] = completionHandler

        // The system completion handler must run on the main thread; the delegate callback
        // that triggers it arrives on the session's own queue.
        let finish: (String) -> Void = { [weak self] sessionId in
            DispatchQueue.main.async {
                self?.backgroundCompletionHandlers.removeValue(forKey: sessionId)?()
            }
        }

        // Dispatch on the identifier. Handing a TUS session to Uploader (as this used to do
        // unconditionally) builds a second URLSession on an identifier TusUploader already
        // owns, and leaves the TUS completion handler permanently uncalled — which iOS
        // punishes with reduced background time.
        let route = UploadRouting.route(
            forSessionIdentifier: identifier,
            tusSessionId: TusUploader.shared.sessionId,
            multipartSessionId: Uploader.shared.sessionId
        )
        switch route {
        case .tus:
            TusUploader.shared.onAllBackgroundEventsComplete = finish
            TusUploader.shared.configureSession(with: identifier)
        case .multipart:
            Uploader.shared.onAllBackgroundEventsComplete = finish
            Uploader.shared.configureSession(with: identifier)
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
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
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
