// В интерфейсе объект называется нодой — везде.
//
// Редактор зовёт элемент истории «нодой»: «Новая нода», «Стартовая нода не
// выбрана», «Звуки ноды», диагностика чистильщика — «Битая ссылка на ноду».
// Но часть онбординга и подписей была написана на «узле»: новичок в первые
// минуты читал про «прямоугольник — это узел» в туториале и про «главы
// группируют узлы» под списком глав, а через экран — «выберите ноду». Два
// имени для одной вещи — это не придирка копипастера: человек, который ещё
// не понял, что такое нода, начинает думать, что узел и нода разные вещи.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть «узел» в любую из исправленных
// строк — падает тест про пользовательские строки.
//
// Правки только в строках, которые видит человек. Комменты не трогаем: там
// «узел дерева панелей» — это про дерево виджетов, а не про ноду квеста.
//
// Словарь перевода — исключение с оговоркой: его ключ обязан совпадать с
// литералом в коде, поэтому старый термин из узаконенной строки кочует и в
// ключ. Проверка требует, чтобы ключ был именно эхом, а не новым вхождением.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final hits = _scanForNodeTerm();

  test('скан видит хотя бы единственное узаконенное вхождение', () {
    // Пустой скан выглядел бы как «порядок наведён», поэтому проверяем, что
    // регулярка действительно находит слово там, где оно осталось намеренно.
    expect(
      hits,
      isNotEmpty,
      reason: 'ни одного вхождения «узел» в lib/ — скан, вероятно, сломался',
    );
    expect(
      hits.map((h) => h.path).toSet(),
      equals({
        ..._allowed,
        for (final hit in hits)
          if (_echoedInUi(hit)) hit.path,
      }),
      reason:
          'список узаконенных вхождений разошёлся: ${hits.map((h) => h.where).toList()}',
    );
  });

  test('пользовательские строки зовут объект нодой, а не узлом', () {
    for (final hit in hits) {
      if (_echoedInUi(hit)) continue;
      expect(
        hit.path,
        isIn(_allowed),
        reason:
            '${hit.where}: «${hit.word}» в тексте, который видит человек — '
            'в приложении этот объект называется нодой',
      );
    }
  });

  test('ключ словаря проходит только как эхо строки из кода', () {
    // Иначе «словарям всё можно» проглотило бы и новый термин, придуманный
    // уже в переводе.
    final echo = hits.firstWhere((h) => h.inDictionary);
    expect(_echoedInUi(echo), isTrue, reason: echo.where);
    expect(
      _echoedInUi(
        _Hit(
          path: echo.path,
          line: echo.line,
          word: 'узлов',
          text: "'граф узлов, которой в коде нет нигде'",
        ),
      ),
      isFalse,
    );
  });
}

/// Единственное место, где «узел» — не про ноду квеста: факт на экране
/// загрузки про графы в движках ветвящихся сюжетов (Twine, Ink).
const _allowed = ['lib/features/app/screens/splash_screen.dart'];

/// Ключ словаря — дословная копия строки из кода (гард l10n требует точного
/// совпадения), поэтому переименовать в нём термин нельзя: ключ перестанет
/// находить литерал. Значит «узел» в ключе — эхо уже узаконенного места. Но
/// именно эхо: ключ, которого нет нигде вне словарей, старый термин придумал
/// сам словарь, и он не проходит.
const _dictionaryDir = 'lib/core/l10n/dictionaries';

final String _uiText = () {
  final buf = StringBuffer();
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.startsWith(_dictionaryDir)) continue;
    buf.write(entity.readAsStringSync());
  }
  return buf.toString();
}();

class _Hit {
  _Hit({
    required this.path,
    required this.line,
    required this.word,
    required this.text,
  });

  final String path;
  final int line;
  final String word;

  /// Строка целиком — по ней ключ словаря сверяется с литералом в коде.
  final String text;

  String get where => '$path:$line';

  bool get inDictionary => path.startsWith(_dictionaryDir);
}

/// true, если это ключ словаря, дословно повторяющий строку из кода: старый
/// термин пришёл в него из UI, а не выдуман здесь.
bool _echoedInUi(_Hit hit) {
  if (!hit.inDictionary) return false;
  final key = _keyLiteralOf(hit.text);
  return key != null && _uiText.contains(key);
}

/// Литерал, с которого начинается строка: от первой `'` до первой незаэкранной
/// `'`. Экранирование не разворачиваем — сверяем с исходником кода как есть.
String? _keyLiteralOf(String trimmedLine) {
  final opener = trimmedLine.indexOf("'");
  if (opener < 0) return null;
  for (var i = opener + 1; i < trimmedLine.length; i++) {
    if (trimmedLine[i] == r'\') {
      i++;
      continue;
    }
    if (trimmedLine[i] == "'") return trimmedLine.substring(opener + 1, i);
  }
  return null;
}

/// Все слова на «узел» в коде (не в комментариях) по всему lib/.
List<_Hit> _scanForNodeTerm() {
  final pattern = RegExp('[Уу]зл[а-яё]*');
  final hits = <_Hit>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('//')) continue;
      final match = pattern.firstMatch(line);
      if (match != null) {
        hits.add(
          _Hit(
            path: entity.path,
            line: i + 1,
            word: match.group(0)!,
            text: line,
          ),
        );
      }
    }
  }
  return hits;
}
