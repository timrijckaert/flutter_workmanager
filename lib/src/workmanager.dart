import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'options.dart';

const _noDuration = const Duration(seconds: 0);

/// Returns the value you provided when registering the task. iOS will always return [Workmanager.iOSBackgroundTask]
typedef BackgroundTask = Future<bool> Function(String echoValue);

/// Workmanager plugin
///
/// Make sure you followed the setup steps first before trying to register any task.
///
/// Initialize the plugin first
///
/// ```
/// void callbackDispatcher() {
///   Workmanager.executeTask((echoValue) {
///     print("Native echoed: $echoValue");
///     return Future.value(true);
///   });
/// }
///
/// Workmanager.initialize(
///     callbackDispatcher,
///     isInDebugMode: true
/// )
/// ```
class Workmanager {
  /// Use this constant inside your callbackDispatcher to identify when an iOS Background Fetch occurred.
  ///
  /// ```
  /// void callbackDispatcher() {
  ///  Workmanager.executeTask((task) async {
  ///      switch (task) {
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
  static bool _isInDebugMode = false;

  static const MethodChannel _backgroundChannel = const MethodChannel(
      "be.tramckrijte.workmanager/background_channel_work_manager");
  static const MethodChannel _foregroundChannel = const MethodChannel(
      "be.tramckrijte.workmanager/foreground_channel_work_manager");

  /// A helper function so you only need to implement a [BackgroundTask]
  static void executeTask(final BackgroundTask backgroundTask) {
    WidgetsFlutterBinding.ensureInitialized();
    _backgroundChannel
        .setMethodCallHandler((call) async => backgroundTask(call.arguments));
    _backgroundChannel.invokeMethod("backgroundChannelInitialized");
  }

  /// This call is required if you wish to use the [WorkManager] plugin.
  /// [callbackDispatcher] is a top level function which will be invoked by Android
  /// [isInDebugMode] true will post debug notifications with information about when a task should have run
  static Future<void> initialize(
    final Function callbackDispatcher, {
    final bool isInDebugMode = false,
  }) async {
    Workmanager._isInDebugMode = isInDebugMode;
    final callback = PluginUtilities.getCallbackHandle(callbackDispatcher);
    await _foregroundChannel.invokeMethod('initialize', callback.toRawHandle());
  }

  /// Schedule a one off task
  /// A [uniqueName] is required so only one task can be registered.
  /// The [valueToReturn] is the value that will be returned in the [BackgroundTask]
  static Future<void> registerOneOffTask(
    final String uniqueName,
    final String valueToReturn, {
    final String tag,
    final ExistingWorkPolicy existingWorkPolicy,
    final Duration initialDelay = _noDuration,
    final Constraints constraints,
    final BackoffPolicy backoffPolicy,
    final Duration backoffPolicyDelay = _noDuration,
  }) async =>
      await _foregroundChannel.invokeMethod(
        "registerOneOffTask",
        JsonMapperHelper.toJson(
          _isInDebugMode,
          uniqueName: uniqueName,
          echoValue: valueToReturn,
          tag: tag,
          existingWorkPolicy: existingWorkPolicy,
          initialDelay: initialDelay,
          constraints: constraints,
          backoffPolicy: backoffPolicy,
          backoffPolicyDelay: backoffPolicyDelay,
        ),
      );

  /// Schedules a periodic task that will run every provided [frequency].
  /// A [uniqueName] is required so only one task can be registered.
  /// The [echoValue] is the value that will be returned in the [BackgroundTask]
  /// a [frequency] is not required and will be defaulted to 15 minutes if not provided.
  static Future<void> registerPeriodicTask(
    final String uniqueName,
    final String echoValue, {
    final Duration frequency,
    final String tag,
    final ExistingWorkPolicy existingWorkPolicy,
    final Duration initialDelay = _noDuration,
    final Constraints constraints,
    final BackoffPolicy backoffPolicy,
    final Duration backoffPolicyDelay = _noDuration,
  }) async =>
      await _foregroundChannel.invokeMethod(
        "registerPeriodicTask",
        JsonMapperHelper.toJson(
          _isInDebugMode,
          uniqueName: uniqueName,
          echoValue: echoValue,
          frequency: frequency,
          tag: tag,
          existingWorkPolicy: existingWorkPolicy,
          initialDelay: initialDelay,
          constraints: constraints,
          backoffPolicy: backoffPolicy,
          backoffPolicyDelay: backoffPolicyDelay,
        ),
      );

  /// Cancels a task by its [uniqueName]
  static Future<void> cancelByUniqueName(final String uniqueName) async =>
      await _foregroundChannel
          .invokeMethod("cancelTaskByUniqueName", {"uniqueName": uniqueName});

  /// Cancels a task by its [tag]
  static Future<void> cancelByTag(final String tag) async =>
      await _foregroundChannel.invokeMethod("cancelTaskByTag", {"tag": tag});

  /// Cancels all tasks
  static Future<void> cancelAll() async =>
      await _foregroundChannel.invokeMethod("cancelAll");
}

/// A helper object to convert the selected options to JSON format. Mainly for testability.
class JsonMapperHelper {
  static Map<String, Object> toJson(
    final bool _isInDebugMode, {
    final String uniqueName,
    final String echoValue,
    final Duration frequency,
    final String tag,
    final ExistingWorkPolicy existingWorkPolicy,
    final Duration initialDelay,
    final Constraints constraints,
    final BackoffPolicy backoffPolicy,
    final Duration backoffPolicyDelay,
  }) {
    assert(uniqueName != null);
    assert(echoValue != null);
    return {
      "isInDebugMode": _isInDebugMode,
      "uniqueName": uniqueName,
      "echoValue": echoValue,
      "tag": tag,
      "frequency": frequency?.inSeconds,
      "existingWorkPolicy": _enumToStringToKotlinString(existingWorkPolicy),
      "initialDelaySeconds": initialDelay.inSeconds,
      "networkType": _enumToStringToKotlinString(constraints?.networkType),
      "requiresBatteryNotLow": constraints?.requiresBatteryNotLow,
      "requiresCharging": constraints?.requiresCharging,
      "requiresDeviceIdle": constraints?.requiresDeviceIdle,
      "requiresStorageNotLow": constraints?.requiresStorageNotLow,
      "backoffPolicyType": _enumToStringToKotlinString(backoffPolicy),
      "backoffDelayInMilliseconds": backoffPolicyDelay.inMilliseconds,
    };
  }

  static String _enumToStringToKotlinString(final dynamic enumeration) =>
      enumeration?.toString()?.split('.')?.last;
}
