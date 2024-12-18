import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'options.dart';

/// Function that executes your background work.
/// You should return whether the task ran successfully or not.
///
/// [taskName] Returns the value you provided when registering the task.
/// iOS will pass [Workmanager.iOSBackgroundTask] (for background-fetch) or
/// custom task IDs for BGTaskScheduler based tasks.
///
/// The behavior for retries is different on each platform:
/// - Android: return `false` from the this method will reschedule the work
///   based on the policy given in [Workmanager.registerOneOffTask], for example
/// - iOS: The return value is ignored, but if work has failed, you can schedule
///   another attempt using [Workmanager.registerOneOffTask]. This depends on
///   BGTaskScheduler being set up correctly. Please follow the README for
///   instructions.
typedef BackgroundTaskHandler = Future<bool> Function(
    String taskName, Map<String, dynamic>? inputData);

/// Make sure you followed the platform setup steps first before trying to register any task.
///
/// Android:
/// - Custom Application class
///
/// iOS:
/// - Enabled the Background Fetch API
///
/// Inside your Dart code
///
/// Initialize the plugin first
///
/// ```
/// @pragma('vm:entry-point')
/// void callbackDispatcher() {
///   Workmanager().executeTask((taskName, inputData) {
///     switch(taskName) {
///       case "":
///         print("Replace this print statement with your code that should be executed in the background here");
///         break;
///     }
///     return Future.value(true);
///   });
/// }
///
/// void main() {
///   Workmanager().initialize(callbackDispatcher);
/// }
/// ```
///
/// ## You can schedule a specific iOS task using:
/// - `Workmanager().registerOneOffTask()`
/// Please read the documentation on limitations for background processing on iOS.
///
///
/// iOS periodic background fetch task is automatically scheduled if you setup the plugin properly for Background Fetch.
///
/// If you are targeting iOS 13+, you can use `Workmanager().registerPeriodicTask()`
///
/// Note: On iOS 13+, adding a BGTaskSchedulerPermittedIdentifiers key to the Info.plist
/// disables the performFetchWithCompletionHandler and setMinimumBackgroundFetchInterval
/// methods, which means you cannot use both old Background Fetch and new registerPeriodicTask
/// at the same time, you have to choose one based on your minimum iOS target version.
/// For details see [Using background tasks to update your app](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app/)
///
///
/// ## You can schedule Android tasks using:
/// - `Workmanager().registerOneOffTask()` or `Workmanager().registerPeriodicTask()`
class Workmanager {
  factory Workmanager() => _instance;

  Workmanager._internal(MethodChannel backgroundChannel,
      MethodChannel foregroundChannel)
      : _backgroundChannel = backgroundChannel,
        _foregroundChannel = foregroundChannel;

  static final Workmanager _instance = Workmanager._internal(
      const MethodChannel(
          "be.tramckrijte.workmanager/background_channel_work_manager"),
      const MethodChannel(
          "be.tramckrijte.workmanager/foreground_channel_work_manager"));

  /// Use this constant inside your callbackDispatcher to identify when an iOS Background Fetch occurred.
  ///
  /// ```
  /// @pragma('vm:entry-point')
  /// void callbackDispatcher() {
  ///   Workmanager().executeTask((taskName, inputData) {
  ///      switch (taskName) {
  ///        case Workmanager.iOSBackgroundTask:
  ///          stderr.writeln("The iOS background fetch was triggered");
  ///          break;
  ///      }
  ///
  ///      return Future.value(true);
  ///  });
  /// }
  /// ```
  static const String iOSBackgroundTask = "iOSPerformFetch";

  /// Use this constant inside your callbackDispatcher to identify when an iOS Background Processing via BGTaskScheduler occurred.
  ///
  /// ```
  /// @pragma('vm:entry-point')
  /// void callbackDispatcher() {
  ///   Workmanager().executeTask((taskName, inputData) {
  ///      switch (taskName) {
  ///        case Workmanager.iOSBackgroundProcessingTask:
  ///          stderr.writeln("A iOS BG processing task was initiated.");
  ///          break;
  ///      }
  ///
  ///      return Future.value(true);
  ///  });
  /// }
  /// ```
  @Deprecated('Use custom iOS task names. This property will be removed.')
  static const String iOSBackgroundProcessingTask =
      "workmanager.background.task";

  static bool _isInDebugMode = false;

  MethodChannel _backgroundChannel = const MethodChannel(
      "be.tramckrijte.workmanager/background_channel_work_manager");
  MethodChannel _foregroundChannel = const MethodChannel(
      "be.tramckrijte.workmanager/foreground_channel_work_manager");

  /// A helper function so you only need to implement a [BackgroundTaskHandler]
  void executeTask(final BackgroundTaskHandler backgroundTask) {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    _backgroundChannel.setMethodCallHandler((call) async {
      final inputData = call.arguments["be.tramckrijte.workmanager.INPUT_DATA"];
      return backgroundTask(
        call.arguments["be.tramckrijte.workmanager.DART_TASK"],
        inputData == null ? null : jsonDecode(inputData),
      );
    });
    _backgroundChannel.invokeMethod("backgroundChannelInitialized");
  }

  /// This call is required if you wish to use the [WorkManager] plugin.
  /// [callbackDispatcher] is a top level function which will be invoked by
  /// Android or iOS. See the discussion on [BackgroundTaskHandler] for details.
  /// [isInDebugMode] true will post debug notifications with information about when a task should have run
  Future<void> initialize(final Function callbackDispatcher, {
    final bool isInDebugMode = false,
  }) async {
    Workmanager._isInDebugMode = isInDebugMode;
    final callback = PluginUtilities.getCallbackHandle(callbackDispatcher);
    assert(callback != null,
    "The callbackDispatcher needs to be either a static function or a top level function to be accessible as a Flutter entry point.");
    if (callback != null) {
      final int handle = callback.toRawHandle();
      await _foregroundChannel.invokeMethod<void>(
        'initialize',
        JsonMapperHelper.toInitializeMethodArgument(
          isInDebugMode: _isInDebugMode,
          callbackHandle: handle,
        ),
      );
    }
  }

  /// Schedule a one off task.
  ///
  /// On iOS it should start immediately, iOS might terminate the task if it takes
  /// more than 30 seconds.
  ///
  /// A [uniqueName] is required so only one task can be registered.
  /// The [taskName] is the value that will be returned in the [BackgroundTaskHandler]
  /// The [inputData] is the input data for task. Valid value types are: int, bool, double, String and their list
  Future<void> registerOneOffTask(

      /// Only supported on Android.
      final String uniqueName,

      /// Only supported on Android.
      final String taskName, {
        /// Only supported on Android.
        final String? tag,

        /// Only supported on Android.
        final ExistingWorkPolicy? existingWorkPolicy,

        /// Configures a initial delay.
        ///
        /// The delay configured here is not guaranteed. The underlying system may
        /// decide to schedule the ask a lot later.
        final Duration initialDelay = Duration.zero,

        /// Fully supported on Android, but only partially supported on iOS.
        /// See [Constraints] for details.
        final Constraints? constraints,
        final BackoffPolicy? backoffPolicy,
        final Duration backoffPolicyDelay = Duration.zero,
        final OutOfQuotaPolicy? outOfQuotaPolicy,
        final Map<String, dynamic>? inputData,
      }) async =>
      await _foregroundChannel.invokeMethod(
        "registerOneOffTask",
        JsonMapperHelper.toRegisterMethodArgument(
          isInDebugMode: _isInDebugMode,
          uniqueName: uniqueName,
          taskName: taskName,
          tag: tag,
          existingWorkPolicy: existingWorkPolicy,
          initialDelay: initialDelay,
          constraints: constraints,
          backoffPolicy: backoffPolicy,
          backoffPolicyDelay: backoffPolicyDelay,
          outOfQuotaPolicy: outOfQuotaPolicy,
          inputData: inputData,
        ),
      );

  /// Schedules a periodic task that will run every provided [frequency].
  ///
  /// On iOS it is not guaranteed when or how often it will run, iOS will schedule
  /// it as per user's App usage pattern, iOS might terminate the task or throttle
  /// it's frequency if it takes more than 30 seconds.
  ///
  /// A [uniqueName] is required so only one task can be registered.
  /// The [taskName] is the value that will be returned in the [BackgroundTaskHandler], ignored on iOS where you should use [uniqueName].
  /// a [frequency] is not required and will be defaulted to 15 minutes if not provided.
  /// a [frequency] has a minimum of 15 min. Android will automatically change your frequency to 15 min if you have configured a lower frequency.
  /// the [flexInterval] If the nature of the work is time-sensitive, you can configure the PeriodicWorkRequest to run in a flexible period at each interval.
  /// https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work?hl=pt-br#flexible_run_intervals
  /// The [inputData] is the input data for task. Valid value types are: int, bool, double, String and their list

  /// Unlike Android, you cannot set [frequency] for iOS here rather you have to set in `AppDelegate.swift` while registering the task.
  /// The [inputData] is the input data for task. Valid value types are: int, bool, double, String and their list. It is not supported on iOS.
  ///
  /// For iOS see Apple docs:
  /// [iOS 13+ Using background tasks to update your app](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app/)
  ///
  /// [iOS 13+ BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask/)
  Future<void> registerPeriodicTask(final String uniqueName,
      final String taskName, {
        final Duration? frequency,
        final Duration? flexInterval,
        final String? tag,
        final ExistingWorkPolicy? existingWorkPolicy,
        final Duration initialDelay = Duration.zero,
        final Constraints? constraints,
        final BackoffPolicy? backoffPolicy,
        final Duration backoffPolicyDelay = Duration.zero,
        final OutOfQuotaPolicy? outOfQuotaPolicy,
        final Map<String, dynamic>? inputData,
      }) async =>
      await _foregroundChannel.invokeMethod(
        "registerPeriodicTask",
        JsonMapperHelper.toRegisterMethodArgument(
          isInDebugMode: _isInDebugMode,
          uniqueName: uniqueName,
          taskName: taskName,
          frequency: frequency,
          flexInterval: flexInterval,
          tag: tag,
          existingWorkPolicy: existingWorkPolicy,
          initialDelay: initialDelay,
          constraints: constraints,
          backoffPolicy: backoffPolicy,
          backoffPolicyDelay: backoffPolicyDelay,
          outOfQuotaPolicy: outOfQuotaPolicy,
          inputData: inputData,
        ),
      );

  /// Checks whether a period task is scheduled by its [uniqueName].
  ///
  /// Scheduled means the work state is either ENQUEUED or RUNNING
  ///
  /// Only available on Android.
  Future<bool> isScheduledByUniqueName(final String uniqueName) async {
    return await _foregroundChannel.invokeMethod(
      "isScheduledByUniqueName",
      {"uniqueName": uniqueName},
    );
  }

  /// Schedule a background long running task, currently only available on iOS.
  ///
  /// Processing tasks are for long processes like data processing and app maintenance.
  /// Processing tasks can run for minutes, but the system can interrupt these.
  /// Processing tasks run only when the device is idle. iOS might terminate any
  /// running background processing tasks when the user starts using the device.
  /// However background refresh tasks aren’t affected.
  ///
  /// For iOS see Apple docs:
  /// [iOS 13+ Using background tasks to update your app](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app/)
  ///
  /// [iOS 13+ BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask/)
  Future<void> registerProcessingTask(final String uniqueName,
      final String taskName, {
        final Duration initialDelay = Duration.zero,

        /// Only partially supported on iOS.
        /// See [Constraints] for details.
        final Constraints? constraints,
      }) async =>
      await _foregroundChannel.invokeMethod(
        "registerProcessingTask",
        JsonMapperHelper.toRegisterMethodArgument(
          isInDebugMode: _isInDebugMode,
          uniqueName: uniqueName,
          taskName: taskName,
          initialDelay: initialDelay,
          constraints: constraints,
        ),
      );

  /// Cancels a task by its [uniqueName]
  Future<void> cancelByUniqueName(final String uniqueName) async =>
      await _foregroundChannel.invokeMethod(
        "cancelTaskByUniqueName",
        {"uniqueName": uniqueName},
      );

  /// Cancels a task by its [tag]
  Future<void> cancelByTag(final String tag) async =>
      await _foregroundChannel.invokeMethod(
        "cancelTaskByTag",
        {"tag": tag},
      );

  /// Cancels all tasks
  Future<void> cancelAll() async =>
      await _foregroundChannel.invokeMethod("cancelAllTasks");

  /// Sets the foreground options for the task.
  Future<void> setForeground(SetForegroundOptions options) async =>
      await _backgroundChannel.invokeMethod("setForeground", options.toMap());

  /// Prints details of un-executed scheduled tasks to console. To be used during
  /// development/debugging.
  ///
  /// Currently only supported on iOS and only on iOS 13+.
  Future<void> printScheduledTasks() async =>
      await _foregroundChannel.invokeMethod("printScheduledTasks");
}

/// A helper object to convert the selected options to JSON format. Mainly for testability.
class JsonMapperHelper {
  @visibleForTesting
  static Map<String, Object?> toRegisterMethodArgument({
    final bool isInDebugMode = false,
    final String? uniqueName,
    final String? taskName,
    final Duration? frequency,
    final Duration? flexInterval,
    final String? tag,
    final ExistingWorkPolicy? existingWorkPolicy,
    final Duration? initialDelay,
    final Constraints? constraints,
    final BackoffPolicy? backoffPolicy,
    final Duration? backoffPolicyDelay,
    final OutOfQuotaPolicy? outOfQuotaPolicy,
    final Map<String, dynamic>? inputData,
  }) {
    if (inputData != null) {
      for (final entry in inputData.entries) {
        final key = entry.key;
        final value = entry.value;
        if (!(value is int ||
            value is bool ||
            value is double ||
            value is String ||
            value is List<int> ||
            value is List<bool> ||
            value is List<double> ||
            value is List<String>)) {
          throw Exception(
              "argument $key has wrong type. WorkManager supports only int, bool, double, String and their list");
        }
      }
    }

    assert(uniqueName != null);
    assert(taskName != null);
    return {
      "isInDebugMode": isInDebugMode,
      "uniqueName": uniqueName,
      "taskName": taskName,
      "tag": tag,
      "frequency": frequency?.inSeconds,
      "flexInterval": flexInterval?.inSeconds,
      "existingWorkPolicy": _enumToString(existingWorkPolicy),
      "initialDelaySeconds": initialDelay?.inSeconds,
      "networkType": _enumToString(constraints?.networkType),
      "requiresBatteryNotLow": constraints?.requiresBatteryNotLow,
      "requiresCharging": constraints?.requiresCharging,
      "requiresDeviceIdle": constraints?.requiresDeviceIdle,
      "requiresStorageNotLow": constraints?.requiresStorageNotLow,
      "backoffPolicyType": _enumToString(backoffPolicy),
      "backoffDelayInMilliseconds": backoffPolicyDelay?.inMilliseconds,
      "outOfQuotaPolicy": _enumToString(outOfQuotaPolicy),
      "inputData": inputData == null ? null : jsonEncode(inputData),
    };
  }

  @visibleForTesting
  static Map<String, Object?> toInitializeMethodArgument({
    required final bool isInDebugMode,
    required final int callbackHandle,
  }) {
    return {
      "isInDebugMode": isInDebugMode,
      "callbackHandle": callbackHandle,
    };
  }

  static String? _enumToString(final dynamic enumeration) =>
      enumeration
          ?.toString()
          .split('.')
          .last;
}

class SetForegroundOptions {
  final int foregroundServiceType;
  final int notificationId;

  final String notificationChannelId;
  final String notificationChannelName;
  final String notificationChannelDescription;
  final int notificationChannelImportance;

  final String notificationTitle;
  final String notificationDescription;

  SetForegroundOptions({required this.foregroundServiceType,
    required this.notificationId,
    required this.notificationChannelId,
    required this.notificationChannelName,
    required this.notificationChannelDescription,
    required this.notificationChannelImportance,
    required this.notificationTitle,
    required this.notificationDescription});

  Map<String, dynamic> toMap() {
    return {
      "foregroundServiceType": foregroundServiceType,
      "notificationId": notificationId,
      "notificationChannelId": notificationChannelId,
      "notificationChannelName": notificationChannelName,
      "notificationChannelDescription": notificationChannelDescription,
      "notificationChannelImportance": notificationChannelImportance,
      "notificationTitle": notificationTitle,
      "notificationDescription": notificationDescription,
    };
  }

  SetForegroundOptions copyWith({
    int? foregroundServiceType,
    int? notificationId,
    String? notificationChannelId,
    String? notificationChannelName,
    String? notificationChannelDescription,
    int? notificationChannelImportance,
    String? notificationTitle,
    String? notificationDescription,
  }) {
    return SetForegroundOptions(
      foregroundServiceType:
      foregroundServiceType ?? this.foregroundServiceType,
      notificationId: notificationId ?? this.notificationId,
      notificationChannelId:
      notificationChannelId ?? this.notificationChannelId,
      notificationChannelName:
      notificationChannelName ?? this.notificationChannelName,
      notificationChannelDescription:
      notificationChannelDescription ?? this.notificationChannelDescription,
      notificationChannelImportance:
      notificationChannelImportance ?? this.notificationChannelImportance,
      notificationTitle: notificationTitle ?? this.notificationTitle,
      notificationDescription:
      notificationDescription ?? this.notificationDescription,
    );
  }
}

class ForegroundServiceType {
  static const int dataSync = 1 << 0;
  static const int mediaPlayback = 1 << 1;
  static const int phoneCall = 1 << 2;
  static const int location = 1 << 3;
  static const int connectedDevice = 1 << 4;
  static const int mediaProjection = 1 << 5;
  static const int camera = 1 << 6;
  static const int microphone = 1 << 7;
  static const int health = 1 << 8;
  static const int remoteMessaging = 1 << 9;
  static const int systemExempted = 1 << 10;
  static const int shortService = 1 << 11;
  static const int fileManagement = 1 << 12;
  static const int specialUse = 1 << 30;
  static const int manifest = -1;
}

class NotificationImportance {
  static const int none = 0;
  static const int min = 1;
  static const int low = 2;
  static const int defaultImportance = 3;
  static const int high = 4;
  static const int max = 5;
}
