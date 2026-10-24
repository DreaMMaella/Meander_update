package com.IILLUMINAT.meadner

import com.android.apksig.ApkSigner
import com.android.apksig.ApkVerifier
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.UnrecoverableKeyException
import java.security.cert.X509Certificate
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

// Платформенно-независимая часть офлайн-сборки APK: без android.* API,
// чтобы её можно было проверить на обычной JVM.

internal data class ApkBuildOptions(
    val manifest: BinaryManifestPatcher.Patch,
    val signing: SigningOptions,
    val v1: Boolean,
    val v2: Boolean,
    val v3: Boolean,
    /** Своя картинка иконки; `null` — оставить иконку шаблона. */
    val iconPath: String? = null,
) {
    companion object {
        private val PACKAGE_REGEX = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$")
        private val JAVA_KEYWORDS = setOf(
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
            "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
            "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "package", "private", "protected", "public",
            "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
            "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null",
        )

        fun isValidPackageName(value: String): Boolean =
            value.length <= 200 && PACKAGE_REGEX.matches(value) &&
                value.split('.').none { it in JAVA_KEYWORDS }
    }
}

internal sealed class SigningOptions {
    data class DeviceKey(
        val commonName: String?,
        val organization: String?,
        val country: String?,
        val validityYears: Int,
    ) : SigningOptions() {
        /** DN сертификата или `null`, если пользователь ничего не задал. */
        fun subject(): String? {
            val parts = buildList {
                commonName?.let { add("CN=" + escapeRdn(it)) }
                organization?.let { add("O=" + escapeRdn(it)) }
                country?.let { add("C=" + escapeRdn(it)) }
            }
            return parts.takeIf { it.isNotEmpty() }?.joinToString(", ")
        }

        private fun escapeRdn(value: String): String {
            val sb = StringBuilder()
            value.forEachIndexed { i, c ->
                val special = c in ",+\"\\<>;=" ||
                    (i == 0 && (c == '#' || c == ' ')) ||
                    (i == value.lastIndex && c == ' ')
                if (special) sb.append('\\')
                sb.append(c)
            }
            return sb.toString()
        }
    }

    data class Keystore(
        val path: String,
        val storePassword: String,
        val alias: String?,
        val keyPassword: String?,
    ) : SigningOptions()
}

internal object ApkRepacker {
    const val QUEST_ENTRY = "assets/flutter_assets/assets/quest/quest.mnd"
    private const val MANIFEST_ENTRY = "AndroidManifest.xml"
    private const val RESOURCES_ENTRY = "resources.arsc"
    private val RASTER_EXTENSIONS = listOf(".png", ".webp", ".jpg", ".jpeg")

    fun readManifestInfo(apk: File): BinaryManifestPatcher.Info =
        ZipFile(apk).use { zip ->
            val entry = zip.getEntry(MANIFEST_ENTRY) ?: error("В шаблоне нет AndroidManifest.xml")
            BinaryManifestPatcher.read(zip.getInputStream(entry).use { it.readBytes() })
        }

    /**
     * Растровые файлы иконки шаблона (android:icon / android:roundIcon) по всем
     * плотностям. Адаптивные XML-иконки сюда не попадают.
     */
    fun iconFiles(apk: File): List<ApkResourceTable.FileRef> =
        ZipFile(apk).use { zip ->
            val manifest = zip.getEntry(MANIFEST_ENTRY) ?: error("В шаблоне нет AndroidManifest.xml")
            val ids = BinaryManifestPatcher.iconResourceIds(zip.getInputStream(manifest).use { it.readBytes() })
            val arsc = zip.getEntry(RESOURCES_ENTRY)
            if (ids.isEmpty() || arsc == null) return@use emptyList<ApkResourceTable.FileRef>()
            ApkResourceTable.files(zip.getInputStream(arsc).use { it.readBytes() }, ids).filter { ref ->
                val path = ref.path.lowercase()
                RASTER_EXTENSIONS.any { path.endsWith(it) } &&
                    !path.endsWith(".9.png") &&
                    zip.getEntry(ref.path) != null
            }
        }

    /**
     * Перепаковывает шаблон и возвращает итоговый ID пакета.
     * [replacements] — файлы, содержимое которых подменяется целиком (иконки).
     */
    fun repack(
        template: File,
        questFile: File,
        output: File,
        patch: BinaryManifestPatcher.Patch,
        replacements: Map<String, ByteArray> = emptyMap(),
    ): String {
        var questReplaced = false
        var packageName: String? = null
        var replaced = 0

        ZipFile(template).use { zip ->
            ZipOutputStream(BufferedOutputStream(FileOutputStream(output), 1 shl 16)).use { out ->
                for (entry in zip.entries()) {
                    val name = entry.name
                    if (isSignatureEntry(name)) continue

                    when (name) {
                        QUEST_ENTRY -> {
                            out.putNextEntry(ZipEntry(name).apply { method = ZipEntry.DEFLATED })
                            questFile.inputStream().use { it.copyTo(out, 1 shl 16) }
                            out.closeEntry()
                            questReplaced = true
                        }
                        MANIFEST_ENTRY -> {
                            val original = zip.getInputStream(entry).use { it.readBytes() }
                            val patched = BinaryManifestPatcher.patch(original, patch)
                            val info = BinaryManifestPatcher.read(patched)
                            if (patch.packageName != null) {
                                check(info.packageName == patch.packageName) { "Не удалось записать ID пакета в манифест" }
                            }
                            if (patch.label != null) {
                                check(info.label == patch.label) { "Не удалось записать название в манифест" }
                            }
                            packageName = info.packageName
                            out.putNextEntry(ZipEntry(name).apply { method = ZipEntry.DEFLATED })
                            out.write(patched)
                            out.closeEntry()
                        }
                        in replacements.keys -> {
                            val data = replacements.getValue(name)
                            val checksum = CRC32().apply { update(data) }.value
                            // Как у aapt2: ресурсы-картинки лежат несжатыми.
                            out.putNextEntry(
                                ZipEntry(name).apply {
                                    method = ZipEntry.STORED
                                    size = data.size.toLong()
                                    compressedSize = data.size.toLong()
                                    crc = checksum
                                    time = entry.time
                                },
                            )
                            out.write(data)
                            out.closeEntry()
                            replaced++
                        }
                        else -> {
                            val copy = ZipEntry(name).apply {
                                method = entry.method
                                time = entry.time
                                if (entry.method == ZipEntry.STORED) {
                                    size = entry.size
                                    compressedSize = entry.size
                                    crc = entry.crc
                                }
                            }
                            out.putNextEntry(copy)
                            zip.getInputStream(entry).use { it.copyTo(out, 1 shl 16) }
                            out.closeEntry()
                        }
                    }
                }
            }
        }
        check(questReplaced) { "В шаблоне плеера нет файла квеста" }
        check(replaced == replacements.size) { "Не удалось заменить иконку в шаблоне плеера" }
        return packageName ?: error("В шаблоне нет AndroidManifest.xml")
    }

    private fun isSignatureEntry(name: String): Boolean {
        if (!name.startsWith("META-INF/")) return false
        val upper = name.uppercase()
        return upper == "META-INF/MANIFEST.MF" ||
            upper.endsWith(".SF") ||
            upper.endsWith(".RSA") ||
            upper.endsWith(".DSA") ||
            upper.endsWith(".EC")
    }
}

internal object ApkSigning {
    class Signer(val key: PrivateKey, val certificates: List<X509Certificate>)

    class Result(val packageName: String, val certificateSha256: String)

    fun keystoreSigner(options: SigningOptions.Keystore): Signer {
        val file = File(options.path)
        require(file.isFile) { "Файл keystore не найден" }
        val password = options.storePassword.toCharArray()

        var keyStore: KeyStore? = null
        for (type in listOf("PKCS12", "BKS", "JKS")) {
            try {
                keyStore = KeyStore.getInstance(type).apply { file.inputStream().use { load(it, password) } }
                break
            } catch (_: Exception) {
            }
        }
        val ks = requireNotNull(keyStore) {
            "Не удалось открыть keystore: неверный пароль или формат. Поддерживаются PKCS12 (.p12, .pfx, .jks из keytool) и BKS"
        }

        val aliases = ks.aliases().toList()
        // keytool в старых JDK приводил алиасы PKCS12 к нижнему регистру.
        val alias = options.alias?.let { wanted ->
            if (ks.containsAlias(wanted)) wanted
            else aliases.firstOrNull { it.equals(wanted, ignoreCase = true) }
                ?: throw IllegalArgumentException("В keystore нет алиаса «$wanted». Есть: ${aliases.joinToString()}")
        }
            ?: aliases.firstOrNull { ks.isKeyEntry(it) }
            ?: throw IllegalArgumentException("В keystore нет ключей")

        val rawKey = try {
            ks.getKey(alias, (options.keyPassword ?: options.storePassword).toCharArray())
        } catch (_: UnrecoverableKeyException) {
            throw IllegalArgumentException("Неверный пароль ключа «$alias»")
        }
        val key = rawKey as? PrivateKey
            ?: throw IllegalArgumentException("Алиас «$alias» не содержит закрытого ключа")

        val chain = ks.getCertificateChain(alias)?.map { it as X509Certificate }
            ?: listOfNotNull(ks.getCertificate(alias) as? X509Certificate)
        require(chain.isNotEmpty()) { "У ключа «$alias» нет сертификата" }
        return Signer(key, chain)
    }

    fun sign(input: File, output: File, signer: Signer, options: ApkBuildOptions, packageName: String): Result {
        require(options.v1 || options.v2) { "Включите подпись v1 или v2 — без них APK не установится на Android 7–8" }
        val config = ApkSigner.SignerConfig.Builder("CERT", signer.key, signer.certificates).build()
        ApkSigner.Builder(listOf(config))
            .setInputApk(input)
            .setOutputApk(output)
            .setV1SigningEnabled(options.v1)
            .setV2SigningEnabled(options.v2)
            .setV3SigningEnabled(options.v3)
            .build()
            .sign()
        verify(output)

        val digest = MessageDigest.getInstance("SHA-256").digest(signer.certificates.first().encoded)
        return Result(packageName, digest.joinToString(":") { "%02X".format(it) })
    }

    /** Офлайн-проверка подписи тем же apksig, что и у установщика: битый APK не отдаём пользователю. */
    private fun verify(apk: File) {
        val result = ApkVerifier.Builder(apk).build().verify()
        if (result.isVerified) return
        val issues = result.errors +
            result.v1SchemeSigners.flatMap { it.errors } +
            result.v2SchemeSigners.flatMap { it.errors } +
            result.v3SchemeSigners.flatMap { it.errors }
        apk.delete()
        error("Подписанный APK не прошёл проверку: " + issues.joinToString("; ").ifEmpty { "неизвестная ошибка" })
    }
}
