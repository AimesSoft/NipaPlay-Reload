# Flutter通用规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 保留Flutter框架内核
-keep class io.flutter.embedding.engine.** { *; }

# 保留Media Kit相关类
-keep class com.alexmercerind.media_kit.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.classycode.mpv.** { *; }

# 保留FileSelector相关类
-keep class dev.flutter.packages.file_selector_android.** { *; }

# 避免对Dart框架进行代码混淆
-keep class org.dartlang.** { *; }

# Kotlin相关类保留
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }

# 避免混淆序列化类
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 避免混淆自定义组件
-keep public class com.aimessoft.nipaplay.** { *; }
-keep public class com.example.nipaplay.** { *; }

# MultiDex相关
-keep class androidx.multidex.** { *; }

# 解决OOM相关优化
-dontpreverify
-repackageclasses
-allowaccessmodification
-optimizations !code/simplification/arithmetic
-keepattributes *Annotation*

# 减少日志输出以节省内存
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# 禁止注解引起的警告
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn org.bouncycastle.jsse.BCSSLParameters
-dontwarn org.bouncycastle.jsse.BCSSLSocket
-dontwarn org.conscrypt.Conscrypt

# 文件选择器优化
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.content.FileProvider$SimplePathStrategy { *; }

# Keep rules for Google Play Core Library
-keep class com.google.android.play.core.** { *; }
-keep interface com.google.android.play.core.** { *; } 