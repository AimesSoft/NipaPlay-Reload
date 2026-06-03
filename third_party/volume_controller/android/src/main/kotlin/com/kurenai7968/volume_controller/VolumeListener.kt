package com.kurenai7968.volume_controller

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import io.flutter.plugin.common.EventChannel

class VolumeListener(private val context: Context, private val audioManager: AudioManager) : EventChannel.StreamHandler {
    private lateinit var volumeBroadcastReceiver: VolumeBroadcastReceiver

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val args = arguments as? Map<String, Any>
        val fetchInitialVolume = args?.get(EventArgument.FETCH_INITIAL_VOLUME) as? Boolean ?: false

        volumeBroadcastReceiver = VolumeBroadcastReceiver(events, audioManager)
        context.registerReceiver(volumeBroadcastReceiver, IntentFilter(VOLUME_CHANGED_ACTION))

        if (fetchInitialVolume) {
            events?.success(audioManager.getVolume())
        }
    }

    override fun onCancel(arguments: Any?) {
        context.unregisterReceiver(volumeBroadcastReceiver)
    }
}

class VolumeBroadcastReceiver(private val events: EventChannel.EventSink?, private val audioManager: AudioManager) : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        events?.success(audioManager.getVolume())
    }
}