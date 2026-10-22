// Текст ошибки, который видит автор в снэкбаре.
//
// Предпосылка проверена языком: `Exception.toString()` добавляет префикс
// `Exception: `, а `HttpException` печатает многострочный дамп. Экраны
// вставляли `$e` как есть — отсюда «Ошибка: Exception: Лимит 5/час».

import 'dart:io';

import 'package:canvas_app/core/utils/error_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Exception не протекает в UI как «Exception: …»', () {
    // То, ради чего хелпер появился: префикс даёт сам dart:core.
    expect(Exception('Лимит 5/час').toString(), 'Exception: Лимит 5/час');
    expect(friendlyError(Exception('Лимит 5/час')), 'Лимит 5/час');
  });

  test('от дампа с трейсом остаётся первая строка', () {
    final error = const FormatException(
      'Unexpected character (at character 3)\n{"a":\n  ^\n'
      '',
    );
    expect(friendlyError(error), 'Unexpected character (at character 3)');
  });

  test('код в начале строки превращается в человеческую фразу', () {
    expect(friendlyError(Exception('403 Только автор')), 'Только автор');
    expect(friendlyError(Exception('403')), 'Доступ запрещён');
    expect(friendlyError(Exception('404 пост не найден')), 'пост не найден');
    expect(friendlyError(Exception('401')), 'Сессия истекла — войдите заново');
    // Обёртка поверх обёртки: `Exception(HttpException: …)` даёт два префикса.
    expect(
      friendlyError(Exception(const HttpException('socket hung').toString())),
      'socket hung',
    );
    expect(
      friendlyError(Exception('Failed to load data: 503 ups')),
      'Сервер ответил: 503 ups',
    );
    expect(
      friendlyError(Exception('Unauthorized: token expired')),
      'Сессия истекла — войдите заново',
    );
  });

  test('нет соединения и техработы опознаются по всему дампу', () {
    expect(
      friendlyError(
        Exception(
          'HttpException: Connection closed before full header was received, '
          'uri = http://127.0.0.1:8787/api/x',
        ),
      ),
      'Connection closed before full header was received, '
      'uri = http://127.0.0.1:8787/api/x',
      reason: 'префикс класса не информативен — остаётся суть',
    );
    expect(
      friendlyError(Exception('SocketException: OS Error: Connection refused')),
      'Нет соединения с сервером',
    );
    expect(
      friendlyError(Exception('SERVER_MAINTENANCE: вернёмся скоро')),
      'Сервер на обслуживании',
    );
  });

  test('длинный текст сервера обрезается, а не растягивает снэкбар', () {
    final long = 'а' * 300;
    final out = friendlyError(Exception(long));
    expect(out.length, 143);
    expect(out.endsWith('...'), isTrue);
  });
}
