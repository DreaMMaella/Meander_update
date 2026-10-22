//! FFI-слой конвертации картинок в WebP при импорте (#148).
//!
//! Логика целиком в `mnd_core::image_convert` — здесь только пронос байтов
//! через границу Dart↔Rust, чтобы Dart не перекодировал картинки сам.

use mnd_core::image_convert;

/// Стоит ли пытать конвертировать файл с таким именем (PNG, не GIF/JPEG).
pub fn image_is_convertible(file_name: String) -> bool {
    image_convert::is_convertible_image(&file_name)
}

/// PNG → lossless WebP. `null` означает «оставь оригинал»: формат не наш,
/// файл не декодируется либо WebP вышел не меньше исходника.
pub fn image_to_webp(file_name: String, bytes: Vec<u8>) -> Option<Vec<u8>> {
    image_convert::to_webp(&file_name, &bytes)
}
