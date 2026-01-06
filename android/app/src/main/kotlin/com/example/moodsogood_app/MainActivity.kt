package tw.heartsshine.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.*
import java.util.concurrent.TimeUnit
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class MainActivity : FlutterActivity() {
    private val CHANNEL = "tw.heartsshine.app/workmanager"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleDailyNotification" -> {
                    val hour = call.argument<Int>("hour") ?: 22
                    val minute = call.argument<Int>("minute") ?: 0
                    scheduleDailyWork(hour, minute)
                    result.success(true)
                }
                "cancelDailyNotification" -> {
                    WorkManager.getInstance(applicationContext).cancelUniqueWork("daily_reminder")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleDailyWork(hour: Int, minute: Int) {
        val currentDate = java.util.Calendar.getInstance()
        val dueDate = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
            set(java.util.Calendar.SECOND, 0)
        }

        if (dueDate.before(currentDate)) {
            dueDate.add(java.util.Calendar.HOUR_OF_DAY, 24)
        }

        val timeDiff = dueDate.timeInMillis - currentDate.timeInMillis

        val dailyWorkRequest = PeriodicWorkRequestBuilder<DailyReminderWorker>(
            24, TimeUnit.HOURS
        )
            .setInitialDelay(timeDiff, TimeUnit.MILLISECONDS)
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            "daily_reminder",
            ExistingPeriodicWorkPolicy.REPLACE,
            dailyWorkRequest
        )
    }
}

class DailyReminderWorker(appContext: Context, workerParams: WorkerParameters) :
    Worker(appContext, workerParams) {

    override fun doWork(): Result {
        showNotification()
        return Result.success()
    }

    private fun showNotification() {
        val notification = NotificationCompat.Builder(applicationContext, "heartshine_general")
            .setContentTitle("今天也辛苦了 💛")
            .setContentText("花一點時間記錄一下今天的心情吧。")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        NotificationManagerCompat.from(applicationContext).notify(1, notification)
    }
}
