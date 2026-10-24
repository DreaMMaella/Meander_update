package com.IILLUMINAT.meadner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Готовит PNG иконки под каждую плотность шаблона: картинка центрируется,
 * обрезается до квадрата и масштабируется с фильтрацией.
 */
internal object QuestIconRenderer {
    private const val BASE_SIZE_DP = 48
    private const val DENSITY_DEFAULT = 0
    private const val DENSITY_MEDIUM = 160
    private const val DENSITY_ANY = 0xFFFE
    private const val DENSITY_NONE = 0xFFFF
    private const val MAX_SIZE = 512

    fun render(source: File, targets: List<ApkResourceTable.FileRef>): Map<String, ByteArray> {
        require(source.isFile) { "Файл иконки не найден — выберите её заново" }
        val sizes = targets.associateWith { sizeFor(it.density) }
        val square = loadSquare(source, sizes.values.max())
        try {
            val encoded = HashMap<Int, ByteArray>()
            return sizes.entries.associate { (ref, size) ->
                ref.path to encoded.getOrPut(size) { encodePng(square, size) }
            }
        } finally {
            square.recycle()
        }
    }

    private fun sizeFor(density: Int): Int = when (density) {
        DENSITY_DEFAULT -> BASE_SIZE_DP
        DENSITY_ANY, DENSITY_NONE -> 192
        else -> (BASE_SIZE_DP * density / DENSITY_MEDIUM).coerceIn(36, MAX_SIZE)
    }

    private fun loadSquare(source: File, targetSize: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "Не удалось прочитать иконку: поддерживаются PNG, JPG и WebP"
        }

        // Декодируем сразу уменьшенной копией: фото с камеры в полном размере
        // легко съедает сотни мегабайт.
        var sample = 1
        while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= targetSize) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            source.path,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: error("Не удалось прочитать иконку")

        val side = minOf(decoded.width, decoded.height)
        val matrix = exifRotation(source)
        val square = Bitmap.createBitmap(
            decoded,
            (decoded.width - side) / 2,
            (decoded.height - side) / 2,
            side,
            side,
            matrix,
            true,
        )
        if (square !== decoded) decoded.recycle()
        return square
    }

    private fun exifRotation(source: File): Matrix? {
        val degrees = try {
            when (
                ExifInterface(source.path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            ) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (_: Exception) {
            0f
        }
        return if (degrees == 0f) null else Matrix().apply { postRotate(degrees) }
    }

    private fun encodePng(square: Bitmap, size: Int): ByteArray {
        val scaled = Bitmap.createScaledBitmap(square, size, size, true)
        try {
            return ByteArrayOutputStream().use { out ->
                check(scaled.compress(Bitmap.CompressFormat.PNG, 100, out)) { "Не удалось сохранить иконку" }
                out.toByteArray()
            }
        } finally {
            if (scaled !== square) scaled.recycle()
        }
    }
}
