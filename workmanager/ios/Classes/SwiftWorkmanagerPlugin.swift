import BackgroundTasks
import Flutter
import UIKit
import os

extension String {
    var lowercasingFirst: String {
        return prefix(1).lowercased() + dropFirst()
    }
}

public class SwiftWorkmanagerPlugin: FlutterPluginAppLifeCycleDelegate {
    static let identifier = "be.tramckrijte.workmanager"

    private static var flutterPluginRegistrantCallback: FlutterPluginRegistrantCallback?

    private struct ForegroundMethodChannel {
        static let channelName = "\(SwiftWorkmanagerPlugin.identifier)/foreground_channel_work_manager"

        struct Methods {
            struct Initialize {
                static let name = "\(Initialize.self)".lowercasingFirst
                enum Arguments: String {
                    case isInDebugMode
                    case callbackHandle
                }
            }

            struct RegisterOneOffTask {
                static let name = "\(RegisterOneOffTask.self)".lowercasingFirst
                enum Arguments: String {
                    case taskName
                    case uniqueName
                    case initialDelaySeconds
                    case inputData
                }
            }

            struct RegisterProcessingTask {
                static let name = "\(RegisterProcessingTask.self)".lowercasingFirst
                enum Arguments: String {
                    case taskName
                    case uniqueName
                    case initialDelaySeconds
                    case networkType
                    case requiresCharging
                }
            }

            struct RegisterPeriodicTask {
                static let name = "\(RegisterPeriodicTask.self)".lowercasingFirst
                enum Arguments: String {
                    case taskName
                    case uniqueName
                    case initialDelaySeconds
                }
            }

            struct CancelAllTasks {
                static let name = "\(CancelAllTasks.self)".lowercasingFirst
                enum Arguments: String {
                    case none
                }
            }

            struct CancelTaskByUniqueName {
                static let name = "\(CancelTaskByUniqueName.self)".lowercasingFirst
                enum Arguments: String {
                    case uniqueName
                }
            }

            struct PrintScheduledTasks {
                static let name = "\(PrintScheduledTasks.self)".lowercasingFirst
                enum Arguments: String {
                    case none
                }
            }
        }
    }

    @available(iOS 13.0, *)
    private static func handleBGProcessingTask(identifier: String, task: BGProcessingTask) {
        let operationQueue = OperationQueue()

        // Create an operation that performs the main part of the background task
        let operation = BackgroundTaskOperation(
            task.identifier,
            inputData: "",
            flutterPluginRegistrantCallback: SwiftWorkmanagerPlugin.flutterPluginRegistrantCallback,
            backgroundMode: .backgroundProcessingTask(identifier: identifier)
        )

        // Provide an expiration handler for the background task
        // that cancels the operation
        task.expirationHandler = {
            operation.cancel()
        }

        // Inform the system that the background task is complete
        // when the operation completes
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        // Start the operation
        operationQueue.addOperation(operation)
    }

    @available(iOS 13.0, *)
    public static func handlePeriodicTask(identifier: String, task: BGAppRefreshTask, earliestBeginInSeconds: Double?) {
        guard let callbackHandle = UserDefaultsHelper.getStoredCallbackHandle(),
              let _ = FlutterCallbackCache.lookupCallbackInformation(callbackHandle)
        else {
            logError("[\(String(describing: self))] \(WMPError.workmanagerNotInitialized.message)")
            return
        }

        // If frequency is not provided it will default to 15 minutes
        schedulePeriodicTask(taskIdentifier: task.identifier, earliestBeginInSeconds: earliestBeginInSeconds ?? (15 * 60))

        let operationQueue = OperationQueue()
        // Create an operation that performs the main part of the background task
        let operation = BackgroundTaskOperation(
            task.identifier,
            inputData: "",
            flutterPluginRegistrantCallback: SwiftWorkmanagerPlugin.flutterPluginRegistrantCallback,
            backgroundMode: .backgroundPeriodicTask(identifier: identifier)
        )

        // Provide an expiration handler for the background task that cancels the operation
        task.expirationHandler = {
            operation.cancel()
        }

        // Inform the system that the background task is complete when the operation completes
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        // Start the operation
        operationQueue.addOperation(operation)
    }

    /// Immediately starts a one off task
    @available(iOS 13.0, *)
    public static func startOneOffTask(identifier: String, taskIdentifier: UIBackgroundTaskIdentifier, inputData: String, delaySeconds: Int64) {
        let operationQueue = OperationQueue()
        // Create an operation that performs the main part of the background task
        let operation = BackgroundTaskOperation(
            identifier,
            inputData: inputData,
            flutterPluginRegistrantCallback: SwiftWorkmanagerPlugin.flutterPluginRegistrantCallback,
            backgroundMode: .backgroundOneOffTask(identifier: identifier)
        )

        // Inform the system that the task is complete when the operation completes
        operation.completionBlock = {
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }

        // Start the operation
        operationQueue.addOperation(operation)
    }

    /// Registers [BGAppRefresh] task name for the given identifier.
    /// You must register task names before app finishes launching in AppDelegate.
    @objc
    public static func registerPeriodicTask(withIdentifier identifier: String, frequency: NSNumber?) {
        if #available(iOS 13.0, *) {
            var frequencyInSeconds: Double?
            if let frequencyValue = frequency {
                frequencyInSeconds = frequencyValue.doubleValue
            }

            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: nil
            ) { task in
                if let task = task as? BGAppRefreshTask {
                    handlePeriodicTask(identifier: identifier, task: task, earliestBeginInSeconds: frequencyInSeconds)
                }
            }
        }
    }

    @objc
    @available(iOS 13.0, *)
    private static func schedulePeriodicTask(taskIdentifier identifier: String, earliestBeginInSeconds begin: Double) {
        if #available(iOS 13.0, *) {
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: begin)
            do {
                try BGTaskScheduler.shared.submit(request)
                logInfo("BGAppRefreshTask submitted \(identifier) earliestBeginInSeconds:\(begin)")
            } catch {
                logInfo("Could not schedule BGAppRefreshTask \(error.localizedDescription)")
                return
            }
        }
    }

    /// Registers [BGProcessingTask] task name for the given identifier.
    /// Task names must be registered before app finishes launching in AppDelegate.
    @objc
    public static func registerBGProcessingTask(withIdentifier identifier: String) {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: nil
            ) { task in
                if let task = task as? BGProcessingTask {
                    handleBGProcessingTask(identifier: identifier, task: task)
                }
            }
        }
    }

    /// Schedules a long running BackgroundProcessingTask
    @objc
    @available(iOS 13.0, *)
    private static func scheduleBackgroundProcessingTask(
        withIdentifier uniqueTaskIdentifier: String,
        earliestBeginInSeconds begin: Double,
        requiresNetworkConnectivity: Bool,
        requiresExternalPower: Bool
    ) {
        let request = BGProcessingTaskRequest(identifier: uniqueTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: begin)
        request.requiresNetworkConnectivity = requiresNetworkConnectivity
        request.requiresExternalPower = requiresExternalPower
        do {
            try BGTaskScheduler.shared.submit(request)
            logInfo("BGProcessingTask submitted \(uniqueTaskIdentifier) earliestBeginInSeconds:\(begin)")
        } catch {
            logInfo("Could not schedule BGProcessingTask identifier:\(uniqueTaskIdentifier) error:\(error.localizedDescription)")
            logInfo("Possible issues can be: running on a simulator instead of a real device, or the task name is not registered")
        }
    }

    static func callback(_: UIBackgroundFetchResult) {
    }
}

// MARK: - FlutterPlugin conformance

extension SwiftWorkmanagerPlugin: FlutterPlugin {

    @objc
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        flutterPluginRegistrantCallback = callback
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let foregroundMethodChannel = FlutterMethodChannel(
            name: ForegroundMethodChannel.channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftWorkmanagerPlugin()
        registrar.addMethodCallDelegate(instance, channel: foregroundMethodChannel)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        switch (call.method, call.arguments as? [AnyHashable: Any]) {
        case (ForegroundMethodChannel.Methods.Initialize.name, let .some(arguments)):
            initialize(arguments: arguments, result: result)
            return
        case (ForegroundMethodChannel.Methods.RegisterOneOffTask.name, let .some(arguments)):
            registerOneOffTask(arguments: arguments, result: result)
            return
        case (ForegroundMethodChannel.Methods.RegisterPeriodicTask.name, let .some(arguments)):
            registerPeriodicTask(arguments: arguments, result: result)
            return
        case (ForegroundMethodChannel.Methods.RegisterProcessingTask.name, let .some(arguments)):
            registerProcessingTask(arguments: arguments, result: result)
            return
        case (ForegroundMethodChannel.Methods.CancelAllTasks.name, .none):
            cancelAllTasks(result: result)
            return
        case (ForegroundMethodChannel.Methods.CancelTaskByUniqueName.name, let .some(arguments)):
            cancelTaskByUniqueName(arguments: arguments, result: result)
            return
        case (ForegroundMethodChannel.Methods.PrintScheduledTasks.name, .none):
            printScheduledTasks(result: result)
            return
        default:
            result(WMPError.unhandledMethod(call.method).asFlutterError)
            return
        }
    }

    private func initialize(arguments: [AnyHashable: Any], result: @escaping FlutterResult) {
        let method = ForegroundMethodChannel.Methods.Initialize.self
        guard let isInDebug = arguments[method.Arguments.isInDebugMode.rawValue] as? Bool,
              let handle = arguments[method.Arguments.callbackHandle.rawValue] as? Int64 else {
            result(WMPError.invalidParameters.asFlutterError)
            return
        }
        UserDefaultsHelper.storeCallbackHandle(handle)
        UserDefaultsHelper.storeIsDebug(isInDebug)
        result(true)
    }

    private func registerOneOffTask(arguments: [AnyHashable: Any], result: @escaping FlutterResult) {
        if !validateCallbackHandle(result: result) {
            return
        }

        if #available(iOS 13.0, *) {
            let method = ForegroundMethodChannel.Methods.RegisterOneOffTask.self
            guard let delaySeconds =
                arguments[method.Arguments.initialDelaySeconds.rawValue] as? Int64 else {
                result(WMPError.invalidParameters.asFlutterError)
                return
            }
            guard let uniqueTaskIdentifier =
                arguments[method.Arguments.uniqueName.rawValue] as? String else {
                result(WMPError.invalidParameters.asFlutterError)
                return
            }

            var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
            let inputData =
                    arguments[method.Arguments.inputData.rawValue] as? String

            taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: uniqueTaskIdentifier, expirationHandler: {
                // Mark the task as ended if time is expired, otherwise iOS might terminate and will throttle future executions
                UIApplication.shared.endBackgroundTask(taskIdentifier)
            })
            SwiftWorkmanagerPlugin.startOneOffTask(identifier: uniqueTaskIdentifier,
                                                  taskIdentifier: taskIdentifier,
                                                  inputData: inputData ?? "",
                                                  delaySeconds: delaySeconds)
            result(true)
            return
        } else {
            result(FlutterError(code: "99",
                                message: "OneOffTask could not be registered",
                                details: "BGTaskScheduler tasks are only supported on iOS 13+"))
        }
    }

    private func registerPeriodicTask(arguments: [AnyHashable: Any], result: @escaping FlutterResult) {
        if !validateCallbackHandle(result: result) {
            return
        }

        if #available(iOS 13.0, *) {
            let method = ForegroundMethodChannel.Methods.RegisterPeriodicTask.self
            guard let uniqueTaskIdentifier =
                arguments[method.Arguments.uniqueName.rawValue] as? String else {
                result(WMPError.invalidParameters.asFlutterError)
                return
            }
            let initialDelaySeconds =
                arguments[method.Arguments.initialDelaySeconds.rawValue] as? Double ?? 0.0

            SwiftWorkmanagerPlugin.schedulePeriodicTask(
                taskIdentifier: uniqueTaskIdentifier,
                earliestBeginInSeconds: initialDelaySeconds)
            result(true)
            return
        } else {
            result(FlutterError(code: "99",
                                message: "PeriodicTask could not be registered",
                                details: "BGAppRefreshTasks are only supported on iOS 13+. Instead you should use Background Fetch"))
        }
    }

    private func registerProcessingTask(arguments: [AnyHashable: Any], result: @escaping FlutterResult) {
        if !validateCallbackHandle(result: result) {
            return
        }

        if #available(iOS 13.0, *) {
            let method = ForegroundMethodChannel.Methods.RegisterProcessingTask.self
            guard let uniqueTaskIdentifier =
                arguments[method.Arguments.uniqueName.rawValue] as? String else {
                result(WMPError.invalidParameters.asFlutterError)
                return
            }
            let delaySeconds =
                arguments[method.Arguments.initialDelaySeconds.rawValue] as? Double ?? 0.0

            let requiresCharging = arguments[method.Arguments.requiresCharging.rawValue] as? Bool ?? false
            var requiresNetwork = false
            if let networkTypeInput = arguments[method.Arguments.networkType.rawValue] as? String,
               let networkType = NetworkType(fromDart: networkTypeInput),
               networkType == .connected || networkType == .metered {
                requiresNetwork = true
            }

            SwiftWorkmanagerPlugin.scheduleBackgroundProcessingTask(
                withIdentifier: uniqueTaskIdentifier,
                earliestBeginInSeconds: delaySeconds,
                requiresNetworkConnectivity: requiresNetwork,
                requiresExternalPower: requiresCharging)

            result(true)
            return
        } else {
            result(FlutterError(code: "99",
                                message: "BackgroundProcessingTask could not be registered",
                                details: "BGProcessingTasks are only supported on iOS 13+"))
        }
    }

    private func cancelAllTasks(result: @escaping FlutterResult) {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.cancelAllTaskRequests()
        }
        result(true)
    }

    private func cancelTaskByUniqueName(arguments: [AnyHashable: Any], result: @escaping FlutterResult) {
        if #available(iOS 13.0, *) {
            let method = ForegroundMethodChannel.Methods.CancelTaskByUniqueName.self
            guard let identifier = arguments[method.Arguments.uniqueName.rawValue] as? String else {
                result(WMPError.invalidParameters.asFlutterError)
                return
            }
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        result(true)
    }

    /// Checks whether getStoredCallbackHandle is set.
    /// Returns true when initialized, if false, result contains error message.
    private func validateCallbackHandle(result: @escaping FlutterResult) -> Bool {
        if UserDefaultsHelper.getStoredCallbackHandle() == nil {
            result(
                FlutterError(
                    code: "1",
                    message: "You have not properly initialized the Flutter WorkManager Package. " +
                        "You should ensure you have called the 'initialize' function first! " +
                        "Example: \n" +
                        "\n" +
                        "`Workmanager().initialize(\n" +
                        "  callbackDispatcher,\n" +
                        " )`" +
                        "\n" +
                        "\n" +
                        "The `callbackDispatcher` is a top level function. See example in repository.",
                    details: nil
                )
            )
            return false
        }
        return true
    }

    /// Prints details of un-executed scheduled tasks. To be used during development/debugging
    private func printScheduledTasks(result: @escaping FlutterResult) {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.getPendingTaskRequests { taskRequests in
                if taskRequests.isEmpty {
                    print("[BGTaskScheduler] There are no scheduled tasks")
                    result(true)
                    return
                }
                print("[BGTaskScheduler] Scheduled Tasks:")
                for taskRequest in taskRequests {
                    print("[BGTaskScheduler] Task Identifier: \(taskRequest.identifier) earliestBeginDate: \(taskRequest.earliestBeginDate?.formatted() ?? "")")
                }
                result(true)
            }
        } else {
            result(FlutterError(code: "99",
                                message: "printScheduledTasks is only supported on iOS 13+",
                                details: "BGTaskScheduler.getPendingTaskRequests is only supported on iOS 13+"))
        }
    }
}

// MARK: - AppDelegate conformance

extension SwiftWorkmanagerPlugin {

    override public func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) -> Bool {
        // Old background fetch API for iOS 12 and lower, in theory it should work for iOS 13+ as well
        let worker = BackgroundWorker(
            mode: .backgroundFetch,
            inputData: "",
            flutterPluginRegistrantCallback: SwiftWorkmanagerPlugin.flutterPluginRegistrantCallback
        )

        return worker.performBackgroundRequest(completionHandler)
    }

}
