package be.tramckrijte.workmanager

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import io.flutter.view.FlutterMain
import io.flutter.view.FlutterNativeView
import io.flutter.view.FlutterRunArguments
import java.util.*
import java.util.concurrent.CountDownLatch
import kotlin.collections.HashMap
import kotlin.system.measureTimeMillis

/***
 * A simple worker that will post your input back to your Flutter application.
 *
 * It will block the background thread until a value of either true or false is received back from Flutter code.
 *
 */
class BackgroundWorker(private val ctx: Context,
                       private val workerParams: WorkerParameters) : Worker(ctx, workerParams), MethodChannel.MethodCallHandler {

    private lateinit var backgroundChannel: MethodChannel

    companion object {
        const val DART_TASK_KEY = "be.tramckrijte.workmanager.DART_TASK"
        const val IS_IN_DEBUG_MODE = "be.tramckrijte.workmanager.IS_IN_DEBUG_MODE"

        const val BACKGROUND_CHANNEL_NAME = "be.tramckrijte.workmanager/background_channel_work_manager"
        const val BACKGROUND_CHANNEL_INITIALIZED = "backgroundChannelInitialized"
    }

    private val inputData by lazy {
        val map = HashMap<String, Any>()
        for (entry in workerParams.inputData.keyValueMap.entries) {
            val key = entry.key
            when (val value = entry.value) {
                //because io.flutter.plugin.common.StandardMessageCodec use Boolean.TRUE and Boolean.FALSE inside writeValue
                is Boolean -> map[key] = if (value) java.lang.Boolean.TRUE else java.lang.Boolean.TRUE
                is Array<*> -> map[key] = value.toList()
                else -> map[key] = value
            }
        }
        map
    }

    private val isInDebug
        get() = workerParams.inputData.getBoolean(IS_IN_DEBUG_MODE, false)

    private val latch = CountDownLatch(1)
    private val randomThreadIdentifier = Random().nextInt()
    var result: Result = Result.retry()

    override fun doWork(): Result {
        Handler(Looper.getMainLooper()).post {
            FlutterMain.ensureInitializationComplete(ctx, null)

            val callbackHandle = SharedPreferenceHelper.getCallbackHandle(ctx)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
            val dartBundlePath = FlutterMain.findAppBundlePath(ctx)

            if (isInDebug) {
                DebugHelper.postTaskStarting(ctx, randomThreadIdentifier, workerParams.inputData.keyValueMap, callbackHandle, callbackInfo, dartBundlePath)
            }

            val backgroundFlutterView = FlutterNativeView(ctx, true)

            val args =
                    FlutterRunArguments()
                            .apply {
                                bundlePath = FlutterMain.findAppBundlePath(ctx)
                                entrypoint = callbackInfo.callbackName
                                libraryPath = callbackInfo.callbackLibraryPath
                            }

            backgroundFlutterView.runFromBundle(args)

            WorkmanagerPlugin.pluginRegistryCallback.registerWith(backgroundFlutterView.pluginRegistry)

            backgroundChannel = MethodChannel(backgroundFlutterView, BACKGROUND_CHANNEL_NAME)
            backgroundChannel.setMethodCallHandler(this)
        }

        val fetchDuration = measureTimeMillis {
            latch.await()
        }

        if (isInDebug) {
            DebugHelper.postTaskCompleteNotification(ctx, randomThreadIdentifier, inputData, fetchDuration, result)
        }

        return result
    }

    override fun onMethodCall(call: MethodCall, r: MethodChannel.Result) {
        when (call.method) {
            BACKGROUND_CHANNEL_INITIALIZED ->
                backgroundChannel.invokeMethod(
                        "onResultSend",
                        inputData,
                        object : MethodChannel.Result {
                            override fun notImplemented() {
                                latch.countDown()
                            }

                            override fun error(p0: String?, p1: String?, p2: Any?) {
                                latch.countDown()
                            }

                            override fun success(p0: Any?) {
                                result = Result.success()
                                latch.countDown()
                            }
                        })
        }
    }
}