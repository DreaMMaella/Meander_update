// Регрессия на жалобу «к посту в сообществе не прикрепляется фото»: клиент
// Meander (`package:http`) объявляет часть multipart как
// `application/octet-stream`, если тип не заполнить вручную. Прежний
// `fileFilter` требовал `image/*` и отвечал 400 настоящим фотографиям со всех
// устройств.
//
// Негативный контроль: первый тест падает, если в image_host.ts снова
// потребовать mime из заголовка части; второй — если checkMagicBytes
// перестанет различать отказ по содержимому.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
    acceptsImagePartMime,
    UnsupportedImageError,
    uploadImage,
} = require('../dist/services/image_host.js');

test('заявленный тип части: картинка и «не знаю» проходят, не-картинка нет', () => {
    assert.equal(acceptsImagePartMime('application/octet-stream'), true);
    assert.equal(acceptsImagePartMime('binary/octet-stream'), true);
    assert.equal(acceptsImagePartMime(''), true);
    assert.equal(acceptsImagePartMime(undefined), true);
    assert.equal(acceptsImagePartMime('image/png'), true);
    assert.equal(acceptsImagePartMime('IMAGE/JPEG'), true);

    assert.equal(acceptsImagePartMime('application/pdf'), false);
    assert.equal(acceptsImagePartMime('text/html'), false);
});

test('файл не-картинка отклоняется по содержимому, а не по заголовку', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mnd-upload-mime-test-'));
    const fake = path.join(dir, 'photo.jpg'); // расширение разрешено, байты — нет
    fs.writeFileSync(fake, Buffer.from('<?xml version="1.0"?><svg/>'));

    await assert.rejects(uploadImage(fake), (err) => {
        assert.ok(err instanceof UnsupportedImageError, `typ: ${err.name}`);
        return true;
    });

    fs.rmSync(dir, { recursive: true, force: true });
});

test('настоящий JPEG проходит и получает ссылку', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mnd-upload-mime-test-'));
    const real = path.join(dir, 'photo.jpg');
    fs.writeFileSync(
        real,
        Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x00, 0xff, 0xd9])
    );

    const url = await uploadImage(real);
    assert.match(url, /^https?:\/\/.+\/uploads\/[0-9a-f-]+\.jpg$/);

    // uploadImage копирует файл в public/uploads — тест не оставляет после
    // себя артефакт.
    fs.rmSync(path.join(process.cwd(), 'public/uploads', path.basename(url)), { force: true });
    fs.rmSync(dir, { recursive: true, force: true });
});
