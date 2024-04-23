# Flutter Workmanager

[![pub package](https://img.shields.io/pub/v/workmanager.svg)](https://pub.dartlang.org/packages/workmanager)

=======

Flutter WorkManager is a wrapper around [Android's WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager), [iOS' performFetchWithCompletionHandler](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623125-application) and [iOS BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), effectively enabling headless execution of Dart code in the background.

For iOS users, please watch this video  on a general introduction to background processing: https://developer.apple.com/videos/play/wwdc2020/10063. All of the constraints discussed in the video also apply to this plugin.

This is especially useful to run periodic tasks, such as fetching remote data on a regular basis.

> This plugin was featured in this [Medium blogpost](https://medium.com/vrt-digital-studio/flutter-workmanager-81e0cfbd6f6e)