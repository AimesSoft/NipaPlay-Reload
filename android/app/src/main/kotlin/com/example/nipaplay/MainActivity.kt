package com.example.nipaplay

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "custom_storage_channel"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestManageExternalStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            val uri = Uri.fromParts("package", packageName, null)
                            intent.data = uri
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error requesting MANAGE_EXTERNAL_STORAGE permission", e)
                            try {
                                // 尝试打开普通应用设置页面
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                val uri = Uri.fromParts("package", packageName, null)
                                intent.data = uri
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Error opening app settings", e)
                                result.success(false)
                            }
                        }
                    } else {
                        // 低于 Android 11 不需要特殊处理
                        result.success(true)
                    }
                }
                "checkManageExternalStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true) // 低于 Android 11 返回true
                    }
                }
                "checkExternalStorageDirectory" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        val dir = File(path)
                        val canRead = dir.canRead()
                        val canWrite = dir.canWrite()
                        val exists = dir.exists()
                        
                        val map = HashMap<String, Any>()
                        map["canRead"] = canRead
                        map["canWrite"] = canWrite
                        map["exists"] = exists
                        
                        result.success(map)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error checking directory", e)
                        result.error("DIRECTORY_CHECK_ERROR", e.message, null)
                    }
                }
                "getAndroidSDKVersion" -> {
                    result.success(Build.VERSION.SDK_INT)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
