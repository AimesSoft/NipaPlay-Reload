package com.aimessoft.nipaplay

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
import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import android.view.SurfaceHolder
import android.view.View
import android.app.ActivityManager
import android.graphics.SurfaceTexture
import android.view.WindowManager

class MainActivity: FlutterActivity() {
    private val STORAGE_CHANNEL = "custom_storage_channel"
    private val FILE_SELECTOR_CHANNEL = "plugins.flutter.io/file_selector"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 存储权限通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
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
                "checkDirectoryPermissions" -> {
                    val directoryPath = call.argument<String>("path") ?: ""
                    val directoryFile = File(directoryPath)
                    val checkResult = mapOf(
                        "exists" to directoryFile.exists(),
                        "canRead" to directoryFile.canRead(),
                        "canWrite" to directoryFile.canWrite()
                    )
                    result.success(checkResult)
                }
                "getAndroidSDKVersion" -> {
                    result.success(Build.VERSION.SDK_INT)
                }
                "checkExternalStorageDirectory" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(mapOf(
                            "exists" to false,
                            "canRead" to false,
                            "canWrite" to false
                        ))
                        return@setMethodCallHandler
                    }
                    
                    try {
                        val dir = File(path)
                        val canRead = dir.canRead()
                        val canWrite = dir.canWrite()
                        val exists = dir.exists()
                        
                        result.success(mapOf(
                            "canRead" to canRead,
                            "canWrite" to canWrite,
                            "exists" to exists
                        ))
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error checking directory", e)
                        result.error("DIRECTORY_CHECK_ERROR", e.message, null)
                    }
                }
                "clearMemory" -> {
                    try {
                        // 清理应用内存
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        activityManager.clearApplicationUserData()
                        System.gc()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "prepareSurface" -> {
                    try {
                        val id = call.argument<Int>("id")
                        if (id == null) {
                            result.error("INVALID_ARGUMENT", "Surface ID cannot be null", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.d("MainActivity", "Preparing surface for ID: $id")
                        
                        // 在主线程上运行
                        runOnUiThread {
                            try {
                                // 强制硬件加速
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
                                )
                                
                                Log.d("MainActivity", "Hardware acceleration enabled for surface")
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Error preparing surface", e)
                                result.error("SURFACE_PREPARE_ERROR", e.message, null)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error in prepareSurface", e)
                        result.error("PREPARE_SURFACE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 文件选择器通道 - 专用于优化视频文件选择，避免OOM
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_SELECTOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFilePathOnly" -> {
                    try {
                        // 使用系统文件选择器，但只返回文件路径而不是内容
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "video/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                        }
                        
                        // 启动文件选择器活动
                        startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
                        
                        // 保存结果回调
                        filePickerResult = result
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error launching file picker", e)
                        result.error("FILE_PICKER_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    // 覆盖onCreate以添加额外的配置，解决黑屏问题
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 设置窗口属性，确保硬件加速启用
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
        
        // 确保硬件加速已启用
        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )
    }
    
    // 文件选择请求码和结果回调
    private val FILE_PICKER_REQUEST_CODE = 9421
    private var filePickerResult: MethodChannel.Result? = null
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == FILE_PICKER_REQUEST_CODE && filePickerResult != null) {
            if (resultCode == RESULT_OK && data != null && data.data != null) {
                // 获取文件的真实路径
                val filePath = getPathFromUri(this, data.data!!)
                if (filePath != null) {
                    // 返回文件路径给Flutter
                    filePickerResult?.success(filePath)
                } else {
                    // 如果无法获取路径，返回错误
                    filePickerResult?.error("PATH_RESOLUTION_FAILED", "Failed to resolve file path", null)
                }
            } else {
                // 用户取消选择
                filePickerResult?.success(null)
            }
            // 清除回调引用
            filePickerResult = null
        }
    }
    
    // Surface创建完成的回调，用于处理MediaKit黑屏问题
    fun onMediaSurfaceTextureReady(surfaceTexture: SurfaceTexture?) {
        if (surfaceTexture != null) {
            // 设置缓冲区大小为视频分辨率
            surfaceTexture.setDefaultBufferSize(1280, 720)
        }
    }
    
    // 从URI获取实际文件路径的辅助方法
    private fun getPathFromUri(context: Context, uri: Uri): String? {
        // 首先尝试使用DocumentFile
        if (DocumentsContract.isDocumentUri(context, uri)) {
            return getPathFromDocumentUri(context, uri)
        }
        
        // 如果是内容URI，尝试从MediaStore查询
        if (ContentResolver.SCHEME_CONTENT == uri.scheme) {
            return getDataColumn(context, uri, null, null)
        }
        
        // 如果是文件URI，直接返回路径
        if (ContentResolver.SCHEME_FILE == uri.scheme) {
            return uri.path
        }
        
        return null
    }
    
    // 从文档URI获取路径
    private fun getPathFromDocumentUri(context: Context, uri: Uri): String? {
        try {
            val documentId = DocumentsContract.getDocumentId(uri)
            
            // 处理外部存储文档
            if (isExternalStorageDocument(uri)) {
                val split = documentId.split(":")
                if (split.size >= 2) {
                    val type = split[0]
                    
                    if ("primary".equals(type, ignoreCase = true)) {
                        return "${Environment.getExternalStorageDirectory()}/${split[1]}"
                    }
                    
                    // 处理SD卡和其他外部存储
                    val externalDirs = ContextCompat.getExternalFilesDirs(context, null)
                    if (externalDirs.isNotEmpty() && externalDirs[0] != null) {
                        val storagePath = externalDirs[0].absolutePath
                        val storageId = storagePath.substringBefore("/Android")
                        return "$storageId/${split[1]}"
                    }
                }
            }
            
            // 处理媒体文件
            if (isMediaDocument(uri)) {
                val split = documentId.split(":")
                if (split.size >= 2) {
                    val mediaType = split[0]
                    val mediaId = split[1]
                    
                    val contentUri = when (mediaType.toLowerCase()) {
                        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else -> return null
                    }
                    
                    val selection = "_id=?"
                    val selectionArgs = arrayOf(mediaId)
                    
                    return getDataColumn(context, contentUri, selection, selectionArgs)
                }
            }
            
            // 处理下载文件
            if (isDownloadsDocument(uri)) {
                // 首先尝试查询媒体数据库
                val contentUri = ContentResolver.SCHEME_CONTENT + "://downloads/public_downloads"
                val contentUriParsed = Uri.parse(contentUri)
                
                return getDataColumn(context, contentUriParsed, "_id=?", arrayOf(documentId))
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error resolving document URI", e)
        }
        
        // 尝试直接从内容解析器获取文件名并保存到缓存目录
        return saveContentToCache(context, uri)
    }
    
    // 保存内容URI指向的文件到缓存目录并返回路径
    private fun saveContentToCache(context: Context, uri: Uri): String? {
        try {
            // 获取文件名
            var fileName: String? = null
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        fileName = cursor.getString(nameIndex)
                    }
                }
            }
            
            if (fileName == null) {
                fileName = "video_${System.currentTimeMillis()}.mp4"
            }
            
            // 创建缓存文件
            val cacheDir = context.externalCacheDir ?: context.cacheDir
            val outputFile = File(cacheDir, fileName)
            
            // 复制内容到缓存文件但不将整个文件加载到内存
            context.contentResolver.openInputStream(uri)?.use { input ->
                outputFile.outputStream().use { output ->
                    val buffer = ByteArray(8 * 1024) // 8KB缓冲区
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                    output.flush()
                }
            }
            
            return outputFile.absolutePath
        } catch (e: Exception) {
            Log.e("MainActivity", "Error saving content to cache", e)
            return null
        }
    }
    
    // 从内容URI获取数据列
    private fun getDataColumn(context: Context, uri: Uri, selection: String?, selectionArgs: Array<String>?): String? {
        var cursor: Cursor? = null
        val column = "_data"
        val projection = arrayOf(column)
        
        try {
            cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, null)
            if (cursor != null && cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndexOrThrow(column)
                return cursor.getString(columnIndex)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error querying content resolver", e)
        } finally {
            cursor?.close()
        }
        
        return null
    }
    
    // 检查URI类型的辅助方法
    private fun isExternalStorageDocument(uri: Uri): Boolean {
        return "com.android.externalstorage.documents" == uri.authority
    }
    
    private fun isDownloadsDocument(uri: Uri): Boolean {
        return "com.android.providers.downloads.documents" == uri.authority
    }
    
    private fun isMediaDocument(uri: Uri): Boolean {
        return "com.android.providers.media.documents" == uri.authority
    }
} 