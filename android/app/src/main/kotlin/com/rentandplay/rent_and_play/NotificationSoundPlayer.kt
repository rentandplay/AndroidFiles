package com.rentandplay.rent_and_play

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper

class NotificationSoundPlayer(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "rental_updates"
        fun audioAttributes(): AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }

    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private val stopSound = Runnable { stop() }

    fun play(): Boolean {
        try {
            val audio = context.getSystemService(AudioManager::class.java)
            val manager = context.getSystemService(NotificationManager::class.java)
            if (!manager.areNotificationsEnabled() ||
                audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
                manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
            ) return false
            val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.getNotificationChannel(CHANNEL_ID)
            } else null
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) return false
            // Use the channel's chosen tone, including the user's Silent setting.
            val uri = if (channel != null) channel.sound else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            if (uri == null) return false
            stop()
            val tone = RingtoneManager.getRingtone(context, uri) ?: return false
            tone.audioAttributes = channel?.audioAttributes ?: audioAttributes()
            ringtone = tone
            tone.play()
            handler.postDelayed(stopSound, 3000)
            return true
        } catch (_: RuntimeException) {
            stop()
            return false
        }
    }

    fun stop() {
        handler.removeCallbacks(stopSound)
        ringtone?.stop()
        ringtone = null
    }
}
