# Flutter-specific rules - CRITICAL: Keep ALL Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.engine.loader.** { *; }

# Keep FlutterLoader initialization
-keepclassmembers class io.flutter.embedding.engine.loader.FlutterLoader {
    private java.util.concurrent.Future initializationFuture;
    public void startInitialization(...);
    public void ensureInitializationComplete(...);
}

# --- ИЗМЕНЕНИЕ ЗДЕСЬ ---
# Keep your application's main activity with the new package name.
-keep class com.IILLUMINAT.meadner.MainActivity { *; }

# Keep MainApplication and its inner classes
-keep class com.IILLUMINAT.meadner.MainApplication { *; }
-keep class com.IILLUMINAT.meadner.MainApplication$** { *; }

# Keep FilePicker plugin (loaded via reflection)
-keep class com.mr.flutter.plugin.filepicker.FilePickerPlugin { *; }
-keepclassmembers class com.mr.flutter.plugin.filepicker.FilePickerPlugin {
    <init>();
}

# Keep other vital Android classes.
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.backup.BackupAgentHelper
-keep public class * extends android.preference.Preference
-keep public class com.android.vending.licensing.ILicensingService

# Yandex Mobile Ads SDK rules
-keep class com.yandex.mobile.ads.** { *; }
-keep interface com.yandex.mobile.ads.** { *; }
-dontwarn com.yandex.mobile.ads.**

# Yandex Login SDK (authsdk)
-keep class com.yandex.authsdk.** { *; }
-dontwarn com.yandex.authsdk.**

# Rule for Flutter's optional Play Core dependency.
-dontwarn com.google.android.play.core.**

# R8 missing class warnings from desugaring (safe to ignore)
-dontwarn java.util.Comparator$_CC
-dontwarn java.util.function.Function$_CC
-dontwarn java.util.function.IntUnaryOperator$_CC

# Keep MethodChannel handlers
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel$MethodCallHandler *;
}

# Keep classes loaded via reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}


