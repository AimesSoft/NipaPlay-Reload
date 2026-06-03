package com.kurenai7968.volume_controller

import android.media.AudioManager
import kotlin.math.round

internal fun AudioManager.getVolume(): Double {
    val currentVolume = getStreamVolume(AudioManager.STREAM_MUSIC)
    val maxVolume = getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    return round((currentVolume / maxVolume.toDouble()) * 10000) / 10000
}