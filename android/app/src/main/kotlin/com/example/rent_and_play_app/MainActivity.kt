package com.example.rent_and_play_app

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("rental_updates", "Rental updates", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Booking approvals, requests and return updates"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
