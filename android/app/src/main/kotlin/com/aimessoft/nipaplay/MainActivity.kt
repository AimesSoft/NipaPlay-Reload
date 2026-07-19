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
import android.content.ClipData
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
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.SurfaceTexture
import android.view.WindowManager
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import java.security.MessageDigest

class MainActivity: FlutterActivity() {
    private val STORAGE_CHANNEL = "custom_storage_channel"
    private val FILE_SELECTOR_CHANNEL = "plugins.flutter.io/file_selector"
    private val SAF_CHANNEL = "nipaplay/android_saf"
    private val FILE_ASSOCIATION_CHANNEL = "file_association_channel"
    private val SYSTEM_SHARE_CHANNEL = "nipaplay/system_share"
    private val DEVICE_PROFILE_CHANNEL = "nipaplay/device_profile"
    private var fileAssociationChannel: MethodChannel? = null
    private var pendingOpenFilePath: String? = null
    private var lastDeliveredOpenUri: String? = null
    
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_PROFILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStartupDeviceProfile" -> {
                        val configuration = resources.configuration
                        result.success(
                            mapOf(
                                "isAndroidTv" to isAndroidTv(),
                                "screenWidthDp" to configuration.screenWidthDp,
                                "screenHeightDp" to configuration.screenHeightDp,
                                "smallestScreenWidthDp" to configuration.smallestScreenWidthDp,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> {
                        if (safDirectoryPickerResult != null) {
                            result.error("SAF_PICKER_BUSY", "A directory picker is already active", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                            }
                            safDirectoryPickerResult = result
                            startActivityForResult(intent, SAF_DIRECTORY_PICKER_REQUEST_CODE)
                        } catch (e: Exception) {
                            safDirectoryPickerResult = null
                            Log.e("MainActivity", "Error launching SAF directory picker", e)
                            result.error("SAF_PICKER_ERROR", e.message, null)
                        }
                    }
                    "scanDirectory" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "treeUri is required", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val entries = scanSafDirectory(treeUri)
                                runOnUiThread { result.success(entries) }
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Error scanning SAF directory", e)
                                runOnUiThread { result.error("SAF_SCAN_ERROR", e.message, null) }
                            }
                        }.start()
                    }
                    "getFileMetadata" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "uri is required", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val metadata = getSafFileMetadata(uri)
                                runOnUiThread { result.success(metadata) }
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Error reading SAF file metadata", e)
                                runOnUiThread { result.error("SAF_METADATA_ERROR", e.message, null) }
                            }
                        }.start()
                    }
                    "canAccessTree" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(canAccessSafTree(treeUri))
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error checking SAF tree access", e)
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        
        // 文件选择器通道 - 专用于优化视频文件选择，避免OOM - 现支持选择其他类型
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_SELECTOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFilePathOnly" -> {
                    if (filePickerResult != null) {
                        result.error(
                            "FILE_PICKER_BUSY",
                            "Another file picker request is already active",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val params = call.arguments as? Map<*, *>
                    var fileType = "video/*"
                    var mimeTypes = mutableListOf<String>()
                    val preserveContentUri = params?.get("preserveContentUri") as? Boolean ?: false
                    if (params != null) {
                        fileType = params["type"] as? String ?: "video/*"
                        params["extra_mime_types"]?.let { types ->
                            val typeList = types as List<*>
                            typeList.forEach { item ->
                                if (item is String) {
                                    mimeTypes.add(item)
                                }
                            }
                        }
                    }

                    try {
                        // 使用系统文件选择器，但只返回文件路径而不是内容
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = fileType
                            addCategory(Intent.CATEGORY_OPENABLE)
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                            )
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                        }
                        if(mimeTypes.isNotEmpty()) {
                            intent.putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                mimeTypes.toTypedArray()
                            )
                        }
                        
                        // 保存结果回调
                        filePickerResult = result
                        filePickerPreserveContentUri = preserveContentUri

                        // 启动文件选择器活动
                        startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
                    } catch (e: Exception) {
                        filePickerResult = null
                        filePickerPreserveContentUri = false
                        Log.e("MainActivity", "Error launching file picker", e)
                        result.error("FILE_PICKER_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 文件关联通道 - 处理从系统传入的文件
        fileAssociationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_ASSOCIATION_CHANNEL)
        fileAssociationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getOpenFileUri" -> {
                    val pending = pendingOpenFilePath
                    if (pending != null) {
                        pendingOpenFilePath = null
                        result.success(pending)
                        return@setMethodCallHandler
                    }
                    result.success(resolveOpenFileFromIntent(intent, allowDuplicate = false))
                }
                else -> result.notImplemented()
            }
        }

        // 系统分享通道 - iOS AirDrop / Android share sheet
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGUMENTS", "Arguments are required", null)
                        return@setMethodCallHandler
                    }

                    val text = args["text"] as? String
                    val url = args["url"] as? String
                    val filePath = args["filePath"] as? String
                    val explicitMimeType = args["mimeType"] as? String
                    val subject = args["subject"] as? String

                    val combinedText = listOfNotNull(
                        text?.takeIf { it.isNotBlank() },
                        url?.takeIf { it.isNotBlank() }
                    ).joinToString("\n")

                    val intent = Intent(Intent.ACTION_SEND)

                    var resolvedMimeType = explicitMimeType ?: "text/plain"
                    if (!filePath.isNullOrEmpty()) {
                        val parsedUri = Uri.parse(filePath)
                        if (ContentResolver.SCHEME_CONTENT == parsedUri.scheme) {
                            intent.putExtra(Intent.EXTRA_STREAM, parsedUri)
                            intent.clipData = ClipData.newRawUri("shared media", parsedUri)
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

                            if (explicitMimeType == null) {
                                resolvedMimeType = contentResolver.getType(parsedUri)
                                    ?: guessMimeTypeFromPath(filePath)
                                    ?: "application/octet-stream"
                            }
                        } else {
                            val file = File(filePath)
                            if (file.exists()) {
                                val uri = FileProvider.getUriForFile(
                                    this@MainActivity,
                                    "${this@MainActivity.packageName}.fileprovider",
                                    file
                                )
                                intent.putExtra(Intent.EXTRA_STREAM, uri)
                                intent.clipData = ClipData.newRawUri("shared media", uri)
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

                                if (explicitMimeType == null) {
                                    resolvedMimeType = guessMimeTypeFromPath(filePath)
                                        ?: "application/octet-stream"
                                }
                            }
                        }
                    }

                    if (combinedText.isNotBlank()) {
                        intent.putExtra(Intent.EXTRA_TEXT, combinedText)
                    }
                    if (!subject.isNullOrBlank()) {
                        intent.putExtra(Intent.EXTRA_SUBJECT, subject)
                    }

                    intent.type = resolvedMimeType

                    try {
                        startActivity(Intent.createChooser(intent, "分享"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAndroidTv(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTelevisionMode =
            uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val hasTvFeature =
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
        return isTelevisionMode || hasTvFeature
    }

    private fun guessMimeTypeFromPath(path: String): String? {
        val ext = path.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
    }
    
    // 覆盖onCreate以添加额外的配置，解决黑屏问题
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingOpenFilePath = resolveOpenFileFromIntent(intent, allowDuplicate = false)
        
        // 设置窗口属性，确保硬件加速启用
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
        
        // 确保硬件加速已启用
        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )

        // 请求最高刷新率：高刷屏（120Hz/90Hz）默认可能被系统限到 60Hz，
        // 导致 wgpu Surface vsync 跑 60Hz、get_current_texture 等 60Hz vsync
        // (~15ms/帧) -> 弹幕稳 60fps 冲不上去。显式请求最高刷新率 mode 让
        // Surface vsync 跑屏原生刷新率，弹幕才能 120fps（DFM+ render 本身
        // 仅 ~1ms，瓶颈完全是 acquire 等 vsync）。实测：双击触发的瞬时
        // 120fps 段 acquire 降到 0.04ms，证明渲染能力足够，只是被 60Hz 限。
        @Suppress("DEPRECATION")
        val disp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val modes = disp?.supportedModes
        if (!modes.isNullOrEmpty()) {
            val highRefreshMode = modes.maxByOrNull { it.refreshRate }
            if (highRefreshMode != null) {
                window.attributes = window.attributes.apply {
                    preferredDisplayModeId = highRefreshMode.modeId
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val filePath = resolveOpenFileFromIntent(intent, allowDuplicate = true)
        if (filePath == null) {
            return
        }

        pendingOpenFilePath = filePath
        fileAssociationChannel?.invokeMethod("onOpenFileUri", filePath)
    }
    
    // 文件选择请求码和结果回调
    private val FILE_PICKER_REQUEST_CODE = 9421
    private val SAF_DIRECTORY_PICKER_REQUEST_CODE = 9422
    private var filePickerResult: MethodChannel.Result? = null
    private var filePickerPreserveContentUri = false
    private var safDirectoryPickerResult: MethodChannel.Result? = null
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == SAF_DIRECTORY_PICKER_REQUEST_CODE && safDirectoryPickerResult != null) {
            if (resultCode == RESULT_OK && data != null && data.data != null) {
                val uri = data.data!!
                try {
                    val takeFlags = data.flags and (
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    val persistFlags = if (takeFlags != 0) {
                        takeFlags
                    } else {
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }
                    contentResolver.takePersistableUriPermission(uri, persistFlags)
                    safDirectoryPickerResult?.success(uri.toString())
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error persisting SAF directory permission", e)
                    safDirectoryPickerResult?.error("SAF_PERMISSION_ERROR", e.message, null)
                }
            } else {
                safDirectoryPickerResult?.success(null)
            }
            safDirectoryPickerResult = null
            return
        }

        if (requestCode == FILE_PICKER_REQUEST_CODE && filePickerResult != null) {
            val pendingResult = filePickerResult
            val preserveContentUri = filePickerPreserveContentUri
            filePickerResult = null
            filePickerPreserveContentUri = false

            if (resultCode == RESULT_OK && data != null && data.data != null) {
                val uri = data.data!!
                if (preserveContentUri && ContentResolver.SCHEME_CONTENT == uri.scheme) {
                    // Preserve video SAF sources so native backends can open
                    // the ContentResolver descriptor without copying media.
                    if (!persistReadPermissionIfAvailable(uri, data.flags)) {
                        Log.w(
                            "MainActivity",
                            "Selected media URI has only an ephemeral read grant; " +
                                "reopening it from history after process restart may fail: $uri"
                        )
                    }
                    pendingResult?.success(uri.toString())
                    return
                }
                val filePath = if (ContentResolver.SCHEME_CONTENT == uri.scheme) {
                    // Subtitle consumers still require an app-owned File path.
                    // A persisted SAF grant does not make provider _data paths
                    // readable under scoped storage, so copy these small files.
                    saveContentToCache(this, uri)
                } else {
                    getPathFromUri(this, uri)
                }
                if (filePath != null) {
                    // 返回文件路径给Flutter
                    pendingResult?.success(filePath)
                } else {
                    // 如果无法获取路径，返回错误
                    pendingResult?.error("PATH_RESOLUTION_FAILED", "Failed to resolve file path", null)
                }
            } else {
                // 用户取消选择
                pendingResult?.success(null)
            }
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
    private fun resolveOpenFileFromIntent(intent: Intent?, allowDuplicate: Boolean): String? {
        val uri = intent?.data ?: return null
        if (!allowDuplicate && uri.toString() == lastDeliveredOpenUri) {
            return null
        }

        if (ContentResolver.SCHEME_CONTENT == uri.scheme) {
            if (!persistReadPermissionIfAvailable(uri, intent.flags)) {
                Log.w(
                    "MainActivity",
                    "File association URI has only an ephemeral read grant; " +
                        "reopening it from history after process restart may fail: $uri"
                )
            }
            val mediaSource = uri.toString()
            Log.d("MainActivity", "File association: $mediaSource")
            lastDeliveredOpenUri = mediaSource
            return mediaSource
        }

        val filePath = getPathFromUri(this@MainActivity, uri)
        if (filePath != null) {
            Log.d("MainActivity", "File association: $filePath")
            lastDeliveredOpenUri = uri.toString()
            return filePath
        }

        Log.e("MainActivity", "Failed to resolve file path from URI: $uri")
        return null
    }

    private fun persistReadPermissionIfAvailable(uri: Uri, flags: Int): Boolean {
        val hasReadGrant = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0
        val isPersistable = flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0
        if (!hasReadGrant || !isPersistable) {
            return false
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            Log.d("MainActivity", "Persisted read permission for $uri")
            return true
        } catch (e: Exception) {
            Log.w("MainActivity", "Unable to persist read permission for $uri", e)
            return false
        }
    }

    private fun canAccessSafTree(treeUriString: String): Boolean {
        val treeUri = Uri.parse(treeUriString)
        val root = DocumentFile.fromTreeUri(this, treeUri) ?: return false
        return root.exists() && root.isDirectory && root.canRead()
    }

    private fun scanSafDirectory(treeUriString: String): List<Map<String, Any>> {
        val treeUri = Uri.parse(treeUriString)
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalArgumentException("Cannot open SAF tree URI: $treeUriString")
        if (!root.exists() || !root.isDirectory || !root.canRead()) {
            throw IllegalStateException("SAF tree is not readable: $treeUriString")
        }

        val output = mutableListOf<Map<String, Any>>()
        collectSafVideoFiles(root, "", output)
        return output.sortedBy { it["relativePath"] as String }
    }

    private fun collectSafVideoFiles(
        current: DocumentFile,
        relativePrefix: String,
        output: MutableList<Map<String, Any>>
    ) {
        for (entry in current.listFiles()) {
            val name = entry.name ?: continue
            val relativePath = if (relativePrefix.isEmpty()) {
                name
            } else {
                "$relativePrefix$name"
            }

            if (entry.isDirectory) {
                collectSafVideoFiles(entry, "$relativePath/", output)
                continue
            }

            if (!entry.isFile || !isSupportedVideoFileName(name)) {
                continue
            }

            val size = entry.length().coerceAtLeast(0L)
            val modifiedMillis = entry.lastModified().coerceAtLeast(0L)
            val fileHash = sha256Hex("$size|$modifiedMillis".toByteArray(Charsets.UTF_8))
                .take(16)

            output.add(
                mapOf(
                    "relativePath" to relativePath,
                    "uri" to entry.uri.toString(),
                    "name" to name,
                    "size" to size,
                    "modifiedMillis" to modifiedMillis,
                    "fileHash" to fileHash
                )
            )
        }
    }

    private fun isSupportedVideoFileName(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension == "mp4" || extension == "mkv"
    }

    private fun getSafFileMetadata(uriString: String): Map<String, Any> {
        val uri = Uri.parse(uriString)
        val name = queryDisplayName(uri) ?: uri.lastPathSegment ?: "video"
        val size = queryFileSize(uri).coerceAtLeast(0L)
        val contentHash = md5FirstBytes(uri, 16 * 1024 * 1024)

        return mapOf(
            "uri" to uriString,
            "name" to name,
            "size" to size,
            "contentHash" to contentHash
        )
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        return cursor.getString(index)
                    }
                }
            }
        return null
    }

    private fun queryFileSize(uri: Uri): Long {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0 && !cursor.isNull(index)) {
                        return cursor.getLong(index)
                    }
                }
            }

        return try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                descriptor.length
            } ?: 0L
        } catch (e: Exception) {
            0L
        }
    }

    private fun md5FirstBytes(uri: Uri, maxBytes: Int): String {
        val digest = MessageDigest.getInstance("MD5")
        contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(64 * 1024)
            var remaining = maxBytes
            while (remaining > 0) {
                val read = input.read(buffer, 0, minOf(buffer.size, remaining))
                if (read <= 0) {
                    break
                }
                digest.update(buffer, 0, read)
                remaining -= read
            }
        } ?: throw IllegalStateException("Cannot open SAF file: $uri")

        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun sha256Hex(input: ByteArray): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(input)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun getPathFromUri(context: Context, uri: Uri): String? {
        // 首先尝试使用DocumentFile
        if (DocumentsContract.isDocumentUri(context, uri)) {
            return getPathFromDocumentUri(context, uri)
        }
        
        // 如果是内容URI，尝试从MediaStore查询
        if (ContentResolver.SCHEME_CONTENT == uri.scheme) {
            return getDataColumn(context, uri, null, null)
                ?: saveContentToCache(context, uri)
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
                        val path = "${Environment.getExternalStorageDirectory()}/${split[1]}"
                        if (File(path).exists()) {
                            return path
                        }
                    }
                    
                    // 处理SD卡和其他外部存储
                    val externalDirs = ContextCompat.getExternalFilesDirs(context, null)
                    val firstExternalDir = externalDirs.firstOrNull()
                    if (firstExternalDir != null) {
                        val storagePath = firstExternalDir.absolutePath
                        val storageId = storagePath.substringBefore("/Android")
                        val path = "$storageId/${split[1]}"
                        if (File(path).exists()) {
                            return path
                        }
                    }
                }
            }
            
            // 处理媒体文件
            if (isMediaDocument(uri)) {
                val split = documentId.split(":")
                if (split.size >= 2) {
                    val mediaType = split[0]
                    val mediaId = split[1]
                    
                    val contentUri = when (mediaType.lowercase()) {
                        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else -> null
                    }

                    if (contentUri != null) {
                        val selection = "_id=?"
                        val selectionArgs = arrayOf(mediaId)
                        val path = getDataColumn(context, contentUri, selection, selectionArgs)
                        if (path != null) {
                            return path
                        }
                    }
                }
            }
            
            // 处理下载文件
            if (isDownloadsDocument(uri)) {
                // 首先尝试查询媒体数据库
                val contentUri = ContentResolver.SCHEME_CONTENT + "://downloads/public_downloads"
                val contentUriParsed = Uri.parse(contentUri)
                
                val path = getDataColumn(
                    context,
                    contentUriParsed,
                    "_id=?",
                    arrayOf(documentId)
                )
                if (path != null) {
                    return path
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error resolving document URI", e)
        }
        
        // 尝试直接从内容解析器获取文件名并保存到缓存目录
        return saveContentToCache(context, uri)
    }
    
    // 保存内容URI指向的文件到缓存目录并返回路径
    private fun saveContentToCache(context: Context, uri: Uri): String? {
        var outputFile: File? = null
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
            
            val extension = fileName
                ?.substringAfterLast('.', "")
                ?.takeIf { it.isNotBlank() }
                ?.let { ".$it" }
                ?: ".tmp"

            // 创建唯一缓存文件，避免失败重试误用上一次选择的旧内容。
            val cacheDir = context.externalCacheDir ?: context.cacheDir
            val cacheFile = File.createTempFile("nipaplay_picker_", extension, cacheDir)
            outputFile = cacheFile
            
            // 复制内容到缓存文件但不将整个文件加载到内存
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Cannot open selected content: $uri")
            input.use { source ->
                cacheFile.outputStream().use { output ->
                    val buffer = ByteArray(8 * 1024) // 8KB缓冲区
                    var bytesRead: Int
                    while (source.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                    }
                    output.flush()
                }
            }

            if (!cacheFile.exists() || cacheFile.length() <= 0L) {
                cacheFile.delete()
                Log.e("MainActivity", "Selected content was empty: $uri")
                return null
            }

            return cacheFile.absolutePath
        } catch (e: Exception) {
            outputFile?.delete()
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
