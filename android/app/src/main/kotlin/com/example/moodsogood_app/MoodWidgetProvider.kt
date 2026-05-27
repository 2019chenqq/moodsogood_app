package tw.heartsshine.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MoodWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val subtitle = normalizedSubtitle(
                widgetData.getString("mood_widget_subtitle", null)
            )
            val views = RemoteViews(context.packageName, R.layout.mood_widget).apply {
                setTextViewText(
                    R.id.mood_widget_mood,
                    widgetData.getString("mood_widget_mood_text", "連續記錄 0 天")
                )
                setTextViewText(
                    R.id.mood_widget_subtitle,
                    subtitle
                )
                setTextViewText(
                    R.id.mood_widget_updated_at,
                    widgetData.getString("mood_widget_updated_at", "")
                )
                setOnClickPendingIntent(
                    R.id.mood_widget_root,
                    buildLaunchPendingIntent(context)
                )
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun normalizedSubtitle(rawSubtitle: String?): String {
        val subtitle = rawSubtitle?.trim().orEmpty()
        if (subtitle.isEmpty()) return "今天尚未紀錄"

        val isLegacyMoodScore =
            subtitle.contains("/10") || subtitle.startsWith("今日心情")
        return if (isLegacyMoodScore) "今天已完成紀錄" else subtitle
    }

    private fun buildLaunchPendingIntent(context: Context): PendingIntent? {
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("payload", "/daily")
            }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }

        return intent?.let {
            PendingIntent.getActivity(context, 1001, it, flags)
        }
    }
}
