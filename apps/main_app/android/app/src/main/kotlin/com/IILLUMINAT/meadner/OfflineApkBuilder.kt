package com.IILLUMINAT.meadner

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Date
import javax.security.auth.x500.X500Principal
import kotlin.concurrent.thread

/**
 * Офлайн-сборка APK квеста без Flutter/SDK.
 *
 * В приложение при сборке CI вшивается готовый APK плеера (apps/quest_player).
 * Здесь в его копии подменяется файл квеста, правится бинарный манифест
 * (имя, ID пакета, версия), старая подпись удаляется, и APK заново
 * подписывается — ключом устройства из AndroidKeyStore или своим keystore.
 */
object OfflineApkBuilder {
    const val CHANNEL = "meander/offline_apk"

    private const val TEMPLATE_ASSET = "quest_player_template.apk"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    /** Алиас ключа по умолчанию — тот же, что в прошлых версиях, чтобы APK обновлялись. */
    private const val DEFAULT_KEY_ALIAS = "meander_offline_quest_signer"
    private const val DEFAULT_SUBJECT = "CN=Meander Offline Quest"
    private const val DEFAULT_VALIDITY_YEARS = 30

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        val mainHandler = Handler(Looper.getMainLooper())

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isAvailable(appContext))
                "templateInfo" -> thread(name = "offline-apk-info") {
                    try {
                        val info = templateInfo(appContext)
                        mainHandler.post {
                            result.success(mapOf("packageName" to info.packageName, "label" to info.label))
                        }
                    } catch (e: Throwable) {
                        mainHandler.post { result.error("info_failed", e.message ?: e.javaClass.simpleName, null) }
                    }
                }
                "build" -> {
                    val questPath = call.argument<String>("questPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (questPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("invalid_args", "questPath/outputPath missing", null)
                        return@setMethodCallHandler
                    }
                    val options = try {
                        parseOptions(call.argument<Map<String, Any?>>("options") ?: emptyMap())
                    } catch (e: IllegalArgumentException) {
                        result.error("invalid_args", e.message, null)
                        return@setMethodCallHandler
                    }
                    thread(name = "offline-apk-builder") {
                        try {
                            val built = build(appContext, File(questPath), File(outputPath), options)
                            mainHandler.post {
                                result.success(
                                    mapOf(
                                        "path" to outputPath,
                                        "packageName" to built.packageName,
                                        "certificateSha256" to built.certificateSha256,
                                    ),
                                )
                            }
                        } catch (e: Throwable) {
                            val message = e.message ?: e.javaClass.simpleName
                            mainHandler.post { result.error("build_failed", message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            context.assets.list("")?.contains(TEMPLATE_ASSET) == true
        } catch (_: Exception) {
            false
        }
    }

    private fun templateInfo(context: Context): BinaryManifestPatcher.Info {
        check(isAvailable(context)) { "Шаблон плеера не встроен в эту сборку приложения" }
        val template = copyTemplate(context)
        try {
            return ApkRepacker.readManifestInfo(template)
        } finally {
            template.delete()
        }
    }

    private fun build(context: Context, questFile: File, output: File, options: ApkBuildOptions): ApkSigning.Result {
        check(isAvailable(context)) { "Шаблон плеера не встроен в эту сборку приложения" }
        require(questFile.isFile) { "Файл квеста не найден" }

        val workDir = File(context.cacheDir, "offline_apk").apply { mkdirs() }
        val template = copyTemplate(context)
        val unsigned = File(workDir, "unsigned_${System.nanoTime()}.apk")

        try {
            val iconReplacements = options.iconPath?.let { path ->
                val targets = ApkRepacker.iconFiles(template)
                check(targets.isNotEmpty()) { "В шаблоне плеера не найдена иконка для замены" }
                QuestIconRenderer.render(File(path), targets)
            } ?: emptyMap()
            val packageName = ApkRepacker.repack(
                template,
                questFile,
                unsigned,
                options.manifest,
                iconReplacements,
            )
            output.parentFile?.mkdirs()
            val signer = when (val s = options.signing) {
                is SigningOptions.DeviceKey -> deviceSigner(s)
                is SigningOptions.Keystore -> ApkSigning.keystoreSigner(s)
            }
            return ApkSigning.sign(unsigned, output, signer, options, packageName)
        } finally {
            template.delete()
            unsigned.delete()
        }
    }

    private fun copyTemplate(context: Context): File {
        val workDir = File(context.cacheDir, "offline_apk").apply { mkdirs() }
        val template = File(workDir, "template_${System.nanoTime()}.apk")
        context.assets.open(TEMPLATE_ASSET).use { input ->
            FileOutputStream(template).use { input.copyTo(it) }
        }
        return template
    }

    private fun parseOptions(map: Map<String, Any?>): ApkBuildOptions {
        fun str(key: String): String? = (map[key] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        fun bool(key: String, default: Boolean): Boolean = map[key] as? Boolean ?: default
        fun int(key: String): Int? = (map[key] as? Number)?.toInt()

        val packageName = str("packageName")
        if (packageName != null) {
            require(ApkBuildOptions.isValidPackageName(packageName)) {
                "Некорректный ID пакета: $packageName"
            }
        }
        val versionCode = int("versionCode")
        if (versionCode != null) require(versionCode in 1..2_100_000_000) { "Код версии должен быть от 1 до 2100000000" }

        val signing = when (str("signingMode") ?: "device") {
            "keystore" -> SigningOptions.Keystore(
                path = str("keystorePath") ?: throw IllegalArgumentException("Не выбран файл keystore"),
                storePassword = map["storePassword"] as? String ?: "",
                alias = str("keyAlias"),
                keyPassword = (map["keyPassword"] as? String)?.takeIf { it.isNotEmpty() },
            )
            else -> {
                val country = str("certCountry")
                if (country != null) require(country.length == 2) { "Код страны — две буквы (RU, US…)" }
                SigningOptions.DeviceKey(
                    commonName = str("certCommonName"),
                    organization = str("certOrganization"),
                    country = country?.uppercase(),
                    validityYears = (int("certValidityYears") ?: DEFAULT_VALIDITY_YEARS).coerceIn(1, 100),
                )
            }
        }

        val v1 = bool("v1", false)
        val v2 = bool("v2", true)
        val v3 = bool("v3", false)
        require(v1 || v2 || v3) { "Нужна хотя бы одна схема подписи" }

        return ApkBuildOptions(
            manifest = BinaryManifestPatcher.Patch(
                packageName = packageName,
                label = str("appName"),
                versionCode = versionCode,
                versionName = str("versionName"),
            ),
            signing = signing,
            v1 = v1,
            v2 = v2,
            v3 = v3,
            iconPath = str("iconPath"),
        )
    }

    private fun deviceSigner(options: SigningOptions.DeviceKey): ApkSigning.Signer {
        val subject = options.subject() ?: DEFAULT_SUBJECT
        val isDefault = subject == DEFAULT_SUBJECT && options.validityYears == DEFAULT_VALIDITY_YEARS
        val alias = if (isDefault) {
            DEFAULT_KEY_ALIAS
        } else {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("$subject|${options.validityYears}".toByteArray())
            "meander_signer_" + digest.take(8).joinToString("") { "%02x".format(it) }
        }

        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (!keyStore.containsAlias(alias)) {
            val now = System.currentTimeMillis()
            val validity = options.validityYears * 365L * 24 * 60 * 60 * 1000
            val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setCertificateSubject(X500Principal(subject))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - 24L * 60 * 60 * 1000))
                .setCertificateNotAfter(Date(now + validity))
                .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEYSTORE).apply {
                initialize(spec)
                generateKeyPair()
            }
        }
        val entry = keyStore.getEntry(alias, null) as KeyStore.PrivateKeyEntry
        return ApkSigning.Signer(entry.privateKey, listOf(entry.certificate as java.security.cert.X509Certificate))
    }
}
