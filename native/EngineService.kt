package com.directionalaudio.directional_audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app process alive (a foreground service with a notification) so Android is less likely to
 * kill it together with the audio effects. It does not process audio by itself.
 * After a restart by the system it rebuilds the effects from the settings EngineHub saved.
 */
class EngineService : Service() {
    companion object {
        const val ACTION_STOP = "com.directionalaudio.directional_audio.STOP_ENGINE"
        private const val CHANNEL = "engine"
        private const val NOTIF_ID = 42
        private const val PREFS = "engine_state"
    }

    // the texts the notification shows (translated by the app)
    private var title = "Directional Audio"
    private var text = ""
    private var stopLabel = "Stop"
    private var bypassText = ""
    private var shownBypass: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        EngineHub.init(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A null intent means the system restarted the service after killing the process.
        EngineHub.logAdd("svc", "onStartCommand action=${intent?.action ?: "-"} systemRestart=${intent == null}")
        if (intent?.action == ACTION_STOP) {
            EngineHub.setWanted(false)
            stopSelf()
            return START_NOT_STICKY
        }

        // The texts come from the app (already translated); after a system restart there is no intent,
        // so the last ones are read back.
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        title = intent?.getStringExtra("title") ?: prefs.getString("n_title", null) ?: "Directional Audio"
        text = intent?.getStringExtra("text") ?: prefs.getString("n_text", null) ?: ""
        stopLabel = intent?.getStringExtra("stop") ?: prefs.getString("n_stop", null) ?: "Stop"
        bypassText = intent?.getStringExtra("bypass") ?: prefs.getString("n_bypass", null) ?: ""
        prefs.edit().putString("n_title", title).putString("n_text", text).putString("n_stop", stopLabel)
            .putString("n_bypass", bypassText).apply()

        try {
            shownBypass = EngineHub.bypass()
            val n = buildNotification(title, currentText(), stopLabel)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (e: Exception) {
            // For example Android 12+ refusing a foreground start from the background.
            stopSelf()
            return START_NOT_STICKY
        }

        EngineHub.stateListener = { b -> refreshNotification(b) }
        EngineHub.markService(true)
        EngineHub.restoreIfEmpty()
        EngineHub.watchRoutes()
        return START_STICKY
    }

    override fun onDestroy() {
        EngineHub.stateListener = null
        EngineHub.markService(false)
        super.onDestroy()
    }

    // While the sound is not being processed (bypass) the notification says so instead of "running".
    private fun currentText(): String =
        if (shownBypass != null && bypassText.isNotEmpty()) bypassText else text

    private fun refreshNotification(bypass: String?) {
        if (bypass == shownBypass) return
        shownBypass = bypass
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification(title, currentText(), stopLabel))
        } catch (ignored: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(title: String, text: String, stop: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val b: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
            b = Notification.Builder(this, CHANNEL)
        } else {
            b = Notification.Builder(this)
        }
        val pf = if (Build.VERSION.SDK_INT >= 23) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) b.setContentIntent(PendingIntent.getActivity(this, 0, open, pf))
        val stopIntent = PendingIntent.getService(
            this, 1, Intent(this, EngineService::class.java).setAction(ACTION_STOP), pf
        )
        b.setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, stop, stopIntent)
        return b.build()
    }
}
