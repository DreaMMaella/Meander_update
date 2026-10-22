// Регрессия #206: размытие, выставленное на фоне-видео ноды, не применялось —
// фон оставался резким, хотя для картинки тот же `ImageFiltered` работал.
//
// Половины причин было две, и обе закрыты:
// 1. порог: `_buildBackground` отдавал видео сигму через тяжёлый рубильник
//    `_disableHeavyEffects` (`PlatformPerformance.shouldDisableBlur()`), а он
//    на Linux `true` всегда — размытие доходило до `_BackgroundVideo` нулём;
// 2. место: даже с настоящей сигмой `ImageFiltered` поверх `Video` ничего не
//    делает. media_kit рисует кадр виджетом `Texture` — это внешняя GL-текстура,
//    и движок не гонит её через offscreen-пасс фильтра. Поэтому размытие
//    уехало внутрь mpv (`setProperty('vf', …)`), где кадр ещё наш.
// 3. платформа: мобильные libmpv (android/ios) ffmpeg-фильтры не компилировали,
//    `gblur` там нет (#223), поэтому на них кадр размывает слой `BackdropFilter`
//    поверх текста, а в mpv фильтр не уходит вообще.
//
// Негативный контроль: вернуть в `_BackgroundVideo` `blurValue:
// _disableHeavyEffects ? 0.0 : blurValue` — падает первый тест; вернуть в
// `_BackgroundVideoState.build` `ImageFiltered` вокруг `Video` и убрать
// `_applyMpvBlur` — падает тест про mpv; убрать `defaultTargetPlatform.name`
// из вызова — падает проверка, что фильтр выбирается по платформе.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath = 'lib/screens/game_screen.dart';

/// Убирает целострочные комментарии: скобки в прозе ломали бы поиск границ
/// вызова, а `//` внутри строк (URL) трогать нельзя.
String _withoutFullLineComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Тело вызова `callee(...)` — текст между первой и последней скобкой,
/// сбалансированный по вложенности.
String _callBody(String source, String callee, {required String marker}) {
  var offset = 0;
  while (true) {
    final at = source.indexOf('$callee(', offset);
    if (at < 0) return '';
    var depth = 0;
    for (var i = at + callee.length; i < source.length; i++) {
      final char = source[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          final body = source.substring(at + callee.length + 1, i);
          // Объявление конструктора тоже подходит под имя, но аргументы там
          // через `this.` — маркер отличает именно вызов.
          if (body.contains(marker)) return body;
          break;
        }
      }
    }
    offset = at + callee.length;
  }
}

/// Значение аргумента `name:` из тела вызова (до запятой верхнего уровня).
String _argument(String body, String name) {
  final at = body.indexOf('$name:');
  if (at < 0) return '';
  var depth = 0;
  for (var i = at + name.length + 1; i < body.length; i++) {
    final char = body[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) return body.substring(at + name.length + 1, i).trim();
      depth--;
    } else if (char == ',' && depth == 0) {
      return body.substring(at + name.length + 1, i).trim();
    }
  }
  return body.substring(at + name.length + 1).trim();
}

/// Тело класса `class Name …` — текст от первой `{` до парной `}`.
String _classBody(String source, String declaration) {
  final at = source.indexOf(declaration);
  if (at < 0) return '';
  final open = source.indexOf('{', at);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  return '';
}

void main() {
  final file = File(_screenPath);
  if (!file.existsSync()) {
    markTestSkipped('$_screenPath не найден относительно рабочей директории');
    return;
  }
  final source = _withoutFullLineComments(file.readAsStringSync());

  group('гейт фонового размытия в game_screen', () {
    test('видео берёт сигму из общего гейта, а не из тяжёлых эффектов', () {
      final body = _callBody(source, '_BackgroundVideo', marker: 'blurValue:');
      expect(body, isNotEmpty, reason: 'вызов _BackgroundVideo не найден');
      final blurArg = _argument(body, 'blurValue');
      expect(blurArg, contains('blurSigma'));
      expect(
        blurArg,
        isNot(contains('_disableHeavyEffects')),
        reason:
            'тяжёлый рубильник на Linux всегда true — видео снова получит 0',
      );
    });

    test('blurSigma считается по мягкому порогу `_disableBackgroundBlur`', () {
      final gate = _callBody(source, 'gateBackgroundBlur', marker: 'disabled:');
      expect(gate, isNotEmpty, reason: 'gateBackgroundBlur не вызывается');
      expect(gate, contains('_disableBackgroundBlur'));
      expect(source, isNot(contains('_disableHeavyEffects ? 0.0')));
    });

    test('обе ветки фона используют одну и ту же сигму', () {
      final imageFilter = _callBody(
        source,
        'ImageFilter.blur',
        marker: 'sigmaX: blurSigma',
      );
      expect(imageFilter, isNotEmpty, reason: 'фильтр картинки не найден');
      expect(imageFilter, contains('blurSigma'));
      expect(imageFilter, isNot(contains('blurValue')));
    });

    test('видео размывает mpv, а не ImageFiltered поверх текстуры', () {
      final videoState = _classBody(source, 'class _BackgroundVideoState');
      expect(videoState, isNotEmpty, reason: '_BackgroundVideoState не найден');
      expect(
        videoState,
        isNot(contains('ImageFiltered')),
        reason:
            'фильтр поверх Texture движок не применяет — слой только платит за offscreen',
      );
      final mpvCall = _callBody(
        videoState,
        'mpvBackgroundBlurFilter',
        marker: 'blurValue',
      );
      expect(
        mpvCall,
        isNotEmpty,
        reason: 'сигма обязана уходить в цепочку фильтров mpv',
      );
      expect(
        mpvCall,
        contains('defaultTargetPlatform.name'),
        reason:
            'у мобильных сборок libmpv фильтра gblur нет — фильтр выбирают по платформе',
      );
      expect(videoState, contains("'vf'"));
    });

    test('фильтр ставится до первого кадра и при смене сигмы', () {
      final videoState = _classBody(source, 'class _BackgroundVideoState');
      expect(
        videoState.indexOf('_applyMpvBlur();') <
            videoState.indexOf('_opened = true'),
        isTrue,
        reason: 'иначе первые кадры фона резкие',
      );
      final didUpdate = _classBody(videoState, 'void didUpdateWidget');
      expect(
        didUpdate,
        contains('blurValue'),
        reason: 'set_blur посреди ноды обязан переставить фильтр',
      );
    });

    test('отказ mpv виден в логе, а не проглатывается', () {
      // #223 ловили вслепую именно потому, что `catch (_) {}` прятал «фильтр
      // не принят»: сигма есть, размытия нет, в консоли чисто.
      final mpvBlur = _classBody(
        _classBody(source, 'class _BackgroundVideoState'),
        'Future<void> _applyMpvBlur',
      );
      expect(mpvBlur, isNotEmpty, reason: '_applyMpvBlur не найден');
      expect(mpvBlur, isNot(contains('catch (_) {}')));
      expect(mpvBlur, contains('kDebugMode'));
    });

    test('на мобильном фоне размытие делает слой, а не фильтр mpv', () {
      // Мобильный libmpv ffmpeg-фильтров не несёт, а `format=w=iw/4` к тому же
      // не разбирается и скале не делает (#223) — вернуть его в `vf` значит
      // снова получить резкий фон с довольным логом.
      final videoState = _classBody(source, 'class _BackgroundVideoState');
      expect(videoState, contains('backgroundVideoBlurRoute'));
      expect(videoState, contains('BackdropFilter'));
      expect(source, isNot(contains('mpvMobileBlurFilter')));
    });
  });
}
