package dev.fluttercommunity.workmanager

import android.content.Context
import android.content.pm.ServiceInfo
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkInfo
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker.Companion.DART_TASK_KEY
import dev.fluttercommunity.workmanager.BackgroundWorker.Companion.IS_IN_DEBUG_MODE_KEY
import dev.fluttercommunity.workmanager.BackgroundWorker.Companion.PAYLOAD_KEY
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

private fun Context.workManager() = WorkManager.getInstance(this)

private fun MethodChannel.Result.success() = success(true)

private interface CallHandler<T : WorkManagerCall> {
    fun handle(
        context: Context,
        convertedCall: T,
        result: MethodChannel.Result,
    )
}

class WorkmanagerCallHandler(private val ctx: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (val extractedCall = Extractor.extractWorkManagerCallFromRawMethodName(call)) {
            is WorkManagerCall.Initialize ->
                InitializeHandler.handle(
                    ctx,
                    extractedCall,
                    result,
                )
            is WorkManagerCall.RegisterTask ->
                RegisterTaskHandler.handle(
                    ctx,
                    extractedCall,
                    result,
                )
            is WorkManagerCall.IsScheduled ->
                IsScheduledHandler.handle(
                    ctx,
                    extractedCall,
                    result,
                )
            is WorkManagerCall.CancelTask ->
                UnregisterTaskHandler.handle(
                    ctx,
                    extractedCall,
                    result,
                )
            is WorkManagerCall.Failed ->
                FailedTaskHandler(extractedCall.code).handle(
                    ctx,
                    extractedCall,
                    result,
                )
            is WorkManagerCall.Unknown -> UnknownTaskHandler.handle(ctx, extractedCall, result)
        }
    }
}

private object InitializeHandler : CallHandler<WorkManagerCall.Initialize> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.Initialize,
        result: MethodChannel.Result,
    ) {
        SharedPreferenceHelper.saveCallbackDispatcherHandleKey(
            context,
            convertedCall.callbackDispatcherHandleKey,
        )
        result.success()
    }
}

private object RegisterTaskHandler : CallHandler<WorkManagerCall.RegisterTask> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.RegisterTask,
        result: MethodChannel.Result,
    ) {
        if (!SharedPreferenceHelper.hasCallbackHandle(context)) {
            result.error(
                "1",
                "You have not properly initialized the Flutter WorkManager Package. " +
                    "You should ensure you have called the 'initialize' function first! " +
                    "Example: \n" +
                    "\n" +
                    "`Workmanager().initialize(\n" +
                    "  callbackDispatcher,\n" +
                    " )`" +
                    "\n" +
                    "\n" +
                    "The `callbackDispatcher` is a top level function. See example in repository.",
                null,
            )
            return
        }

        when (convertedCall) {
            is WorkManagerCall.RegisterTask.OneOffTask -> enqueueOneOffTask(context, convertedCall)
            is WorkManagerCall.RegisterTask.PeriodicTask ->
                enqueuePeriodicTask(
                    context,
                    convertedCall,
                )
        }
        result.success()
    }

    private fun enqueuePeriodicTask(
        context: Context,
        convertedCall: WorkManagerCall.RegisterTask.PeriodicTask,
    ) {
        WM.enqueuePeriodicTask(
            context = context,
            uniqueName = convertedCall.uniqueName,
            dartTask = convertedCall.taskName,
            tag = convertedCall.tag,
            flexIntervalInSeconds = convertedCall.flexIntervalInSeconds,
            frequencyInSeconds = convertedCall.frequencyInSeconds,
            isInDebugMode = convertedCall.isInDebugMode,
            existingWorkPolicy = convertedCall.existingWorkPolicy,
            initialDelaySeconds = convertedCall.initialDelaySeconds,
            constraintsConfig = convertedCall.constraintsConfig,
            backoffPolicyConfig = convertedCall.backoffPolicyConfig,
            outOfQuotaPolicy = convertedCall.outOfQuotaPolicy,
            payload = convertedCall.payload,
        )
    }

    private fun enqueueOneOffTask(
        context: Context,
        convertedCall: WorkManagerCall.RegisterTask.OneOffTask,
    ) {
        WM.enqueueOneOffTask(
            context = context,
            uniqueName = convertedCall.uniqueName,
            dartTask = convertedCall.taskName,
            tag = convertedCall.tag,
            isInDebugMode = convertedCall.isInDebugMode,
            existingWorkPolicy = convertedCall.existingWorkPolicy,
            initialDelaySeconds = convertedCall.initialDelaySeconds,
            constraintsConfig = convertedCall.constraintsConfig,
            backoffPolicyConfig = convertedCall.backoffPolicyConfig,
            outOfQuotaPolicy = convertedCall.outOfQuotaPolicy,
            payload = convertedCall.payload,
        )
    }
}

private object IsScheduledHandler : CallHandler<WorkManagerCall.IsScheduled> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.IsScheduled,
        result: MethodChannel.Result,
    ) {
        when (convertedCall) {
            is WorkManagerCall.IsScheduled.ByUniqueName -> {
                val workInfos = WM.getWorkInfoByUniqueName(context, convertedCall.uniqueName).get()
                val scheduled =
                    workInfos.isNotEmpty() &&
                        workInfos.all { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING }
                return result.success(scheduled)
            }
        }
    }
}

private object UnregisterTaskHandler : CallHandler<WorkManagerCall.CancelTask> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.CancelTask,
        result: MethodChannel.Result,
    ) {
        when (convertedCall) {
            is WorkManagerCall.CancelTask.ByUniqueName ->
                WM.cancelByUniqueName(
                    context,
                    convertedCall.uniqueName,
                )
            is WorkManagerCall.CancelTask.ByTag -> WM.cancelByTag(context, convertedCall.tag)
            WorkManagerCall.CancelTask.All -> WM.cancelAll(context)
        }
        result.success()
    }
}

class FailedTaskHandler(private val code: String) : CallHandler<WorkManagerCall.Failed> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.Failed,
        result: MethodChannel.Result,
    ) {
        result.error(code, null, null)
    }
}

private object UnknownTaskHandler : CallHandler<WorkManagerCall.Unknown> {
    override fun handle(
        context: Context,
        convertedCall: WorkManagerCall.Unknown,
        result: MethodChannel.Result,
    ) {
        result.notImplemented()
    }
}

object WM {
    fun enqueueOneOffTask(
        context: Context,
        uniqueName: String,
        dartTask: String,
        payload: String? = null,
        tag: String? = null,
        isInDebugMode: Boolean = false,
        existingWorkPolicy: ExistingWorkPolicy = defaultOneOffExistingWorkPolicy,
        initialDelaySeconds: Long = DEFAULT_INITIAL_DELAY_SECONDS,
        constraintsConfig: Constraints = defaultConstraints,
        outOfQuotaPolicy: OutOfQuotaPolicy? = defaultOutOfQuotaPolicy,
        backoffPolicyConfig: BackoffPolicyTaskConfig?,
    ) {
        val oneOffTaskRequest =
            OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                .setInputData(buildTaskInputData(dartTask, isInDebugMode, payload))
                .setInitialDelay(initialDelaySeconds, TimeUnit.SECONDS)
                .setConstraints(constraintsConfig)
                .apply {
                    if (backoffPolicyConfig != null) {
                        setBackoffCriteria(
                            backoffPolicyConfig.backoffPolicy,
                            backoffPolicyConfig.backoffDelay,
                            TimeUnit.MILLISECONDS,
                        )
                    }
                }
                .apply {
                    tag?.let(::addTag)
                    outOfQuotaPolicy?.let(::setExpedited)
                }
                .build()
        context.workManager()
            .enqueueUniqueWork(uniqueName, existingWorkPolicy, oneOffTaskRequest)
    }

    fun enqueuePeriodicTask(
        context: Context,
        uniqueName: String,
        dartTask: String,
        payload: String? = null,
        tag: String? = null,
        frequencyInSeconds: Long = DEFAULT_PERIODIC_REFRESH_FREQUENCY_SECONDS,
        flexIntervalInSeconds: Long = DEFAULT_FLEX_INTERVAL_SECONDS,
        isInDebugMode: Boolean = false,
        existingWorkPolicy: ExistingPeriodicWorkPolicy = defaultPeriodExistingWorkPolicy,
        initialDelaySeconds: Long = DEFAULT_INITIAL_DELAY_SECONDS,
        constraintsConfig: Constraints = defaultConstraints,
        outOfQuotaPolicy: OutOfQuotaPolicy? = defaultOutOfQuotaPolicy,
        backoffPolicyConfig: BackoffPolicyTaskConfig?,
    ) {
        val periodicTaskRequest =
            PeriodicWorkRequest.Builder(
                BackgroundWorker::class.java,
                frequencyInSeconds,
                TimeUnit.SECONDS,
                flexIntervalInSeconds,
                TimeUnit.SECONDS,
            )
                .setInputData(buildTaskInputData(dartTask, isInDebugMode, payload))
                .setInitialDelay(initialDelaySeconds, TimeUnit.SECONDS)
                .setConstraints(constraintsConfig)
                .apply {
                    if (backoffPolicyConfig != null) {
                        setBackoffCriteria(
                            backoffPolicyConfig.backoffPolicy,
                            backoffPolicyConfig.backoffDelay,
                            TimeUnit.MILLISECONDS,
                        )
                    }
                }
                .apply {
                    tag?.let(::addTag)
                    outOfQuotaPolicy?.let(::setExpedited)
                }
                .build()
        context.workManager()
            .enqueueUniquePeriodicWork(uniqueName, existingWorkPolicy, periodicTaskRequest)
    }

    private fun buildTaskInputData(
        dartTask: String,
        isInDebugMode: Boolean,
        payload: String?,
    ): Data {
        return Data.Builder()
            .putString(DART_TASK_KEY, dartTask)
            .putBoolean(IS_IN_DEBUG_MODE_KEY, isInDebugMode)
            .apply {
                payload?.let {
                    putString(PAYLOAD_KEY, payload)
                }
            }
            .build()
    }

    fun getWorkInfoByUniqueName(
        context: Context,
        uniqueWorkName: String,
    ) = context.workManager().getWorkInfosForUniqueWork(uniqueWorkName)

    fun cancelByUniqueName(
        context: Context,
        uniqueWorkName: String,
    ) = context.workManager().cancelUniqueWork(uniqueWorkName)

    fun cancelByTag(
        context: Context,
        tag: String,
    ) = context.workManager().cancelAllWorkByTag(tag)

    fun cancelAll(context: Context) = context.workManager().cancelAllWork()
}
