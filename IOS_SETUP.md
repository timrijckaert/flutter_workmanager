# iOS Installation

## Prerequisites

This plugin is compatible with **Swift 4.2** and up. Make sure you are using **Xcode 10.3** or higher and have set your minimum deployment target to **iOS 10** or higher by defining a platform version in your podfile: `platform :ios, '10.0'`


## Enable BGTaskScheduler

> ⚠️ BGTaskScheduler is similar to Background Fetch described below and brings a similar set of constraints. Most notably, there are no guarantees when the background task will be run. Excerpt from the documentation:
> 
> Schedule a processing task request to ask that the system launch your app when conditions are favorable for battery life to handle deferrable, longer-running processing, such as syncing, database maintenance, or similar tasks. The system will attempt to fulfill this request to the best of its ability within the next two days as long as the user has used your app within the past week.
> 
> Workmanager BGTaskScheduler methods `registerOneOffTask`, `registerPeriodicTask`, and `registerProcessingTask` are only available on iOS 13+

![Screenshot of Background Fetch Capabilities tab in Xcode ](.art/ios_background_mode_background_processing.png)

This will add the **UIBackgroundModes** key to your project's `Info.plist`:

``` xml
<key>UIBackgroundModes</key>
<array>
	<string>processing</string>

	<!-- If you need periodic tasks in iOS 13+ you need to enable Background Fetch as well -->
	<string>fetch</string>
</array>
```

You **MUST** amend your `AppDelegate.swift` and `Info.plist` file to register your task ID.

- AppDelegate.swift
``` swift
import workmanager
```

``` swift
// In AppDelegate.application method
WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "task-identifier")

// Register a periodic task in iOS 13+
WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "be.tramckrijte.workmanagerExample.iOSBackgroundAppRefresh", frequency: NSNumber(value: 20 * 60))
```

- Info.plist
``` xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
	<string>task-identifier</string>

	<!-- Register a periodic task in iOS 13+ -->
	<string>be.tramckrijte.workmanagerExample.iOSBackgroundAppRefresh</string>
</array>
```
> ⚠️ On iOS 13+, adding a `BGTaskSchedulerPermittedIdentifiers` key to the Info.plist for new `BGTaskScheduler` API disables the `performFetchWithCompletionHandler` and `setMinimumBackgroundFetchInterval`
methods, which means you cannot use both old Background Fetch and new `registerPeriodicTask` at the same time, you have to choose one based on your minimum iOS target version. 
For details see [Apple Docs](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app)

And will set the correct *SystemCapabilities* for your target in the `project.pbxproj` file:

```
SystemCapabilities = {
	com.apple.BackgroundModes = {
		enabled = 1;
	};
};
```

## Testing BGTaskScheduler

Follow the instructions on https://developer.apple.com/documentation/backgroundtasks/starting_and_terminating_tasks_during_development.

The exact command to trigger the WorkManager default BG Task is:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"workmanager.background.task"]
```

## Enabling Background Fetch

> ⚠️ Background fetch is one supported way to do background work on iOS with work manager. Note that this API is deprecated starting iOS 13, however it still works on iOS 13+ as of writing this article

> ⚠️ On iOS 13+, adding a `BGTaskSchedulerPermittedIdentifiers` key to the Info.plist for new `BGTaskScheduler` API disables the `performFetchWithCompletionHandler` and `setMinimumBackgroundFetchInterval`
methods, which means you cannot use both old Background Fetch and new `registerPeriodicTask` at the same time, you have to choose one based on your minimum iOS target version. 
For details see [Apple Docs](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app)

Background fetching is very different compared to Android's Background Jobs.  
In order for your app to support Background Fetch, you have to add the *Background Modes* capability in Xcode for your app's Target and check *Background fetch*:

![Screenshot of Background Fetch Capabilities tab in Xcode ](.art/ios_background_mode_fetch.png)

This will add the **UIBackgroundModes** key to your project's `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
	<string>fetch</string>
</array>
```

And will set the correct *SystemCapabilities* for your target in the `project.pbxproj` file:

```
SystemCapabilities = {
	com.apple.BackgroundModes = {
		enabled = 1;
	};
};
```

Inside your app's delegate `didFinishLaunchingWithOptions`, set your desired **minimumBackgroundFetchInterval** :


```Swift
class AppDelegate:UIResponder,UIApplicationDelegate{
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplicationLaunchOptionsKey:Any]?)->Bool{
        // Other intialization code…
        UIApplication.shared.setMinimumBackgroundFetchInterval(TimeInterval(60*15))

        return true
    }
}
```

This ensures that the task is ran at most every 15 minutes.

> 📝 Note: this is a **minimum** time interval, there's no guarantee on how often this will be called.



## Testing Background Fetch

You can wait for iOS to trigger the `performFetchWithCompletionHandler` but you as a developer have no control over *when* and how often iOS will allow your app to fetch data in the background:

>  When a good opportunity arises, the system wakes or launches your app into the background and calls the app delegate’s `application:performFetchWithCompletionHandler:` method. [...] **Apps that download small amounts of content quickly, and accurately reflect when they had content available to download, are more likely to receive execution time in the future** than apps that take a long time to download their content or that claim content was available but then do not download anything.



> 📝 Note: also see relevant discussion in issue #23

But in order to test your implementation during development, you can *simulate* a `background fetch` in Xcode; go to `Debug` → `Simulate Background Fetch`

![Screenshot of iOS Xcode's Debug menu](.art/ios_xcode_debug_menu.png)

When the WorkManager plugin receives a `background fetch` event,  it will start a new **Dart isolate**, using the entrypoint provided by the `initialize` method.

Here is an example of a Flutter entrypoint called `callbackDispatcher`:

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    switch (task) {
      case Workmanager.iOSBackgroundTask:
        stderr.writeln("The iOS background fetch was triggered");
        break;
    }
    bool success = true;
    return Future.value(success);
  });
}
```

If you then simulate a background fetch in Xcode, you should see  `"The iOS background fetch was triggered"` log in Xcode's Console:

![Screenshot of Xcode console's output](.art/ios_xcode_console.png)

### Troubleshooting

If the *Simulate Background Fetch* is greyed out in the *Debug* menu, that means Xcode's debugger is not attached to the current process. Attaching is done for you *automatically* when you run directly from Xcode. 

If you launched your app using the Flutter command line tools or another IDE like IntelliJ IDEA, you will need to attach to the running *Runner* process using the Debug menu in Xcode:

![Screenshot of Xcode's attach to process menu item](.art/ios_xcode_attach_to_process.jpg)

> 📝  Note that this feature of Xcode is not 100% reliable. For best results, run directly from Xcode





## Registered plugins
Since the provided Flutter entry point is ran in a dedicated **Dart isolate**, the Flutter plugins which may
have been registered AppDelegate's `didFinishLaunchingWithOptions` (or somewhere else) are unavailable,
since they were registered on a different registry.

In order to know when the Dart isolate has started, the plugin user may make use of the
WorkmanagerPlugin's `setPluginRegistrantCallback` function. For example :

```Swift
class AppDelegate: FlutterAppDelegate {
    /// Registers all pubspec-referenced Flutter plugins in the given registry.  
    static func registerPlugins(with registry: FlutterPluginRegistry) {
            GeneratedPluginRegistrant.register(with: registry)
       }
    
    override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // ... Initialization code
        
        AppDelegate.registerPlugins(with: self) // Register the app's plugins in the context of a normal run
        
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in  
            // The following code will be called upon WorkmanagerPlugin's registration.
            // Note : all of the app's plugins may not be required in this context ;
            // instead of using GeneratedPluginRegistrant.register(with: registry),
            // you may want to register only specific plugins.
            AppDelegate.registerPlugins(with: registry)
        }
    }
}
```



## Useful links

- [Updating Your App with Background App Refresh](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/updating_your_app_with_background_app_refresh) - Apple Documentation

- [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649518-usernotificationcenter) documentation
