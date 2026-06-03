package com.kurenai7968.volume_controller

import android.media.AudioManager
import kotlin.math.round

class VolumeController(private val audioManager: AudioManager) {
    private var tempMuteVolume: Double?

    init {
        tempMuteVolume = null
    }

    fun setVolume(volume: Double, showSystemUI: Boolean) {
        val clampedVolume = volume.coerceIn(0.0, 1.0)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val adjustedVolume = (round(clampedVolume * maxVolume)).toInt()
        val flag = if (showSystemUI) AudioManager.FLAG_SHOW_UI else 0

        if (clampedVolume != 0.0) {
            tempMuteVolume = null
        }

        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, adjustedVolume, flag)
    }

    fun getVolume(): Double {
        return audioManager.getVolume()
    }

    fun isMute(): Boolean {
        return getVolume() == 0.0
    }

    fun setMute(isMute: Boolean, showSystemUI: Boolean) {
        if (isMute) {
            tempMuteVolume = getVolume()
            setVolume(0.0, showSystemUI)
        } else {
            val previousVolume = tempMuteVolume ?: return
            setVolume(previousVolume, showSystemUI)
            tempMuteVolume = null
        }
    }
}