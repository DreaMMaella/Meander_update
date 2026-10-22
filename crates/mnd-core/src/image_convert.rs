//! Конвертация картинок в WebP при импорте (#148).
//!
//! Квест весит в основном картинками, а PNG лежат в песочнице нетронутыми
//! вплоть до публикации. Здесь чистая функция над байтами — ничего не читает
//! и не пишет, поэтому вызывается и из FFI, и из тестов.
//!
//! В веб-сборке (фича `image-convert` выключена) `to_webp` возвращает `None`:
//! и `image`, и `webp` — C-криейты, а импортирует картинки всё равно редактор,
//! которого в браузере нет. Отсев по расширению остаётся общим, чтобы
//! вызывающий код не ветвился.

#[cfg(feature = "image-convert")]
use std::io::Cursor;

#[cfg(feature = "image-convert")]
use image::{GenericImageView, ImageReader};

/// Конвертируем статичные PNG: на них без потерь выходит 60–63 % исходника.
/// GIF не трогаем: декодер берёт из него первый кадр, и анимация исчезла бы
/// молча. JPEG тоже: сжатие без потерь раздувает его выше оригинала, а
/// потерянное качество фотографии — решение автора, не наша автоматика.
/// Пиксели при перекодировании PNG не меняются. Единственное исключение:
/// кодировщик обнуляет цвет там, где альфа равна нулю, а такой пиксел на
/// экране всё равно невидим.
pub fn is_convertible_image(file_name: &str) -> bool {
    extension(file_name) == "png"
}

/// Байты картинки → байты WebP. `None` — оставляем оригинал: формат не наш,
/// файл не декодируется, либо WebP вышел не меньше исходника.
pub fn to_webp(file_name: &str, bytes: &[u8]) -> Option<Vec<u8>> {
    if !is_convertible_image(file_name) || bytes.is_empty() {
        return None;
    }
    encode_png(bytes)
}

#[cfg(feature = "image-convert")]
fn encode_png(bytes: &[u8]) -> Option<Vec<u8>> {
    let image = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .decode()
        .ok()?;
    let (width, height) = image.dimensions();
    if width == 0 || height == 0 {
        return None;
    }
    let rgba = image.to_rgba8();
    let mut config = webp::WebPConfig::new().ok()?;
    config.lossless = 1;
    // При lossless это не «степень потерь», а усилие кодировщика: 100 —
    // максимальное сжатие, самое медленное. Импорт редкий и фоновый,
    // поэтому платим временем ради размера.
    config.quality = 100.0;
    let memory = webp::Encoder::from_rgba(rgba.as_raw(), width, height)
        .encode_advanced(&config)
        .ok()?;
    let encoded = memory.to_vec();
    if encoded.is_empty() || encoded.len() >= bytes.len() {
        return None;
    }
    Some(encoded)
}

/// Веб-сборка: кодировщика нет, оригинал остаётся оригиналом.
#[cfg(not(feature = "image-convert"))]
fn encode_png(_bytes: &[u8]) -> Option<Vec<u8>> {
    None
}

fn extension(file_name: &str) -> String {
    match file_name.rfind('.') {
        Some(i) => file_name[i + 1..].to_ascii_lowercase(),
        None => String::new(),
    }
}

#[cfg(all(test, feature = "image-convert"))]
mod tests {
    use super::*;
    use image::ImageEncoder;

    fn png_bytes(width: u32, height: u32, pixel: image::Rgba<u8>) -> Vec<u8> {
        let image = image::RgbaImage::from_pixel(width, height, pixel);
        let mut cursor = Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut cursor)
            .write_image(
                image.as_raw(),
                width,
                height,
                image::ExtendedColorType::Rgba8,
            )
            .expect("png кодируется");
        cursor.into_inner()
    }

    /// Градиент с плавающей альфой: то, чем автор закидывает библиотеку
    /// (скрины, оверлеи), а не однотонная заливка.
    fn gradient_png(side: u32) -> Vec<u8> {
        let image = image::RgbaImage::from_fn(side, side, |x, y| {
            image::Rgba([
                (x % 256) as u8,
                (y % 256) as u8,
                ((x + y) / 2 % 256) as u8,
                (x * 2 % 256) as u8,
            ])
        });
        let mut cursor = Cursor::new(Vec::new());
        image::codecs::png::PngEncoder::new(&mut cursor)
            .write_image(image.as_raw(), side, side, image::ExtendedColorType::Rgba8)
            .expect("png кодируется");
        cursor.into_inner()
    }

    #[test]
    fn only_static_png_is_converted() {
        assert!(is_convertible_image("cat.png"));
        assert!(is_convertible_image("CAT.PNG"));
        // JPEG без потерь только раздувается, гонять кодировщик впустую незачем.
        assert!(!is_convertible_image("CAT.JPG"));
        assert!(!is_convertible_image("photo.jpeg"));
        // Анимация, уже готовый формат и файлы без расширения.
        assert!(!is_convertible_image("ball.gif"));
        assert!(!is_convertible_image("cat.webp"));
        assert!(!is_convertible_image("notes.txt"));
        assert!(!is_convertible_image("no_extension"));
    }

    #[test]
    fn png_becomes_smaller_webp_and_keeps_pixels() {
        let source = gradient_png(96);
        let encoded = to_webp("sprite.png", &source).expect("конвертируется");
        assert_eq!(&encoded[0..4], b"RIFF");
        assert_eq!(&encoded[8..12], b"WEBP");
        assert!(
            encoded.len() < source.len(),
            "webp {} не меньше png {}",
            encoded.len(),
            source.len()
        );

        let decoded = webp::Decoder::new(&encoded)
            .decode()
            .expect("это читаемый webp");
        assert_eq!((decoded.width(), decoded.height()), (96, 96));
        // Сжатие без потерь. Оговорка одна: кодировщик обнуляет цвет там, где
        // альфа равна нулю (прозрачный пиксел всё равно не виден), поэтому
        // сравниваем пикселы целиком, а прозрачные — по одной лишь альфе.
        let original = ImageReader::new(Cursor::new(&source))
            .with_guessed_format()
            .unwrap()
            .decode()
            .unwrap()
            .to_rgba8();
        assert_eq!(decoded.as_chunks::<4>().0.len(), 96 * 96);
        assert!(
            decoded
                .as_chunks::<4>()
                .0
                .iter()
                .zip(original.as_raw().as_chunks::<4>().0)
                .all(|(a, b)| a == b || (a[3] == 0 && a[..3] == [0, 0, 0] && b[3] == 0)),
            "пиксели поехали"
        );
    }

    #[test]
    fn garbage_and_unconvertible_input_keep_the_original() {
        assert_eq!(to_webp("cat.png", &[]), None);
        assert_eq!(to_webp("cat.png", "не картинка совсем".as_bytes()), None);
        // Формат вне конвертации — даже валидный PNG внутри.
        let source = png_bytes(8, 8, image::Rgba([0, 0, 0, 255]));
        assert_eq!(to_webp("cat.gif", &source), None);
    }

    #[test]
    fn webp_never_comes_back_bigger() {
        // На крошечных картинках контейнер WebP может стоить дороже пикселов —
        // тогда возвращаем None и оставляем оригинал.
        for (i, side) in [1u32, 4, 32].iter().enumerate() {
            let source = png_bytes(*side, *side, image::Rgba([255, 0, 0, 255]));
            if let Some(encoded) = to_webp(&format!("dot{i}.png"), &source) {
                assert!(
                    encoded.len() < source.len(),
                    "{side}×{side}: webp {} не меньше png {}",
                    encoded.len(),
                    source.len()
                );
            }
        }
    }
}
