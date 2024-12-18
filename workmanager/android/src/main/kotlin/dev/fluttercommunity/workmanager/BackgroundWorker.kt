package dev.fluttercommunity.workmanager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.*


/***
 * A simple worker that will post your input back to your Flutter application.
 *
 * It will block the background thread until a value of either true or false is received back from Flutter code.
 */
class BackgroundWorker(
    applicationContext: Context,
    private val workerParams: WorkerParameters,
) : ListenableWorker(applicationContext, workerParams), MethodChannel.MethodCallHandler {
    private lateinit var backgroundChannel: MethodChannel

    companion object {
        const val TAG = "BackgroundWorker"

        const val PAYLOAD_KEY = "be.tramckrijte.workmanager.INPUT_DATA"
        const val DART_TASK_KEY = "be.tramckrijte.workmanager.DART_TASK"
        const val IS_IN_DEBUG_MODE_KEY = "be.tramckrijte.workmanager.IS_IN_DEBUG_MODE_KEY"

        const val BACKGROUND_CHANNEL_NAME =
            "be.tramckrijte.workmanager/background_channel_work_manager"
        const val BACKGROUND_CHANNEL_INITIALIZED = "backgroundChannelInitialized"
        const val SET_FOREGROUND = "setForeground"

        private val flutterLoader = FlutterLoader()
    }

    private val payload
        get() = workerParams.inputData.getString(PAYLOAD_KEY)

    private val dartTask
        get() = workerParams.inputData.getString(DART_TASK_KEY)!!

    private val isInDebug
        get() = workerParams.inputData.getBoolean(IS_IN_DEBUG_MODE_KEY, false)

    private val randomThreadIdentifier = Random().nextInt()
    private var engine: FlutterEngine? = null

    private var startTime: Long = 0

    private var completer: CallbackToFutureAdapter.Completer<Result>? = null

    private var resolvableFuture =
        CallbackToFutureAdapter.getFuture { completer ->
            this.completer = completer
            null
        }

    private fun createForegroundInfo(
        setForegroundOptions: SetForeground
    ): ForegroundInfo {
        // Create a Notification channel if necessary
        createNotificationChannel(
            setForegroundOptions.notificationChannelId,
            setForegroundOptions.notificationChannelName,
            setForegroundOptions.notificationChannelDescription,
            setForegroundOptions.notificationChannelImportance
        )
        val notification = NotificationCompat.Builder(applicationContext, setForegroundOptions.notificationChannelId)
            .setContentTitle(setForegroundOptions.notificationTitle)
            .setTicker(setForegroundOptions.notificationTitle)
            .setContentText(setForegroundOptions.notificationDescription)
            .setOngoing(true)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()

        return ForegroundInfo(
            setForegroundOptions.notificationId,
            notification,
            setForegroundOptions.foregroundServiceType
        )
    }

    private fun createNotificationChannel(id: String, name: String, description: String, importance: Int) {
        // Create a Notification channel
        // Notification channels are only available in OREO and higher.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mChannel = NotificationChannel(id, name, importance)
            mChannel.description = description
            val notificationManager = applicationContext.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(mChannel)
        }
    }

    override fun startWork(): ListenableFuture<Result> {
        startTime = System.currentTimeMillis()

        engine = FlutterEngine(applicationContext)

        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(applicationContext)
        }

        flutterLoader.ensureInitializationCompleteAsync(
            applicationContext,
            null,
            Handler(Looper.getMainLooper()),
        ) {
            val callbackHandle = SharedPreferenceHelper.getCallbackHandle(applicationContext)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
            val dartBundlePath = flutterLoader.findAppBundlePath()

            if (isInDebug) {
                DebugHelper.postTaskStarting(
                    applicationContext,
                    randomThreadIdentifier,
                    dartTask,
                    payload,
                    callbackHandle,
                    callbackInfo,
                    dartBundlePath,
                )
            }

            engine?.let { engine ->
                backgroundChannel = MethodChannel(engine.dartExecutor, BACKGROUND_CHANNEL_NAME)
                backgroundChannel.setMethodCallHandler(this@BackgroundWorker)

                engine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(
                        applicationContext.assets,
                        dartBundlePath,
                        callbackInfo,
                    ),
                )
            }
        }

        return resolvableFuture
    }

    override fun onStopped() {
        stopEngine(null)
    }

    private fun stopEngine(result: Result?) {
        val fetchDuration = System.currentTimeMillis() - startTime

        if (isInDebug) {
            DebugHelper.postTaskCompleteNotification(
                applicationContext,
                randomThreadIdentifier,
                dartTask,
                payload,
                fetchDuration,
                result ?: Result.failure(),
            )
        }

        // No result indicates we were signalled to stop by WorkManager.  The result is already
        // STOPPED, so no need to resolve another one.
        if (result != null) {
            this.completer?.set(result)
        }

        // If stopEngine is called from `onStopped`, it may not be from the main thread.
        Handler(Looper.getMainLooper()).post {
            engine?.destroy()
            engine = null
        }
    }

    private fun onBackgroundChannelInitialized() {
        backgroundChannel.invokeMethod(
            "onResultSend",
            mapOf(DART_TASK_KEY to dartTask, PAYLOAD_KEY to payload),
            object : MethodChannel.Result {
                override fun notImplemented() {
                    stopEngine(Result.failure())
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    Log.e(TAG, "errorCode: $errorCode, errorMessage: $errorMessage")
                    stopEngine(Result.failure())
                }

                override fun success(receivedResult: Any?) {
                    val wasSuccessFul = receivedResult?.let { it as Boolean? } == true
                    stopEngine(if (wasSuccessFul) Result.success() else Result.retry())
                }
            },
        )
    }

    private fun onSetForeground(setForegroundOptions: SetForeground) {
        setForegroundAsync(createForegroundInfo(setForegroundOptions))
    }

    override fun onMethodCall(
        call: MethodCall,
        r: MethodChannel.Result,
    ) {
        when (call.method) {
            BACKGROUND_CHANNEL_INITIALIZED ->
                onBackgroundChannelInitialized()

            SET_FOREGROUND -> onSetForeground(Extractor.parseSetForegroundCall(call))
        }
        r.success(null)
    }
}
