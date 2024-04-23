import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

void main() => runApp(MaterialApp(home: MyApp()));

const simpleTaskKey = "be.tramckrijte.workmanagerExample.simpleTask";
const rescheduledTaskKey = "be.tramckrijte.workmanagerExample.rescheduledTask";
const failedTaskKey = "be.tramckrijte.workmanagerExample.failedTask";
const simpleDelayedTask = "be.tramckrijte.workmanagerExample.simpleDelayedTask";
const simplePeriodicTask =
    "be.tramckrijte.workmanagerExample.simplePeriodicTask";
const simplePeriodic1HourTask =
    "be.tramckrijte.workmanagerExample.simplePeriodic1HourTask";
const iOSBackgroundAppRefresh =
    "be.tramckrijte.workmanagerExample.iOSBackgroundAppRefresh";
const iOSBackgroundProcessingTask =
    "be.tramckrijte.workmanagerExample.iOSBackgroundProcessingTask";

final List<String> allTasks = [
  simpleTaskKey,
  rescheduledTaskKey,
  failedTaskKey,
  simpleDelayedTask,
  simplePeriodicTask,
  simplePeriodic1HourTask,
  iOSBackgroundAppRefresh,
  iOSBackgroundProcessingTask,
];

// Pragma is mandatory if the App is obfuscated or using Flutter 3.1+
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    print("$task started. inputData = $inputData");
    await prefs.setString(task, 'Last ran at: ${DateTime.now().toString()}');

    switch (task) {
      case simpleTaskKey:
        await prefs.setBool("test", true);
        print("Bool from prefs: ${prefs.getBool("test")}");
        break;
      case rescheduledTaskKey:
        final key = inputData!['key']!;
        if (prefs.containsKey('unique-$key')) {
          print('has been running before, task is successful');
          return true;
        } else {
          await prefs.setBool('unique-$key', true);
          print('reschedule task');
          return false;
        }
      case failedTaskKey:
        print('failed task');
        return Future.error('failed');
      case simpleDelayedTask:
        print("$simpleDelayedTask was executed");
        break;
      case simplePeriodicTask:
        print("$simplePeriodicTask was executed");
        break;
      case simplePeriodic1HourTask:
        print("$simplePeriodic1HourTask was executed");
        break;
      case iOSBackgroundAppRefresh:
        // To test, follow the instructions on https://developer.apple.com/documentation/backgroundtasks/starting_and_terminating_tasks_during_development
        // and https://github.com/fluttercommunity/flutter_workmanager/blob/main/IOS_SETUP.md
        Directory? tempDir = await getTemporaryDirectory();
        String? tempPath = tempDir.path;
        print(
            "You can access other plugins in the background, for example Directory.getTemporaryDirectory(): $tempPath");
        break;
      case iOSBackgroundProcessingTask:
        // To test, follow the instructions on https://developer.apple.com/documentation/backgroundtasks/starting_and_terminating_tasks_during_development
        // and https://github.com/fluttercommunity/flutter_workmanager/blob/main/IOS_SETUP.md
        // Processing tasks are started by iOS only when phone is idle, hence
        // you need to manually trigger by following the docs and putting the App to background
        await Future<void>.delayed(Duration(seconds: 40));
        print("$task finished");
        break;
      default:
        return Future.value(false);
    }

    return Future.value(true);
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool workmanagerInitialized = false;
  String _prefsString = "empty";

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text("Flutter WorkManager Example"),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  "Plugin initialization",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                ElevatedButton(
                  child: Text("Start the Flutter background service"),
                  onPressed: () async {
                    if (Platform.isIOS) {
                      final status = await Permission.backgroundRefresh.status;
                      if (status != PermissionStatus.granted) {
                        _showNoPermission(context, status);
                        return;
                      }
                    }
                    if (!workmanagerInitialized) {
                      Workmanager().initialize(
                        callbackDispatcher,
                      );
                      setState(() => workmanagerInitialized = true);
                    }
                  },
                ),
                SizedBox(height: 8),
                Text(
                  "Register task",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

                //This task runs once.
                //Most likely this will trigger immediately
                ElevatedButton(
                  child: Text("Register OneOff Task"),
                  onPressed: () {
                    Workmanager().registerOneOffTask(
                      simpleTaskKey,
                      simpleTaskKey,
                      inputData: <String, dynamic>{
                        'int': 1,
                        'bool': true,
                        'double': 1.0,
                        'string': 'string',
                        'array': [1, 2, 3],
                      },
                    );
                  },
                ),
                ElevatedButton(
                  child: Text("Register rescheduled Task"),
                  onPressed: () {
                    Workmanager().registerOneOffTask(
                      rescheduledTaskKey,
                      rescheduledTaskKey,
                      inputData: <String, dynamic>{
                        'key': Random().nextInt(64000),
                      },
                    );
                  },
                ),
                ElevatedButton(
                  child: Text("Register failed Task"),
                  onPressed: () {
                    Workmanager().registerOneOffTask(
                      failedTaskKey,
                      failedTaskKey,
                    );
                  },
                ),
                //This task runs once
                //This wait at least 10 seconds before running
                ElevatedButton(
                    child: Text("Register Delayed OneOff Task"),
                    onPressed: () {
                      Workmanager().registerOneOffTask(
                        simpleDelayedTask,
                        simpleDelayedTask,
                        initialDelay: Duration(seconds: 10),
                      );
                    }),
                SizedBox(height: 8),
                Text(
                  "Register periodic task (android only)",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                //This task runs periodically
                //It will wait at least 10 seconds before its first launch
                //Since we have not provided a frequency it will be the default 15 minutes
                ElevatedButton(
                    child: Text("Register Periodic Task (Android)"),
                    onPressed: Platform.isAndroid
                        ? () {
                            Workmanager().registerPeriodicTask(
                              simplePeriodicTask,
                              simplePeriodicTask,
                              initialDelay: Duration(seconds: 10),
                            );
                          }
                        : null),
                //This task runs periodically
                //It will run about every hour
                ElevatedButton(
                    child: Text("Register 1 hour Periodic Task (Android)"),
                    onPressed: Platform.isAndroid
                        ? () {
                            Workmanager().registerPeriodicTask(
                              simplePeriodic1HourTask,
                              simplePeriodic1HourTask,
                              flexInterval: Duration(minutes: 15),
                              frequency: Duration(hours: 1),
                            );
                          }
                        : null),

                // Currently we cannot provide frequency for iOS, hence it will be
                // minimum 15 minutes after which iOS will reschedule
                ElevatedButton(
                  child: Text('Register Periodic Background App Refresh (iOS)'),
                  onPressed: Platform.isIOS
                      ? () async {
                          if (!workmanagerInitialized) {
                            _showNotInitialized();
                            return;
                          }
                          await Workmanager().registerPeriodicTask(
                            iOSBackgroundAppRefresh,
                            iOSBackgroundAppRefresh,
                            initialDelay: Duration(seconds: 10),
                            inputData: <String, dynamic>{}, //ignored on iOS
                          );
                        }
                      : null,
                ),

                // This task runs only once, to perform a time consuming task at
                // a later time decided by iOS.
                // Processing tasks run only when the device is idle. iOS might
                // terminate any running background processing tasks when the
                // user starts using the device.
                ElevatedButton(
                  child: Text('Register BackgroundProcessingTask (iOS)'),
                  onPressed: Platform.isIOS
                      ? () async {
                          if (!workmanagerInitialized) {
                            _showNotInitialized();
                            return;
                          }
                          await Workmanager().registerProcessingTask(
                            iOSBackgroundProcessingTask,
                            iOSBackgroundProcessingTask,
                            initialDelay: Duration(seconds: 20),
                          );
                        }
                      : null,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                    child: Text("isscheduled (Android)"),
                    onPressed: Platform.isAndroid
                        ? () async {
                            final workInfo =
                                await Workmanager().isScheduledByUniqueName(
                              simplePeriodicTask,
                            );
                            print('isscheduled = $workInfo');
                          }
                        : null),
                SizedBox(height: 8),
                Text(
                  "Task cancellation",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                ElevatedButton(
                  child: Text("Cancel All"),
                  onPressed: () async {
                    await Workmanager().cancelAll();
                    print('Cancel all tasks completed');
                  },
                ),
                SizedBox(height: 15),
                ElevatedButton(
                  child: Text('Refresh stats'),
                  onPressed: _refreshStats,
                ),
                SizedBox(height: 10),
                SingleChildScrollView(
                  child: Text(
                    'Task run stats:\n'
                    '${workmanagerInitialized ? '' : 'Workmanager not initialized'}'
                    '\n$_prefsString',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Refresh/get saved prefs
  void _refreshStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    _prefsString = '';
    for (final task in allTasks) {
      _prefsString = '$_prefsString \n$task:\n${prefs.getString(task)}\n';
    }

    if (Platform.isIOS) {
      Workmanager().printScheduledTasks();
    }

    setState(() {});
  }

  void _showNotInitialized() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Workmanager not initialized'),
          content: Text('Workmanager is not initialized, please initialize'),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showNoPermission(BuildContext context, PermissionStatus hasPermission) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('No permission'),
          content: Text('Background app refresh is disabled, please enable in '
              'App settings. Status ${hasPermission.name}'),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}
