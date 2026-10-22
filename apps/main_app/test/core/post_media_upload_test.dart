import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/post_media_service.dart';

/// Фото с телефона: сервер смотрит на сигнатуру байт, поэтому в файле лежит
/// настоящий JPEG-заголовок, а не случайные байты.
final _jpegBytes = Uint8List.fromList([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x00, 0xff, 0xd9,
]);

/// Клиент-подставка: запоминает, что именно улетело на сервер, и отвечает
/// заранее подготовленным кодом и телом.
class _Capture {
  String? rawBody;
  http.BaseRequest? request;
  bool called = false;
}

http.Client _capturing(
  _Capture capture, {
  int status = 200,
  String body = '{"url":"https://cdn.mnd/f.jpg"}',
}) {
  return MockClient.streaming((request, bodyStream) async {
    capture.called = true;
    capture.request = request;
    capture.rawBody = utf8.decode(await bodyStream.toBytes(), allowMalformed: true);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(body)),
      status,
    );
  });
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mnd_post_media');
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<XFile> galleryFile(String name) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(_jpegBytes);
    return XFile(file.path);
  }

  test('часть multipart объявляет картинку, а не octet-stream', () async {
    // Регрессия на жалобу «к посту не прикрепляется фото»: `package:http`
    // без явного типа ставит части `application/octet-stream`, и серверный
    // fileFilter отвечал 400 до сохранения файла.
    final capture = _Capture();
    final url = await PostMediaUpload.upload(
      await galleryFile('image_picker12345.jpg'),
      client: _capturing(capture),
    );

    expect(url, 'https://cdn.mnd/f.jpg');
    expect(capture.rawBody, contains('filename="image_picker12345.jpg"'));
    // `package:http` пишет заголовки части в нижнем регистре.
    expect(capture.rawBody, contains('content-type: image/jpeg'));
    expect(capture.rawBody, isNot(contains('application/octet-stream')));
  });

  test('POST идёт на адрес загрузки стены с токеном аккаунта', () async {
    final capture = _Capture();
    await PostMediaUpload.upload(
      await galleryFile('photo.jpg'),
      client: _capturing(capture),
    );

    final request = capture.request!;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/author-walls/upload-media');
    expect(request.headers['Authorization'], 'Bearer test-token');
  });

  test('тип части берётся по расширению файла', () {
    expect(imagePartType('/tmp/a/b/image.JPG').mimeType, 'image/jpeg');
    expect(imagePartType('/tmp/shot.png').mimeType, 'image/png');
    expect(imagePartType('/tmp/anim.webp').mimeType, 'image/webp');
    expect(imagePartType('/tmp/sticker.gif').mimeType, 'image/gif');
    // Неизвестное расширение всё равно уходит картинкой: решает сигнатура байт.
    expect(imagePartType('/tmp/mystery.bmp').mimeType, 'image/jpeg');
  });

  test('415 от сервера: показываем его текст', () async {
    final capture = _Capture();
    await expectLater(
      PostMediaUpload.upload(
        await galleryFile('photo.jpg'),
        client: _capturing(
          capture,
          status: 415,
          body:
              '{"error":"Это не похоже на картинку — поддерживаются jpg, png, webp и gif"}',
        ),
      ),
      throwsA(
        predicate<Exception>(
          (e) => e.toString().contains('Это не похоже на картинку'),
        ),
      ),
    );
  });

  test('413 от сервера: лимит размера назван числом', () async {
    final capture = _Capture();
    await expectLater(
      PostMediaUpload.upload(
        await galleryFile('huge.jpg'),
        client: _capturing(
          capture,
          status: 413,
          body: '{"error":"Фото не больше 10 МБ"}',
        ),
      ),
      throwsA(
        predicate<Exception>(
          (e) => e.toString().contains('Фото не больше 10 МБ'),
        ),
      ),
    );
  });

  test('nginx-страница вместо JSON не показывает человеку HTML', () async {
    final capture = _Capture();
    await expectLater(
      PostMediaUpload.upload(
        await galleryFile('photo.jpg'),
        client: _capturing(
          capture,
          status: 502,
          body: '<!DOCTYPE html><html><head><title>502</title></head></html>',
        ),
      ),
      throwsA(
        predicate<Exception>(
          (e) => e.toString() == 'Exception: Сервер не принял фото (код 502)',
        ),
      ),
    );
  });

  test('ответ без ссылки — отдельная честная ошибка', () async {
    final capture = _Capture();
    await expectLater(
      PostMediaUpload.upload(
        await galleryFile('photo.jpg'),
        client: _capturing(capture, body: '{"ok":true}'),
      ),
      throwsA(
        predicate<Exception>(
          (e) => e.toString().contains('Сервер не вернул ссылку'),
        ),
      ),
    );
  });

  test('гость не отправляет фото', () async {
    SharedPreferences.setMockInitialValues({});
    final capture = _Capture();

    await expectLater(
      PostMediaUpload.upload(
        await galleryFile('photo.jpg'),
        client: _capturing(capture),
      ),
      throwsA(
        predicate<Exception>((e) => e.toString().contains('войди в аккаунт')),
      ),
    );
    expect(capture.called, isFalse);
  });
}
