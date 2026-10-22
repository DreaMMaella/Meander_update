// Регрессия на «публикация висит на 99% / падает с непонятной ошибкой».
//
// Негативный контроль: если убрать учёт байтов в ProgressMultipartRequest
// (вернуть `super.finalize()`), тесты прогресса падают — колбэк не вызывается
// ни разу. Если убрать сравнение размера пакета с лимитом в
// preflightSizeRejection, падает первый же тест отсева. Если вернуть в
// describePublishFailure общий текст вместо разбора по `code` — падают тесты
// вилок по кодам.
//
// Тесты не покрывают: сам UI-экран (setState-переходы, обрыв по сторожу на
// живом соклете) и сетевые таймауты — там, где решает реальный запуск на
// десктопе.

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/core/services/publish_upload.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('лимиты пакета', () {
    test('совпадают с бэкендом', () {
      expect(PublishLimits.forVerified(false), 100 * 1024 * 1024);
      expect(PublishLimits.forVerified(true), 500 * 1024 * 1024);
    });

    test('101 МБ у обычного автора отсекаются до загрузки', () {
      final message = preflightSizeRejection(
        101 * 1024 * 1024,
        false,
      );
      expect(message, isNotNull);
      expect(message, contains('101.0'));
      expect(message, contains('100.0'));
      // Худший сценарий для верификации — подсказка, а не тупик.
      expect(message, contains('верификац'));
    });

    test('100 МБ ровно — проходят, 499 МБ у верифицированного — проходят', () {
      expect(
        preflightSizeRejection(100 * 1024 * 1024, false),
        isNull,
      );
      expect(
        preflightSizeRejection(499 * 1024 * 1024, true),
        isNull,
      );
    });

    test('210 МБ у верифицированного — не отказ', () {
      expect(
        preflightSizeRejection(210 * 1024 * 1024, true),
        isNull,
      );
    });
  });

  group('прогресс отправки', () {
    test('sentFraction считает долю и не врёт при неизвестном размере', () {
      expect(sentFraction(0, 100), 0.0);
      expect(sentFraction(50, 100), 0.5);
      expect(sentFraction(150, 100), 1.0);
      expect(sentFraction(-1, 100), isNull);
      expect(sentFraction(10, 0), isNull);
    });

    test('ProgressMultipartRequest отдаёт реальные байты тела', () async {
      final dir = await Directory.systemTemp.createTemp('mnd-publish-test-');
      final questFile = File('${dir.path}/quest.mnd');
      final payload = List<int>.generate(64 * 1024, (i) => i % 251);
      await questFile.writeAsBytes(payload);

      final reports = <List<int>>[];
      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:1/quests'),
        (sent, total) => reports.add([sent, total]),
      )..fields['id'] = 'quest-1';
      request.files.add(await http.MultipartFile.fromPath('questFile', questFile.path));

      final total = request.contentLength;
      var received = 0;
      await for (final chunk in request.finalize()) {
        received += chunk.length;
      }

      expect(reports, isNotEmpty, reason: 'тело шло, но прогресс не вызвался');
      expect(reports.first.first, greaterThan(0));
      expect(reports.last[0], total, reason: 'последний отсчёт = весь массив');
      expect(received, total);
      // Монотонность: проценты не должны прыгать назад.
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
      }
      expect(total, greaterThan(payload.length), reason: 'multipart добавляет заголовки и поля');
      await dir.delete(recursive: true);
    });

    test('ProgressMultipartRequest не ломает тело: multipart разбирается', () async {
      final dir = await Directory.systemTemp.createTemp('mnd-publish-body-');
      final questFile = File('${dir.path}/quest.mnd');
      await questFile.writeAsBytes(utf8.encode('{"nodes":[]}'));

      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:1/quests'),
        null,
      )..fields['title'] = 'Тест';
      request.files.add(await http.MultipartFile.fromPath('questFile', questFile.path));

      final body = <int>[];
      await for (final chunk in request.finalize()) {
        body.addAll(chunk);
      }
      final text = utf8.decode(body, allowMalformed: true);
      expect(text, contains('name="title"'));
      expect(text, contains('Тест'));
      expect(text, contains('name="questFile"'));
      expect(text, contains('filename="quest.mnd"'));
      expect(text, contains('{"nodes":[]}'));
      await dir.delete(recursive: true);
    });
  });

  group('разбор отказа по коду', () {
    test('каждый код даёт свой actionable-текст', () {
      const cases = <String, List<String>>{
        'file_too_large': ['210', '100'],
        'quest_owned_by_other_author': ['копия', 'маркет'],
        'duplicate_file': ['уже'],
        'quest_file_required': ['не дошёл'],
        'archive_unreadable': ['разобрать'],
        'content_policy_violation': ['Слишком мало контента'],
        'publish_failed': ['не твоя ошибка'],
      };
      for (final entry in cases.entries) {
        final message = describePublishFailure({
          'code': entry.key,
          'error': 'internal english detail',
          'reason': 'Слишком мало контента',
          'size_mb': 210.5,
          'limit_mb': 100,
        }, 400);
        expect(message, isNotNull, reason: 'код ${entry.key} без текста');
        for (final needle in entry.value) {
          expect(
            message!.toLowerCase(),
            contains(needle.toLowerCase()),
            reason: '${entry.key}: ожидалось «$needle»',
          );
        }
      }
    });

    test('английское внутреннее сообщение сервера наружу не уходит', () {
      final message = describePublishFailure({
        'code': 'file_too_large',
        'error': 'File size exceeds limit. Your limit: 100 MB',
      }, 413);
      expect(message, isNotNull);
      expect(message, isNot(contains('File size exceeds')));
    });

    test('401 без кода — отдельная строка про сессию', () {
      expect(
        describePublishFailure({'error': 'Invalid token'}, 401),
        contains('Перезайди'),
      );
    });

    test('незнакомый код или тело без кода — null, разбор отдаём экрану', () {
      expect(describePublishFailure({'code': 'weird_new_code'}, 400), isNull);
      expect(describePublishFailure({'error': 'boom'}, 500), isNull);
      expect(describePublishFailure({}, 502), isNull);
    });
  });
}
