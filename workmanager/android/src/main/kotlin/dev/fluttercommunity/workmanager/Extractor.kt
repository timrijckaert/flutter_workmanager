package dev.fluttercommunity.workmanager

import android.os.Build
import androidx.annotation.VisibleForTesting
import androidx.work.*
import dev.fluttercommunity.workmanager.WorkManagerCall.CancelTask.ByTag.KEYS.UNREGISTER_TASK_TAG_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.CancelTask.ByUniqueName.KEYS.UNREGISTER_TASK_UNIQUE_NAME_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.Initialize.KEYS.INITIALIZE_TASK_CALL_HANDLE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.Initialize.KEYS.INITIALIZE_TASK_IS_IN_DEBUG_MODE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.IsScheduled.ByUniqueName.KEYS.IS_SCHEDULED_UNIQUE_NAME_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_BACK_OFF_POLICY_DELAY_MILLIS_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_BACK_OFF_POLICY_TYPE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_CONSTRAINTS_BATTERY_NOT_LOW_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_CONSTRAINTS_CHARGING_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_CONSTRAINTS_DEVICE_IDLE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_CONSTRAINTS_NETWORK_TYPE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_CONSTRAINTS_STORAGE_NOT_LOW_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_EXISTING_WORK_POLICY_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_INITIAL_DELAY_SECONDS_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_IS_IN_DEBUG_MODE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_NAME_VALUE_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_OUT_OF_QUOTA_POLICY_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_PAYLOAD_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_TAG_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.KEYS.REGISTER_TASK_UNIQUE_NAME_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.PeriodicTask.KEYS.PERIODIC_FLEX_INTERVAL_SECONDS_KEY
import dev.fluttercommunity.workmanager.WorkManagerCall.RegisterTask.PeriodicTask.KEYS.PERIODIC_TASK_FREQUENCY_SECONDS_KEY
import io.flutter.plugin.common.MethodCall
import kotlin.math.max

val defaultBackOffPolicy = BackoffPolicy.EXPONENTIAL
val defaultNetworkType = NetworkType.NOT_REQUIRED
val defaultOutOfQuotaPolicy: OutOfQuotaPolicy? = null
val defaultOneOffExistingWorkPolicy = ExistingWorkPolicy.KEEP
val defaultPeriodExistingWorkPolicy = ExistingPeriodicWorkPolicy.KEEP
val defaultConstraints: Constraints = Constraints.NONE
const val DEFAULT_INITIAL_DELAY_SECONDS = 0L
const val DEFAULT_REQUESTED_BACKOFF_DELAY = 0L
const val DEFAULT_PERIODIC_REFRESH_FREQUENCY_SECONDS =
    PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS / 1000
const val DEFAULT_FLEX_INTERVAL_SECONDS =
    PeriodicWorkRequest.MIN_PERIODIC_FLEX_MILLIS / 1000
const val LOG_TAG = "Extractor"

data class BackoffPolicyTaskConfig(
    val backoffPolicy: BackoffPolicy,
    private val requestedBackoffDelay: Long,
    private val minBackoffInMillis: Long,
    val backoffDelay: Long = max(minBackoffInMillis, requestedBackoffDelay),
)

sealed class WorkManagerCall {
    data class Initialize(
        val callbackDispatcherHandleKey: Long,
        val isInDebugMode: Boolean,
    ) : WorkManagerCall() {
        companion object KEYS {
            const val INITIALIZE_TASK_IS_IN_DEBUG_MODE_KEY = "isInDebugMode"
            const val INITIALIZE_TASK_CALL_HANDLE_KEY = "callbackHandle"
        }
    }

    sealed class RegisterTask : WorkManagerCall() {
        abstract val isInDebugMode: Boolean
        abstract val uniqueName: String
        abstract val taskName: String
        abstract val tag: String?
        abstract val initialDelaySeconds: Long
        abstract val constraintsConfig: Constraints?
        abstract val payload: String?

        companion object KEYS {
            const val REGISTER_TASK_IS_IN_DEBUG_MODE_KEY = "isInDebugMode"
            const val REGISTER_TASK_UNIQUE_NAME_KEY = "uniqueName"
            const val REGISTER_TASK_NAME_VALUE_KEY = "taskName"
            const val REGISTER_TASK_TAG_KEY = "tag"
            const val REGISTER_TASK_EXISTING_WORK_POLICY_KEY = "existingWorkPolicy"

            const val REGISTER_TASK_CONSTRAINTS_NETWORK_TYPE_KEY = "networkType"
            const val REGISTER_TASK_CONSTRAINTS_BATTERY_NOT_LOW_KEY = "requiresBatteryNotLow"
            const val REGISTER_TASK_CONSTRAINTS_CHARGING_KEY = "requiresCharging"
            const val REGISTER_TASK_CONSTRAINTS_DEVICE_IDLE_KEY = "requiresDeviceIdle"
            const val REGISTER_TASK_CONSTRAINTS_STORAGE_NOT_LOW_KEY = "requiresStorageNotLow"

            const val REGISTER_TASK_INITIAL_DELAY_SECONDS_KEY = "initialDelaySeconds"

            const val REGISTER_TASK_BACK_OFF_POLICY_TYPE_KEY = "backoffPolicyType"
            const val REGISTER_TASK_BACK_OFF_POLICY_DELAY_MILLIS_KEY = "backoffDelayInMilliseconds"
            const val REGISTER_TASK_OUT_OF_QUOTA_POLICY_KEY = "outOfQuotaPolicy"
            const val REGISTER_TASK_PAYLOAD_KEY = "inputData"
        }

        data class OneOffTask(
            override val isInDebugMode: Boolean,
            override val uniqueName: String,
            override val taskName: String,
            override val tag: String? = null,
            val existingWorkPolicy: ExistingWorkPolicy,
            override val initialDelaySeconds: Long,
            override val constraintsConfig: Constraints,
            val backoffPolicyConfig: BackoffPolicyTaskConfig?,
            val outOfQuotaPolicy: OutOfQuotaPolicy?,
            override val payload: String? = null,
        ) : RegisterTask()

        data class PeriodicTask(
            override val isInDebugMode: Boolean,
            override val uniqueName: String,
            override val taskName: String,
            override val tag: String? = null,
            val existingWorkPolicy: ExistingPeriodicWorkPolicy,
            val frequencyInSeconds: Long,
            val flexIntervalInSeconds: Long,
            override val initialDelaySeconds: Long,
            override val constraintsConfig: Constraints,
            val backoffPolicyConfig: BackoffPolicyTaskConfig?,
            val outOfQuotaPolicy: OutOfQuotaPolicy?,
            override val payload: String? = null,
        ) : RegisterTask() {
            companion object KEYS {
                const val PERIODIC_TASK_FREQUENCY_SECONDS_KEY = "frequency"
                const val PERIODIC_FLEX_INTERVAL_SECONDS_KEY = "flexInterval"
            }
        }
    }

    sealed class IsScheduled : WorkManagerCall() {
        data class ByUniqueName(val uniqueName: String) : IsScheduled() {
            companion object KEYS {
                const val IS_SCHEDULED_UNIQUE_NAME_KEY = "uniqueName"
            }
        }
    }

    sealed class CancelTask : WorkManagerCall() {
        data class ByUniqueName(val uniqueName: String) : CancelTask() {
            companion object KEYS {
                const val UNREGISTER_TASK_UNIQUE_NAME_KEY = "uniqueName"
            }
        }

        data class ByTag(val tag: String) : CancelTask() {
            companion object KEYS {
                const val UNREGISTER_TASK_TAG_KEY = "tag"
            }
        }

        object All : CancelTask()
    }

    object Unknown : WorkManagerCall()

    class Failed(val code: String) : WorkManagerCall()
}
data class SetForeground(
    val foregroundServiceType: Int,
    val notificationId: Int,
    val notificationChannelId: String,
    val notificationChannelName: String,
    val notificationChannelDescription: String,
    val notificationChannelImportance: Int,
    val notificationTitle: String,
    val notificationDescription: String,
) {
    companion object KEYS {
        const val FOREGROUND_SERVICE_TYPE_KEY = "foregroundServiceType"
        const val NOTIFICATION_ID_KEY = "notificationId"
        const val NOTIFICATION_CHANNEL_ID_KEY = "notificationChannelId"
        const val NOTIFICATION_CHANNEL_NAME_KEY = "notificationChannelName"
        const val NOTIFICATION_CHANNEL_DESCRIPTION_KEY = "notificationChannelDescription"
        const val NOTIFICATION_CHANNEL_IMPORTANCE_KEY = "notificationChannelImportance"
        const val NOTIFICATION_TITLE_KEY = "notificationTitle"
        const val NOTIFICATION_DESCRIPTION_KEY = "notificationDescription"
    }
}
private enum class TaskType(val minimumBackOffDelay: Long) {
    ONE_OFF(WorkRequest.MIN_BACKOFF_MILLIS),
    PERIODIC(WorkRequest.MIN_BACKOFF_MILLIS),
}

object Extractor {
    private enum class PossibleWorkManagerCall(val rawMethodName: String?) {
        INITIALIZE("initialize"),

        REGISTER_ONE_OFF_TASK("registerOneOffTask"),
        REGISTER_PERIODIC_TASK("registerPeriodicTask"),

        IS_SCHEDULED_BY_UNIQUE_NAME("isScheduledByUniqueName"),

        CANCEL_TASK_BY_UNIQUE_NAME("cancelTaskByUniqueName"),
        CANCEL_TASK_BY_TAG("cancelTaskByTag"),
        CANCEL_ALL("cancelAllTasks"),

        UNKNOWN(null),
        ;

        companion object {
            fun fromRawMethodName(methodName: String): PossibleWorkManagerCall =
                values()
                    .filter { !it.rawMethodName.isNullOrEmpty() }
                    .firstOrNull { it.rawMethodName == methodName }
                    ?: UNKNOWN
        }
    }

    fun parseSetForegroundCall(call: MethodCall): SetForeground {
        val foregroundServiceType =
            call.argument<Int>(SetForeground.KEYS.FOREGROUND_SERVICE_TYPE_KEY)!!
        val notificationId = call.argument<Int>(SetForeground.KEYS.NOTIFICATION_ID_KEY)!!
        val notificationChannelId =
            call.argument<String>(SetForeground.KEYS.NOTIFICATION_CHANNEL_ID_KEY)!!
        val notificationChannelName =
            call.argument<String>(SetForeground.KEYS.NOTIFICATION_CHANNEL_NAME_KEY)!!
        val notificationChannelDescription =
            call.argument<String>(SetForeground.KEYS.NOTIFICATION_CHANNEL_DESCRIPTION_KEY)!!
        val notificationChannelImportance =
            call.argument<Int>(SetForeground.KEYS.NOTIFICATION_CHANNEL_IMPORTANCE_KEY)!!
        val notificationTitle =
            call.argument<String>(SetForeground.KEYS.NOTIFICATION_TITLE_KEY)!!
        val notificationDescription =
            call.argument<String>(SetForeground.KEYS.NOTIFICATION_DESCRIPTION_KEY)!!
        return SetForeground(
            foregroundServiceType,
            notificationId,
            notificationChannelId,
            notificationChannelName,
            notificationChannelDescription,
            notificationChannelImportance,
            notificationTitle,
            notificationDescription,
        )
    }

    fun extractWorkManagerCallFromRawMethodName(call: MethodCall): WorkManagerCall =
        when (PossibleWorkManagerCall.fromRawMethodName(call.method)) {
            PossibleWorkManagerCall.INITIALIZE -> {
                val handle = call.argument<Number>(INITIALIZE_TASK_CALL_HANDLE_KEY)?.toLong()
                val inDebugMode = call.argument<Boolean>(INITIALIZE_TASK_IS_IN_DEBUG_MODE_KEY)

                if (handle == null || inDebugMode == null) {
                    WorkManagerCall.Failed("Invalid parameters passed")
                } else {
                    WorkManagerCall.Initialize(handle, inDebugMode)
                }
            }

            PossibleWorkManagerCall.REGISTER_ONE_OFF_TASK -> {
                WorkManagerCall.RegisterTask.OneOffTask(
                    isInDebugMode = call.argument<Boolean>(REGISTER_TASK_IS_IN_DEBUG_MODE_KEY)!!,
                    uniqueName = call.argument<String>(REGISTER_TASK_UNIQUE_NAME_KEY)!!,
                    taskName = call.argument<String>(REGISTER_TASK_NAME_VALUE_KEY)!!,
                    tag = call.argument<String>(REGISTER_TASK_TAG_KEY),
                    existingWorkPolicy = extractExistingWorkPolicyFromCall(call),
                    initialDelaySeconds = extractInitialDelayFromCall(call),
                    constraintsConfig = extractConstraintConfigFromCall(call),
                    outOfQuotaPolicy = extractOutOfQuotaPolicyFromCall(call),
                    backoffPolicyConfig =
                    extractBackoffPolicyConfigFromCall(
                        call,
                        TaskType.ONE_OFF,
                    ),
                    payload = extractPayload(call),
                )
            }

            PossibleWorkManagerCall.REGISTER_PERIODIC_TASK -> {
                WorkManagerCall.RegisterTask.PeriodicTask(
                    isInDebugMode = call.argument<Boolean>(REGISTER_TASK_IS_IN_DEBUG_MODE_KEY)!!,
                    uniqueName = call.argument<String>(REGISTER_TASK_UNIQUE_NAME_KEY)!!,
                    taskName = call.argument<String>(REGISTER_TASK_NAME_VALUE_KEY)!!,
                    frequencyInSeconds = extractFrequencySecondsFromCall(call),
                    tag = call.argument<String>(REGISTER_TASK_TAG_KEY),
                    flexIntervalInSeconds = extractFlexIntervalSecondsFromCall(call),
                    existingWorkPolicy = extractExistingPeriodicWorkPolicyFromCall(call),
                    initialDelaySeconds = extractInitialDelayFromCall(call),
                    constraintsConfig = extractConstraintConfigFromCall(call),
                    backoffPolicyConfig =
                    extractBackoffPolicyConfigFromCall(
                        call,
                        TaskType.PERIODIC,
                    ),
                    outOfQuotaPolicy = extractOutOfQuotaPolicyFromCall(call),
                    payload = extractPayload(call),
                )
            }

            PossibleWorkManagerCall.IS_SCHEDULED_BY_UNIQUE_NAME -> {
                WorkManagerCall.IsScheduled.ByUniqueName(
                    call.argument(IS_SCHEDULED_UNIQUE_NAME_KEY)!!,
                )
            }

            PossibleWorkManagerCall.CANCEL_TASK_BY_UNIQUE_NAME ->
                WorkManagerCall.CancelTask.ByUniqueName(
                    call.argument(UNREGISTER_TASK_UNIQUE_NAME_KEY)!!,
                )

            PossibleWorkManagerCall.CANCEL_TASK_BY_TAG ->
                WorkManagerCall.CancelTask.ByTag(
                    call.argument(
                        UNREGISTER_TASK_TAG_KEY,
                    )!!,
                )

            PossibleWorkManagerCall.CANCEL_ALL -> WorkManagerCall.CancelTask.All

            PossibleWorkManagerCall.UNKNOWN -> WorkManagerCall.Unknown
        }

    private fun extractExistingWorkPolicyFromCall(call: MethodCall): ExistingWorkPolicy =
        try {
            ExistingWorkPolicy.valueOf(
                call.argument<String>(REGISTER_TASK_EXISTING_WORK_POLICY_KEY)!!.uppercase(),
            )
        } catch (ignored: Exception) {
            defaultOneOffExistingWorkPolicy
        }

    private fun extractExistingPeriodicWorkPolicyFromCall(call: MethodCall) =
        try {
            ExistingPeriodicWorkPolicy.valueOf(
                call.argument<String>(
                    REGISTER_TASK_EXISTING_WORK_POLICY_KEY,
                )!!.uppercase(),
            )
        } catch (ignored: Exception) {
            defaultPeriodExistingWorkPolicy
        }

    private fun extractFrequencySecondsFromCall(call: MethodCall) =
        call.argument<Int>(PERIODIC_TASK_FREQUENCY_SECONDS_KEY)?.toLong()
            ?: DEFAULT_PERIODIC_REFRESH_FREQUENCY_SECONDS

    private fun extractFlexIntervalSecondsFromCall(call: MethodCall) =
        call.argument<Int>(PERIODIC_FLEX_INTERVAL_SECONDS_KEY)?.toLong()
            ?: DEFAULT_FLEX_INTERVAL_SECONDS

    private fun extractInitialDelayFromCall(call: MethodCall) =
        call.argument<Int>(REGISTER_TASK_INITIAL_DELAY_SECONDS_KEY)?.toLong()
            ?: DEFAULT_INITIAL_DELAY_SECONDS

    private fun extractBackoffPolicyConfigFromCall(
        call: MethodCall,
        taskType: TaskType,
    ): BackoffPolicyTaskConfig? {
        if (call.argument<String?>(REGISTER_TASK_BACK_OFF_POLICY_TYPE_KEY) == null) {
            return null
        }

        val backoffPolicy =
            try {
                BackoffPolicy.valueOf(
                    call.argument<String>(REGISTER_TASK_BACK_OFF_POLICY_TYPE_KEY)!!.uppercase(),
                )
            } catch (ignored: Exception) {
                defaultBackOffPolicy
            }

        val requestedBackoffDelay =
            call.argument<Int>(REGISTER_TASK_BACK_OFF_POLICY_DELAY_MILLIS_KEY)?.toLong()
                ?: DEFAULT_REQUESTED_BACKOFF_DELAY
        val minimumBackOffDelay = taskType.minimumBackOffDelay

        return BackoffPolicyTaskConfig(
            backoffPolicy,
            requestedBackoffDelay,
            minimumBackOffDelay,
        )
    }

    @VisibleForTesting
    fun extractOutOfQuotaPolicyFromCall(call: MethodCall): OutOfQuotaPolicy? {
        try {
            return OutOfQuotaPolicy.valueOf(
                call.argument<String>(REGISTER_TASK_OUT_OF_QUOTA_POLICY_KEY)!!.uppercase(),
            )
        } catch (ignored: Exception) {
            return defaultOutOfQuotaPolicy
        }
    }

    @VisibleForTesting(otherwise = VisibleForTesting.PRIVATE)
    fun extractConstraintConfigFromCall(call: MethodCall): Constraints {
        fun extractNetworkTypeFromCall(call: MethodCall) =
            try {
                NetworkType.valueOf(
                    call.argument<String>(REGISTER_TASK_CONSTRAINTS_NETWORK_TYPE_KEY)!!.uppercase(),
                )
            } catch (ignored: Exception) {
                defaultNetworkType
            }

        val requestedNetworkType = extractNetworkTypeFromCall(call)
        val requiresBatteryNotLow =
            call.argument<Boolean>(REGISTER_TASK_CONSTRAINTS_BATTERY_NOT_LOW_KEY)
                ?: false
        val requiresCharging =
            call.argument<Boolean>(REGISTER_TASK_CONSTRAINTS_CHARGING_KEY)
                ?: false
        val requiresDeviceIdle =
            call.argument<Boolean>(REGISTER_TASK_CONSTRAINTS_DEVICE_IDLE_KEY)
                ?: false
        val requiresStorageNotLow =
            call.argument<Boolean>(REGISTER_TASK_CONSTRAINTS_STORAGE_NOT_LOW_KEY)
                ?: false
        return Constraints.Builder()
            .setRequiredNetworkType(requestedNetworkType)
            .setRequiresBatteryNotLow(requiresBatteryNotLow)
            .setRequiresCharging(requiresCharging)
            .setRequiresStorageNotLow(requiresStorageNotLow)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    setRequiresDeviceIdle(requiresDeviceIdle)
                }
            }
            .build()
    }

    private fun extractPayload(call: MethodCall): String? {
        return call.argument<String>(REGISTER_TASK_PAYLOAD_KEY)
    }
}
