package com.kurenai7968.volume_controller

internal const val VOLUME_CHANGED_ACTION = "android.media.VOLUME_CHANGED_ACTION"

object ChannelName {
    const val METHOD_CHANNEL = "com.kurenai7968.volume_controller.method"
    const val EVENT_CHANNEL = "com.kurenai7968.volume_controller.volume_listener_event"
}

object MethodName {
    const val GET_VOLUME = "getVolume"
    const val SET_VOLUME = "setVolume"
    const val IS_MUTED = "isMuted"
    const val SET_MUTE = "setMute"
}

object MethodArgument {
    const val VOLUME = "volume"
    const val SHOW_SYSTEM_UI = "showSystemUI"
    const val IS_MUTE = "isMute"
}

object EventArgument {
    const val FETCH_INITIAL_VOLUME = "fetchInitialVolume"
}