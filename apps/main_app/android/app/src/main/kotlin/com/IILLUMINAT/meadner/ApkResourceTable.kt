package com.IILLUMINAT.meadner

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Минимальный читатель resources.arsc: по ID ресурса находит пути файлов
 * всех его конфигураций (плотностей).
 *
 * Пути берутся из таблицы, а не угадываются по имени: release-сборка может
 * сократить их (res/xY.png вместо res/mipmap-xxxhdpi-v4/ic_launcher.png).
 * Платформенно-независимый код — проверяется на обычной JVM.
 */
internal object ApkResourceTable {
    data class FileRef(val path: String, val density: Int)

    private const val RES_STRING_POOL_TYPE = 0x0001
    private const val RES_TABLE_TYPE = 0x0002
    private const val RES_TABLE_PACKAGE_TYPE = 0x0200
    private const val RES_TABLE_TYPE_TYPE = 0x0201

    private const val UTF8_FLAG = 0x100

    private const val TYPE_FLAG_SPARSE = 0x01
    private const val TYPE_FLAG_OFFSET16 = 0x02
    private const val ENTRY_FLAG_COMPLEX = 0x0001
    private const val ENTRY_FLAG_COMPACT = 0x0008

    private const val TYPE_REFERENCE = 0x01
    private const val TYPE_STRING = 0x03

    private const val MAX_REFERENCE_DEPTH = 4

    fun files(arsc: ByteArray, resIds: Collection<Int>): List<FileRef> {
        val table = Table.parse(arsc)
        val result = LinkedHashMap<String, FileRef>()

        fun resolve(id: Int, depth: Int) {
            if (depth > MAX_REFERENCE_DEPTH) return
            for (value in table.values(id)) {
                when (value.dataType) {
                    TYPE_STRING -> {
                        val path = table.globalString(value.data) ?: continue
                        result.putIfAbsent(path, FileRef(path, value.density))
                    }
                    TYPE_REFERENCE -> if (value.data != 0 && value.data != id) resolve(value.data, depth + 1)
                }
            }
        }

        resIds.forEach { resolve(it, 0) }
        return result.values.toList()
    }

    private class Value(val dataType: Int, val data: Int, val density: Int)

    private class TypeChunk(val packageId: Int, val offset: Int)

    private class Table(
        private val bytes: ByteArray,
        private val buf: ByteBuffer,
        private val globalPool: Int,
        private val types: List<TypeChunk>,
    ) {
        private fun u16(at: Int): Int = buf.getShort(at).toInt() and 0xFFFF

        fun values(resId: Int): List<Value> {
            val pkg = (resId ushr 24) and 0xFF
            val type = (resId ushr 16) and 0xFF
            val entry = resId and 0xFFFF
            val out = ArrayList<Value>()
            for (t in types) {
                if (t.packageId != pkg) continue
                if ((bytes[t.offset + 8].toInt() and 0xFF) != type) continue
                readEntry(t.offset, entry)?.let(out::add)
            }
            return out
        }

        private fun readEntry(c: Int, index: Int): Value? {
            val headerSize = u16(c + 2)
            val chunkEnd = minOf(c + buf.getInt(c + 4), bytes.size)
            val flags = bytes[c + 9].toInt() and 0xFF
            val entryCount = buf.getInt(c + 12)
            val entriesStart = buf.getInt(c + 16)
            // ResTable_config: size(4) mcc(2) mnc(2) language(2) country(2)
            // orientation(1) touchscreen(1) density(2).
            val density = u16(c + 20 + 14)
            val offsets = c + headerSize

            val offset = when {
                flags and TYPE_FLAG_SPARSE != 0 -> {
                    var found = -1
                    for (i in 0 until entryCount) {
                        val p = offsets + i * 4
                        if (p + 4 > chunkEnd) break
                        if (u16(p) == index) {
                            found = u16(p + 2) * 4
                            break
                        }
                    }
                    found
                }
                index >= entryCount -> -1
                flags and TYPE_FLAG_OFFSET16 != 0 ->
                    u16(offsets + index * 2).let { if (it == 0xFFFF) -1 else it * 4 }
                else -> buf.getInt(offsets + index * 4)
            }
            if (offset < 0) return null

            val e = c + entriesStart + offset
            if (e + 8 > chunkEnd) return null
            val entrySize = u16(e)
            val entryFlags = u16(e + 2)
            return when {
                entryFlags and ENTRY_FLAG_COMPACT != 0 ->
                    Value(entryFlags ushr 8, buf.getInt(e + 4), density)
                entryFlags and ENTRY_FLAG_COMPLEX != 0 -> null
                else -> {
                    val v = e + entrySize
                    if (v + 8 > chunkEnd) null
                    else Value(bytes[v + 3].toInt() and 0xFF, buf.getInt(v + 4), density)
                }
            }
        }

        fun globalString(index: Int): String? {
            val p = globalPool
            if (p < 0) return null
            val headerSize = u16(p + 2)
            val count = buf.getInt(p + 8)
            if (index !in 0 until count) return null
            val flags = buf.getInt(p + 16)
            val stringsStart = buf.getInt(p + 20)
            val at = p + stringsStart + buf.getInt(p + headerSize + index * 4)
            return if (flags and UTF8_FLAG != 0) {
                BinaryManifestPatcher.decodeUtf8(bytes, at)
            } else {
                BinaryManifestPatcher.decodeUtf16(buf, at)
            }
        }

        companion object {
            fun parse(bytes: ByteArray): Table {
                val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                fun u16(at: Int): Int = buf.getShort(at).toInt() and 0xFFFF
                require(bytes.size >= 12 && u16(0) == RES_TABLE_TYPE) { "resources.arsc шаблона повреждён" }

                var pool = -1
                val types = ArrayList<TypeChunk>()
                val end = minOf(buf.getInt(4), bytes.size)
                var pos = u16(2)
                while (pos + 8 <= end) {
                    val type = u16(pos)
                    val size = buf.getInt(pos + 4)
                    if (size < 8) break
                    when (type) {
                        RES_STRING_POOL_TYPE -> if (pool < 0) pool = pos
                        RES_TABLE_PACKAGE_TYPE -> {
                            val packageId = buf.getInt(pos + 8)
                            val packageEnd = minOf(pos + size, end)
                            var c = pos + u16(pos + 2)
                            while (c + 8 <= packageEnd) {
                                val childSize = buf.getInt(c + 4)
                                if (childSize < 8) break
                                if (u16(c) == RES_TABLE_TYPE_TYPE) types.add(TypeChunk(packageId, c))
                                c += childSize
                            }
                        }
                    }
                    pos += size
                }
                return Table(bytes, buf, pool, types)
            }
        }
    }
}
