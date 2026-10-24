package com.IILLUMINAT.meadner

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Правка скомпилированного (бинарного, AXML) AndroidManifest.xml шаблона
 * плеера: имя приложения, ID пакета, версия.
 *
 * Старые строки пула не трогаем — новые значения дописываются в конец пула,
 * и на них перенацеливаются только нужные атрибуты. Индексы существующих строк
 * и карта ресурсов атрибутов (resource map) при этом остаются валидными.
 */
internal object BinaryManifestPatcher {
    data class Patch(
        val packageName: String? = null,
        val label: String? = null,
        val versionCode: Int? = null,
        val versionName: String? = null,
    ) {
        val isEmpty: Boolean
            get() = packageName == null && label == null && versionCode == null && versionName == null
    }

    data class Info(val packageName: String?, val label: String?)

    private const val RES_STRING_POOL_TYPE = 0x0001
    private const val RES_XML_TYPE = 0x0003
    private const val RES_XML_START_ELEMENT_TYPE = 0x0102
    private const val RES_XML_RESOURCE_MAP_TYPE = 0x0180

    private const val UTF8_FLAG = 0x100
    private const val SORTED_FLAG = 0x1

    private const val TYPE_REFERENCE = 0x01
    private const val TYPE_STRING = 0x03
    private const val TYPE_INT_DEC = 0x10

    private const val ATTR_LABEL = 0x01010001
    private const val ATTR_ICON = 0x01010002
    private const val ATTR_ROUND_ICON = 0x0101052c

    private val ICON_ELEMENTS = setOf("application", "activity", "activity-alias")
    private const val ATTR_NAME = 0x01010003
    private const val ATTR_AUTHORITIES = 0x01010018
    private const val ATTR_TARGET_ACTIVITY = 0x01010202
    private const val ATTR_VERSION_CODE = 0x0101021b
    private const val ATTR_VERSION_NAME = 0x0101021c

    /** Элементы, у которых android:name — имя класса, а не строка пакета. */
    private val CLASS_NAME_ELEMENTS = setOf(
        "application", "activity", "activity-alias", "service",
        "receiver", "provider", "instrumentation",
    )

    private class Attr(val offset: Int, val nameIdx: Int, val resId: Int)

    private class Element(val name: String, val attrs: List<Attr>)

    private class Parsed(
        val bytes: ByteArray,
        val poolStart: Int,
        val poolEnd: Int,
        val isUtf8: Boolean,
        val flags: Int,
        val strings: MutableList<String>,
        val styleOffsets: IntArray,
        val styleData: ByteArray,
        val elements: List<Element>,
    )

    fun read(bytes: ByteArray): Info {
        val parsed = parse(bytes)
        var pkg: String? = null
        var label: String? = null
        for (el in parsed.elements) {
            for (attr in el.attrs) {
                val value = stringValue(parsed, attr) ?: continue
                if (el.name == "manifest" && attr.resId == 0 && parsed.strings[attr.nameIdx] == "package") pkg = value
                if (el.name == "application" && attr.resId == ATTR_LABEL) label = value
            }
        }
        return Info(pkg, label)
    }

    /** ID ресурсов android:icon / android:roundIcon приложения и его активностей. */
    fun iconResourceIds(bytes: ByteArray): List<Int> {
        val parsed = parse(bytes)
        val buf = ByteBuffer.wrap(parsed.bytes).order(ByteOrder.LITTLE_ENDIAN)
        val ids = LinkedHashSet<Int>()
        for (el in parsed.elements) {
            if (el.name !in ICON_ELEMENTS) continue
            for (attr in el.attrs) {
                if (attr.resId != ATTR_ICON && attr.resId != ATTR_ROUND_ICON) continue
                val dataType = parsed.bytes[attr.offset + 15].toInt() and 0xFF
                if (dataType != TYPE_REFERENCE) continue
                val id = buf.getInt(attr.offset + 16)
                if (id != 0) ids.add(id)
            }
        }
        return ids.toList()
    }

    fun patch(bytes: ByteArray, patch: Patch): ByteArray {
        if (patch.isEmpty) return bytes
        val parsed = parse(bytes)
        val out = parsed.bytes.copyOf()
        val buf = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        val appended = LinkedHashMap<String, Int>()

        fun indexOf(value: String): Int = appended.getOrPut(value) {
            parsed.strings.add(value)
            parsed.strings.size - 1
        }

        fun setString(attr: Attr, value: String) {
            val idx = indexOf(value)
            buf.putInt(attr.offset + 8, idx)
            buf.putShort(attr.offset + 12, 8.toShort())
            out[attr.offset + 14] = 0
            out[attr.offset + 15] = TYPE_STRING.toByte()
            buf.putInt(attr.offset + 16, idx)
        }

        val oldPackage = parsed.elements.firstOrNull { it.name == "manifest" }
            ?.attrs?.firstOrNull { it.resId == 0 && parsed.strings[it.nameIdx] == "package" }
            ?.let { stringValue(parsed, it) }
        val newPackage = patch.packageName?.takeIf { it != oldPackage }

        fun renamePackage(value: String): String? {
            if (oldPackage == null || newPackage == null) return null
            return when {
                value == oldPackage -> newPackage
                value.startsWith("$oldPackage.") -> newPackage + value.substring(oldPackage.length)
                else -> null
            }
        }

        for (el in parsed.elements) {
            for (attr in el.attrs) {
                val attrName = parsed.strings[attr.nameIdx]
                val value = stringValue(parsed, attr)

                if (el.name == "manifest" && attr.resId == 0 && attrName == "package") {
                    if (newPackage != null) setString(attr, newPackage)
                    continue
                }
                if (el.name == "manifest" && attr.resId == ATTR_VERSION_CODE && patch.versionCode != null) {
                    buf.putShort(attr.offset + 12, 8.toShort())
                    out[attr.offset + 14] = 0
                    out[attr.offset + 15] = TYPE_INT_DEC.toByte()
                    buf.putInt(attr.offset + 8, -1)
                    buf.putInt(attr.offset + 16, patch.versionCode)
                    continue
                }
                if (el.name == "manifest" && attr.resId == ATTR_VERSION_NAME && patch.versionName != null) {
                    setString(attr, patch.versionName)
                    continue
                }
                if (attr.resId == ATTR_LABEL && patch.label != null &&
                    (el.name == "application" || (el.name == "activity" && value != null))
                ) {
                    setString(attr, patch.label)
                    continue
                }
                if (value == null || newPackage == null) continue

                val isClassName = el.name in CLASS_NAME_ELEMENTS &&
                    (attr.resId == ATTR_NAME || attr.resId == ATTR_TARGET_ACTIVITY)
                if (isClassName) {
                    // Относительное имя класса резолвится от package манифеста —
                    // после смены пакета его нужно зафиксировать полным.
                    if (value.startsWith(".") && oldPackage != null) setString(attr, oldPackage + value)
                    continue
                }
                if (el.name == "meta-data") continue

                val renamed = if (attr.resId == ATTR_AUTHORITIES) {
                    val parts = value.split(';')
                    val mapped = parts.map { renamePackage(it) ?: it }
                    if (mapped == parts) null else mapped.joinToString(";")
                } else {
                    renamePackage(value)
                }
                if (renamed != null) setString(attr, renamed)
            }
        }

        val pool = encodePool(parsed)
        val result = ByteArrayOutputStream(out.size + pool.size)
        val header = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
        val totalSize = 8 + pool.size + (out.size - parsed.poolEnd)
        header.putShort(RES_XML_TYPE.toShort())
        header.putShort(8.toShort())
        header.putInt(totalSize)
        result.write(header.array())
        result.write(pool)
        result.write(out, parsed.poolEnd, out.size - parsed.poolEnd)
        return result.toByteArray()
    }

    private fun stringValue(parsed: Parsed, attr: Attr): String? {
        val buf = ByteBuffer.wrap(parsed.bytes).order(ByteOrder.LITTLE_ENDIAN)
        val dataType = parsed.bytes[attr.offset + 15].toInt() and 0xFF
        val raw = buf.getInt(attr.offset + 8)
        val idx = when {
            dataType == TYPE_STRING -> buf.getInt(attr.offset + 16)
            raw >= 0 && dataType != TYPE_REFERENCE -> raw
            else -> return null
        }
        return parsed.strings.getOrNull(idx)
    }

    private fun parse(bytes: ByteArray): Parsed {
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(bytes.size >= 8 && (buf.getShort(0).toInt() and 0xFFFF) == RES_XML_TYPE) {
            "AndroidManifest.xml шаблона не в бинарном формате"
        }
        val headerSize = buf.getShort(2).toInt() and 0xFFFF
        val fileSize = minOf(buf.getInt(4), bytes.size)

        val poolStart = headerSize
        require((buf.getShort(poolStart).toInt() and 0xFFFF) == RES_STRING_POOL_TYPE) {
            "Не найден пул строк манифеста"
        }
        val poolHeaderSize = buf.getShort(poolStart + 2).toInt() and 0xFFFF
        val poolSize = buf.getInt(poolStart + 4)
        val stringCount = buf.getInt(poolStart + 8)
        val styleCount = buf.getInt(poolStart + 12)
        val flags = buf.getInt(poolStart + 16)
        val stringsStart = buf.getInt(poolStart + 20)
        val stylesStart = buf.getInt(poolStart + 24)
        val isUtf8 = flags and UTF8_FLAG != 0
        val poolEnd = poolStart + poolSize

        val offsetsBase = poolStart + poolHeaderSize
        val strings = ArrayList<String>(stringCount + 8)
        for (i in 0 until stringCount) {
            val at = poolStart + stringsStart + buf.getInt(offsetsBase + i * 4)
            strings.add(if (isUtf8) decodeUtf8(bytes, at) else decodeUtf16(buf, at))
        }
        val styleOffsets = IntArray(styleCount) { buf.getInt(offsetsBase + stringCount * 4 + it * 4) }
        val styleData = if (styleCount > 0 && stylesStart > 0) {
            bytes.copyOfRange(poolStart + stylesStart, poolEnd)
        } else {
            ByteArray(0)
        }

        var resourceIds = IntArray(0)
        val elements = ArrayList<Element>()
        var pos = poolEnd
        while (pos + 8 <= fileSize) {
            val type = buf.getShort(pos).toInt() and 0xFFFF
            val chunkHeader = buf.getShort(pos + 2).toInt() and 0xFFFF
            val chunkSize = buf.getInt(pos + 4)
            if (chunkSize < 8) break
            when (type) {
                RES_XML_RESOURCE_MAP_TYPE -> {
                    val count = (chunkSize - chunkHeader) / 4
                    resourceIds = IntArray(count) { buf.getInt(pos + chunkHeader + it * 4) }
                }
                RES_XML_START_ELEMENT_TYPE -> {
                    val ext = pos + chunkHeader
                    val nameIdx = buf.getInt(ext + 4)
                    val attrStart = buf.getShort(ext + 8).toInt() and 0xFFFF
                    val attrSize = buf.getShort(ext + 10).toInt() and 0xFFFF
                    val attrCount = buf.getShort(ext + 12).toInt() and 0xFFFF
                    val attrs = ArrayList<Attr>(attrCount)
                    for (i in 0 until attrCount) {
                        val a = ext + attrStart + i * attrSize
                        val attrNameIdx = buf.getInt(a + 4)
                        val resId = if (attrNameIdx in resourceIds.indices) resourceIds[attrNameIdx] else 0
                        attrs.add(Attr(a, attrNameIdx, resId))
                    }
                    elements.add(Element(strings.getOrElse(nameIdx) { "" }, attrs))
                }
            }
            pos += chunkSize
        }

        return Parsed(
            bytes = bytes,
            poolStart = poolStart,
            poolEnd = poolEnd,
            isUtf8 = isUtf8,
            flags = flags,
            strings = strings,
            styleOffsets = styleOffsets,
            styleData = styleData,
            elements = elements,
        )
    }

    private fun encodePool(parsed: Parsed): ByteArray {
        val data = ByteArrayOutputStream()
        val offsets = IntArray(parsed.strings.size)
        for ((i, s) in parsed.strings.withIndex()) {
            offsets[i] = data.size()
            if (parsed.isUtf8) encodeUtf8(data, s) else encodeUtf16(data, s)
        }
        while (data.size() % 4 != 0) data.write(0)

        val headerSize = 28
        val stringCount = parsed.strings.size
        val styleCount = parsed.styleOffsets.size
        val stringsStart = headerSize + 4 * stringCount + 4 * styleCount
        val stylesStart = if (styleCount > 0) stringsStart + data.size() else 0
        val total = stringsStart + data.size() + parsed.styleData.size

        val buf = ByteBuffer.allocate(total).order(ByteOrder.LITTLE_ENDIAN)
        buf.putShort(RES_STRING_POOL_TYPE.toShort())
        buf.putShort(headerSize.toShort())
        buf.putInt(total)
        buf.putInt(stringCount)
        buf.putInt(styleCount)
        buf.putInt(parsed.flags and SORTED_FLAG.inv())
        buf.putInt(stringsStart)
        buf.putInt(stylesStart)
        offsets.forEach { buf.putInt(it) }
        parsed.styleOffsets.forEach { buf.putInt(it) }
        buf.put(data.toByteArray())
        buf.put(parsed.styleData)
        return buf.array()
    }

    internal fun decodeUtf8(bytes: ByteArray, start: Int): String {
        var pos = start
        fun readLen(): Int {
            val first = bytes[pos++].toInt() and 0xFF
            return if (first and 0x80 != 0) {
                ((first and 0x7F) shl 8) or (bytes[pos++].toInt() and 0xFF)
            } else {
                first
            }
        }
        readLen()
        val byteLen = readLen()
        return String(bytes, pos, byteLen, Charsets.UTF_8)
    }

    internal fun decodeUtf16(buf: ByteBuffer, start: Int): String {
        var pos = start
        var len = buf.getShort(pos).toInt() and 0xFFFF
        pos += 2
        if (len and 0x8000 != 0) {
            len = ((len and 0x7FFF) shl 16) or (buf.getShort(pos).toInt() and 0xFFFF)
            pos += 2
        }
        val chars = CharArray(len) { buf.getChar(pos + it * 2) }
        return String(chars)
    }

    private fun encodeUtf8(out: ByteArrayOutputStream, s: String) {
        val encoded = s.toByteArray(Charsets.UTF_8)
        require(s.length <= 0x7FFF && encoded.size <= 0x7FFF) { "Слишком длинная строка манифеста" }
        fun writeLen(len: Int) {
            if (len > 0x7F) {
                out.write(((len shr 8) and 0x7F) or 0x80)
                out.write(len and 0xFF)
            } else {
                out.write(len)
            }
        }
        writeLen(s.length)
        writeLen(encoded.size)
        out.write(encoded)
        out.write(0)
    }

    private fun encodeUtf16(out: ByteArrayOutputStream, s: String) {
        fun writeU16(v: Int) {
            out.write(v and 0xFF)
            out.write((v shr 8) and 0xFF)
        }
        val len = s.length
        if (len > 0x7FFF) {
            writeU16(((len shr 16) and 0x7FFF) or 0x8000)
            writeU16(len and 0xFFFF)
        } else {
            writeU16(len)
        }
        for (c in s) writeU16(c.code)
        writeU16(0)
    }
}
