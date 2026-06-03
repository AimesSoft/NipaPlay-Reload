package com.kurenai7968.volume_controller

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class VolumeControllerPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var volumeController: VolumeController
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val context = flutterPluginBinding.applicationContext
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val volumeListener = VolumeListener(context, audioManager)
    volumeController = VolumeController(audioManager)

    // Register EventChannel
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, ChannelName.EVENT_CHANNEL)
    eventChannel.setStreamHandler(volumeListener)

    // Register MethodChannel
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, ChannelName.METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      MethodName.GET_VOLUME -> {
        val volume = volumeController.getVolume()
        result.success(volume)
      }
      MethodName.SET_VOLUME -> {
        val volume: Double = call.argument(MethodArgument.VOLUME)!!
        val showSystemUI: Boolean = call.argument(MethodArgument.SHOW_SYSTEM_UI)!!

        volumeController.setVolume(volume, showSystemUI)
        result.success(null)
      }
      MethodName.IS_MUTED -> {
        val isMute = volumeController.isMute()
        result.success(isMute)
      }
      MethodName.SET_MUTE -> {
        val isMute: Boolean = call.argument(MethodArgument.IS_MUTE)!!
        val showSystemUI: Boolean = call.argument(MethodArgument.SHOW_SYSTEM_UI)!!

        volumeController.setMute(isMute, showSystemUI)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }
}