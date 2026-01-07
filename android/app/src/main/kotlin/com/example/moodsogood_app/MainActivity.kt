package tw.heartsshine.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.*
import java.util.concurrent.TimeUnit
import android.content.Context
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class MainActivity : FlutterActivity() {
    private val CHANNEL = "tw.heartsshine.app/workmanager"
    private lateinit var workManagerChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 確保 native notification channel 已建立（WorkManager native 通知會使用此 channel id）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "heartshine_general",
                "心晴提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "心晴的提醒與每日通知"
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
        // 確保 native side 的 notification channel 存在（Android O+）
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val name = "心晴提醒"
            val descriptionText = "心晴的提醒與每日通知"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel("heartshine_general", name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
        
        workManagerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        workManagerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleDailyNotification" -> {
                    val hour = call.argument<Int>("hour") ?: 22
                    val minute = call.argument<Int>("minute") ?: 0
                    val payload = call.argument<String>("payload") ?: "/daily"
                    scheduleDailyWork(hour, minute, payload)
                    result.success(true)
                }
                "cancelDailyNotification" -> {
                    WorkManager.getInstance(applicationContext).cancelUniqueWork("daily_reminder")
                    result.success(true)
                }
                "getInitialPayload" -> {
                    val payload = intent?.getStringExtra("payload")
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Update the activity intent so getIntent() returns latest
        setIntent(intent)
        // If there's a payload, notify Flutter via MethodChannel
        val payload = intent.getStringExtra("payload")
        if (payload != null) {
            try {
                workManagerChannel.invokeMethod("notificationTapped", payload)
            } catch (e: Exception) {
                // ignore if Flutter side not ready
            }
        }
    }

    private fun scheduleDailyWork(hour: Int, minute: Int, payload: String) {
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

        val inputData = androidx.work.Data.Builder()
            .putString("payload", payload)
            .build()

        val dailyWorkRequest = PeriodicWorkRequestBuilder<DailyReminderWorker>(
            24, TimeUnit.HOURS
        )
            .setInitialDelay(timeDiff, TimeUnit.MILLISECONDS)
            .setInputData(inputData)
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
        // Create an intent that reopens the app when the notification is tapped.
        val launchIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("notification_payload", "open_daily_record")
            }

        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                applicationContext,
                0,
                it,
                pendingFlags
            )
        }

        val notification = NotificationCompat.Builder(applicationContext, "heartshine_general")
            .setContentTitle("今天也辛苦了 💛")
            .setContentText("花一點時間記錄一下今天的心情吧。")
            .setSmallIcon(smallIcon)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        NotificationManagerCompat.from(applicationContext).notify(1, notification)
    }
}
