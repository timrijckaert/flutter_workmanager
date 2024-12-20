# Flutter Workmanager

[![pub package](https://img.shields.io/pub/v/workmanager.svg)](https://pub.dartlang.org/packages/workmanager)
[![Build status](https://img.shields.io/cirrus/github/vrtdev/flutter_workmanager/master)](https://cirrus-ci.com/github/vrtdev/flutter_workmanager/)
=======

Flutter WorkManager is a wrapper around [Android's WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager), [iOS' performFetchWithCompletionHandler](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623125-application) and [iOS BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), effectively enabling headless execution of Dart code in the background.

For iOS users, please watch this video  on a general introduction to background processing: https://developer.apple.com/videos/play/wwdc2019/707. All of the constraints discussed in the video also apply to this plugin.

This is especially useful to run periodic tasks, such as fetching remote data on a regular basis.

> This plugin was featured in this [Medium blogpost](https://medium.com/vrt-digital-studio/flutter-workmanager-81e0cfbd6f6e)

# Platform Setup

In order for background work to be scheduled correctly you should follow the Android and iOS setup first.

- [Android Setup](https://github.com/fluttercommunity/flutter_workmanager/blob/master/ANDROID_SETUP.md)
- [iOS Setup](https://github.com/fluttercommunity/flutter_workmanager/blob/master/IOS_SETUP.md)

# How to use the package?

See sample folder for a complete working example.  
Before registering any task, the WorkManager plugin must be initialized.

```dart
@pragma('vm:entry-point') // Mandatory if the App is obfuscated or using Flutter 3.1+
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    print("Native called background task: $task"); //simpleTask will be emitted here.
    return Future.value(true);
  });
}

void main() {
  Workmanager().initialize(
    callbackDispatcher, // The top level function, aka callbackDispatcher
    isInDebugMode: true // If enabled it will post a notification whenever the task is running. Handy for debugging tasks
  );
  Workmanager().registerOneOffTask("task-identifier", "simpleTask");
  runApp(MyApp());
}
```

> The `callbackDispatcher` needs to be either a static function or a top level function to be accessible as a Flutter entry point.

The workmanager runs on a separate isolate from the main flutter isolate. Ensure to initialize all dependencies inside the `Workmanager().executeTask`.

##### Debugging tips

Wrap the code inside your `Workmanager().executeTask` in a `try and catch` in order to catch any exceptions thrown.

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {

    int? totalExecutions;
    final _sharedPreference = await SharedPreferences.getInstance(); //Initialize dependency

    try { //add code execution
      totalExecutions = _sharedPreference.getInt("totalExecutions");
      _sharedPreference.setInt("totalExecutions", totalExecutions == null ? 1 : totalExecutions+1);
    } catch(err) {
      Logger().e(err.toString()); // Logger flutter package, prints error on the debug console
      throw Exception(err);
    }

    return Future.value(true);
  });
}
```

Android tasks are identified using their `taskName`.
iOS tasks are identified using their `taskIdentifier`.

However, there is an exception for iOS background fetch: `Workmanager.iOSBackgroundTask`, a constant for iOS background fetch task.

---

# Work Result

The `Workmanager().executeTask(...` block supports 3 possible outcomes:

1. `Future.value(true)`: The task is successful.
2. `Future.value(false)`: The task did not complete successfully and needs to be retried. On Android, the retry is done automatically. On iOS (when using BGTaskScheduler), the retry needs to be scheduled manually.
3. `Future.error(...)`: The task failed.

On Android, the `BackoffPolicy` will configure how `WorkManager` is going to retry the task.

Refer to the example app for a successful, retrying and a failed task.

# iOS specific setup and note

Initialize Workmanager only once.
Background app refresh can only be tested on a real device, it cannot be tested on a simulator.

### Migrate to 0.6.x
Version 0.6.x of this plugin has some breaking changes for iOS:
- Workmanager.registerOneOffTask was previously using iOS **BGProcessingTask**, now it will be an immediate run task which will continue in the background if user leaves the App. Since the previous solution meant the one off task will only run if the device is idle and as often experienced only when device is charging, in practice it means somewhere at night, or not at all during that day, because **BGProcessingTask** is meant for long running tasks. The new solution makes it more in line with Android except it does not support **initialDelay**
- If you need the old behavior you can use the new iOS only method `Workmanager.registerProcessingTask`:
  1. Replace `Workmanager().registerOneOffTask` with `Workmanager().registerProcessingTask` in your App
  1. Replace `WorkmanagerPlugin.registerTask` with `WorkmanagerPlugin.registerBGProcessingTask` in `AppDelegate.swift`
- Workmanager.registerOneOffTask does not support **initialDelay**
- Workmanager.registerOneOffTask now supports **inputData** which was always returning null in the previous solution
- Workmanager.registerOneOffTask now does NOT require `WorkmanagerPlugin.registerTask` call in `AppDelegate.swift` hence remove the call

### One off tasks
iOS supports **One off tasks** only on iOS 13+ with a few basic constraints:

`registerOneOffTask` starts immediately. It might run for only 30 seconds due to iOS restrictions.

```dart
Workmanager().registerOneOffTask(
  "task-identifier",
  simpleTaskKey, // Ignored on iOS
  initialDelay: Duration(minutes: 30), // Ignored on iOS
  inputData: ... // fully supported
);
```

### Periodic tasks
iOS supports two types of **Periodic tasks**:
- On iOS 12 and lower you can use deprecated Background Fetch API, see [iOS Setup](./IOS_SETUP.md), even though the API is
deprecated by iOS it still works on iOS 13+ as of writing this article

- `registerPeriodicTask` is only supported on iOS 13+, it might run for only 30 seconds due to iOS restrictions, but doesn't start immediately, rather iOS will schedule it as per user's App usage pattern.

> ⚠️ On iOS 13+, adding a `BGTaskSchedulerPermittedIdentifiers` key to the Info.plist for new `BGTaskScheduler` API disables the `performFetchWithCompletionHandler` and `setMinimumBackgroundFetchInterval`
methods, which means you cannot use both old Background Fetch and new `registerPeriodicTask` at the same time, you have to choose one based on your minimum iOS target version. 
For details see [Apple Docs](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app)

To use `registerPeriodicTask` first register the task in `Info.plist` and `AppDelegate.swift` [iOS Setup](./IOS_SETUP.md). Unlike Android, for iOS you have to set the frequency in `AppDelegate.swift`. The frequency is not guaranteed rather iOS will schedule it as per user's App usage pattern, iOS might take a few days to learn usage pattern. In reality frequency just means do not repeat the task before x seconds/minutes. If frequency is not provided it will default to 15 minutes.

```objc
// Register a periodic task with 20 minutes frequency. The frequency is in seconds.
WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "be.tramckrijte.workmanagerExample.iOSBackgroundAppRefresh", frequency: NSNumber(value: 20 * 60))
```

Then schedule the task from your App
```dart
const iOSBackgroundAppRefresh = "be.tramckrijte.workmanagerExample.iOSBackgroundAppRefresh";
Workmanager().registerPeriodicTask(
  iOSBackgroundAppRefresh,
  iOSBackgroundAppRefresh,
  initialDelay: Duration(seconds: 10),
  frequency: Duration(hours: 1), // Ignored on iOS, rather set in AppDelegate.swift
  inputData: ... // Not supported
);
```

For more information see [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)

### Processing tasks
iOS supports **Processing tasks** only on iOS 13+ which can run for more than 30 seconds.

`registerProcessingTask` is a long running one off background task, currently only for iOS. It can be run for more than 30 seconds but doesn't start immediately, rather iOS might schedule it when device is idle and charging.
Processing tasks are for long processes like data processing and app maintenance. Processing tasks can run for minutes, but the system can interrupt these.
iOS might terminate any running background processing tasks when the user starts using the device.
For more information see [BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)

```dart
const iOSBackgroundProcessingTask = "be.tramckrijte.workmanagerExample.iOSBackgroundProcessingTask";
Workmanager().registerProcessingTask(
  iOSBackgroundProcessingTask,
  iOSBackgroundProcessingTask,
  initialDelay: Duration(minutes: 2),
  constraints: Constraints(
    // Connected or metered mark the task as requiring internet
    networkType: NetworkType.connected,
    // Require external power
    requiresCharging: true,
  ),
);
```

### Background App Refresh permission

On iOS user can disable `Background App Refresh` permission anytime, hence background tasks can only run if user has granted the permission.

Use `permision_handler` to check for the permission:

``` dart
final status = await Permission.backgroundRefresh.status;
if (status != PermissionStatus.granted) {
  _showNoPermission(context, status);
  return;
}
```

For more information see the [BGTaskScheduler documentation](https://developer.apple.com/documentation/backgroundtasks).

### Print scheduled tasks
On iOS you can print scheduled tasks using `Workmanager.printScheduledTasks`

It prints task details to console. To be used during development/debugging.
Currently only supported on iOS and only on iOS 13+.

```dart
if (Platform.isIOS) {
  Workmanager().printScheduledTasks();
  // Prints: [BGTaskScheduler] Task Identifier: iOSBackgroundAppRefresh earliestBeginDate: 2023.10.10 PM 11:10:12
  // Or:     [BGTaskScheduler] There are no scheduled tasks
}
```


# Customisation (Android)

Not every `Android WorkManager` feature is ported.

Two kinds of background tasks can be registered :

- **One off task** : runs only once
- **Periodic tasks** : runs indefinitely on a regular basis

```dart
// One off task registration
Workmanager().registerOneOffTask(
    "oneoff-task-identifier", 
    "simpleTask"
);

// Periodic task registration
Workmanager().registerPeriodicTask(
    "periodic-task-identifier", 
    "simplePeriodicTask", 
    // When no frequency is provided the default 15 minutes is set.
    // Minimum frequency is 15 min. Android will automatically change your frequency to 15 min if you have configured a lower frequency.
    frequency: Duration(hours: 1),
)
```

Each task must have an **unique name**;  
This allows cancellation of a started task.  
The second parameter is the `String` that will be sent to your `callbackDispatcher` function, indicating the task's _type_.

## Tagging

You can set the optional `tag` property.  
Handy for cancellation by `tag`.  
This is different from the unique name in that you can group multiple tasks under one tag.

```dart
Workmanager().registerOneOffTask("1", "simpleTask", tag: "tag");
```

## Existing Work Policy

Indicates the desired behaviour when the same task is scheduled more than once.  
The default is `KEEP`

```dart
Workmanager().registerOneOffTask("1", "simpleTask", existingWorkPolicy: ExistingWorkPolicy.append);
```

## Initial Delay

Indicates how along a task should waitbefore its first run.

```dart
Workmanager().registerOneOffTask("1", "simpleTask", initialDelay: Duration(seconds: 10));
```

## Constraints

> Constraints are mapped at best effort to each platform. Android's WorkManager supports most of the specific constraints, whereas iOS tasks are limited.

- NetworkType
  Constrains the type of network required for your work to run. For example, Connected. 
  The `NetworkType` lists various network conditions. `.connected` & `.metered` will be mapped to [`requiresNetworkConnectivity`](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtaskrequest/3142242-requiresnetworkconnectivity) on iOS.
- RequiresBatteryNotLow (Android only)
  When set to true, your work will not run if the device is in low battery mode.
  **Enabling the battery saving mode on the android device prevents the job from running**
- RequiresCharging
  When set to true, your work will only run when the device is charging.
- RequiresDeviceIdle (Android only)
  When set to true, this requires the user’s device to be idle before the work will run. This can be useful for running batched operations that might otherwise have a - negative performance impact on other apps running actively on the user’s device.
- RequiresStorageNotLow (Android only)
  When set to true, your work will not run if the user’s storage space on the device is too low.

```dart
Workmanager().registerOneOffTask(
    "1",
    "simpleTask",
    constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: true,
        requiresDeviceIdle: true,
        requiresStorageNotLow: true
    )
);
```

### InputData

Add some input data for your task. Valid value types are: `int`, `bool`, `double`, `String` and their `list`

```dart
 Workmanager().registerOneOffTask(
    "1",
    "simpleTask",
    inputData: {
    'int': 1,
    'bool': true,
    'double': 1.0,
    'string': 'string',
    'array': [1, 2, 3],
    },
);
```

## BackoffPolicy

Indicates the waiting strategy upon task failure.  
The default is `BackoffPolicy.exponential`.  
You can also specify the delay.

```dart
Workmanager().registerOneOffTask("1", "simpleTask", backoffPolicy: BackoffPolicy.exponential, backoffPolicyDelay: Duration(seconds: 10));
```

## Cancellation

A task can be cancelled in different ways :

### By Tag

Cancels the task that was previously registered using this **Tag**, if any.

```dart
Workmanager().cancelByTag("tag");
```

### By Unique Name

```dart
Workmanager().cancelByUniqueName("<MyTask>");
```

### All

```dart
Workmanager().cancelAll();
```


# Building project

Project was migrated to [Melos](https://pub.dev/packages/melos) so build steps has changed.

1. Install melos

```
dart pub global activate melos
```

2. In project root bootstrap

```
melos bootstrap
```

3. Get packages

```
melos run get
```

Now you should be able to run example project

```
cd example
flutter run
```