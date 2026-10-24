import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.JavaVersion

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Параметры квеста задаёт сборщик (scripts/build_quest_apk.sh) через
// ORG_GRADLE_PROJECT_<имя> или -P<имя>=...
fun questProperty(name: String): String? =
    (project.findProperty(name) as String?)?.takeIf { it.isNotBlank() }

val questAppId = questProperty("questAppId") ?: "sbs.meander.quest"
val questAppName = questProperty("questAppName") ?: "Meander Quest"
val questAbis = (questProperty("questAbis") ?: "arm64-v8a,armeabi-v7a,x86_64")
    .split(",")
    .map { it.trim() }
    .filter { it.isNotEmpty() }

// Своя иконка подменяет дефолтную целиком: два res-каталога с одинаковым
// ic_launcher.png в одном sourceSet дали бы «Duplicate resources».
val questIconFile = questProperty("questIcon")?.let { file(it) }?.takeIf { it.isFile }
val iconResDir: File =
    if (questIconFile != null) {
        val dir = layout.buildDirectory.dir("questIcon/res").get().asFile
        questIconFile.copyTo(File(dir, "mipmap-xxxhdpi/ic_launcher.png"), overwrite = true)
        dir
    } else {
        file("src/defaultIcon/res")
    }

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKeystore =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword").all {
        !keystoreProperties.getProperty(it).isNullOrBlank()
    }
if (!hasReleaseKeystore) {
    logger.warn(
        "key.properties нет: release-APK подписывается debug-ключом. " +
            "Для публикации создай android/key.properties.",
    )
}

val androidNdkVersion = "28.2.13676358"
val buildMndFfiAndroid = tasks.register("buildMndFfiAndroid") {
    group = "mnd"
    description = "Собирает libmnd_ffi.so из crates/mnd-ffi для ABI квеста."
    notCompatibleWithConfigurationCache("запускает cargo-ndk")
    doLast {
        val localProps = Properties()
        val sdkLocal = rootProject.file("local.properties")
        if (sdkLocal.exists()) sdkLocal.inputStream().use { localProps.load(it) }
        val sdkDir = localProps.getProperty("sdk.dir")
            ?: System.getenv("ANDROID_HOME")
            ?: error("Android SDK не найден: нет sdk.dir в local.properties и ANDROID_HOME пуст.")
        val ndkFromEnv = System.getenv("ANDROID_NDK_HOME")
            ?.let { file(it) }
            ?.takeIf { it.isDirectory }
        val ndkDir = ndkFromEnv ?: file("$sdkDir/ndk/$androidNdkVersion")
        if (!ndkDir.isDirectory) {
            error(
                "NDK $androidNdkVersion не установлен в $sdkDir/ndk — поставь его через " +
                    "sdkmanager или укажи ANDROID_NDK_HOME.",
            )
        }
        // directory — корень монорепы (app -> android -> quest_player -> apps -> корень).
        fun cargo(args: List<String>, quiet: Boolean): Int {
            val builder = ProcessBuilder(listOf("cargo") + args)
                .directory(file("../../../../"))
            val redirect =
                if (quiet) ProcessBuilder.Redirect.DISCARD else ProcessBuilder.Redirect.INHERIT
            builder.redirectOutput(redirect)
            builder.redirectError(redirect)
            builder.environment()["ANDROID_NDK_HOME"] = ndkDir.absolutePath
            return try {
                builder.start().waitFor()
            } catch (e: Exception) {
                -1
            }
        }
        if (cargo(listOf("ndk", "--version"), true) != 0) {
            error("Нужен cargo-ndk: cargo install cargo-ndk.")
        }
        val jniLibs = file("src/main/jniLibs")
        jniLibs.deleteRecursively()
        val code = cargo(
            listOf("ndk", "--platform", "24") +
                questAbis.flatMap { listOf("-t", it) } +
                listOf("-o", jniLibs.absolutePath, "build", "--release", "--locked", "-p", "mnd-ffi"),
            false,
        )
        if (code != 0) {
            error("cargo ndk завершился с кодом $code — APK без ядра не запустится.")
        }
    }
}

android {
    namespace = "sbs.meander.questplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = androidNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    sourceSets {
        getByName("main") {
            res.srcDir(iconResDir)
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = questAppId
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["questAppName"] = questAppName
        ndk {
            abiFilters.clear()
            abiFilters.addAll(questAbis)
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

tasks.named("preBuild") {
    dependsOn(buildMndFfiAndroid)
}
