pluginManagement {
    val flutterSdkPath =
        run {
            // local.properties создаёт flutter (`flutter pub get`, `flutter build`):
            // в нём не только flutter.sdk, но и flutter.versionCode/versionName, из
            // которых app/build.gradle.kts берёт версию APK. Прямой `./gradlew` с
            // чистого дерева поэтому не точка входа: он собрал бы сборку 1+1.
            val properties = java.util.Properties()
            val localProps = file("local.properties")
            if (!localProps.exists()) {
                error(
                    "Нет apps/main_app/android/local.properties — создай его " +
                        "`flutter pub get` в apps/main_app (там же flutter.sdk, " +
                        "flutter.versionCode и flutter.versionName).",
                )
            }
            localProps.inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.5.0") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// Ensure file_picker Android module is included (workaround for missing plugin class in registrant)
val flutterPluginDeps = file("../.flutter-plugins-dependencies")
if (flutterPluginDeps.exists()) {
    val depsText = flutterPluginDeps.readText()
    // file_picker 12+: Android-реализация федеративная — android_file_picker
    val regex = Regex("\"name\"\\s*:\\s*\"(android_file_picker|file_picker)\"[\\s\\S]*?\"path\"\\s*:\\s*\"([^\"]+)\"")
    val match = regex.find(depsText)
    val pluginPath = match?.groupValues?.get(2)
    val pluginName = match?.groupValues?.get(1)
    if (!pluginPath.isNullOrBlank() && !pluginName.isNullOrBlank()) {
        val androidDir = file("${pluginPath}/android")
        if (androidDir.exists()) {
            include(":$pluginName")
            project(":$pluginName").projectDir = androidDir
        }
    }
}
