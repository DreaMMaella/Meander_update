// Заполнители полей переводятся на витрине, а не в данных.
//
// Значения вида «Не выбрана», «Выберите ноду», «имя_переменной» лежат в
// моделях блоков и уже записаны в файлах квестов пользователей. Перевести их
// в самих данных было бы ловушкой: новый файл получился бы английским, а
// старые остались русскими, и сравнение «значение == заглушка» (его делают
// `isEmpty`-проверки и логика блоков) сломалось бы на половине библиотеки.
// Поэтому данные остаются русскими, а `displayFieldSentinel` снимает перевод
// ровно в момент, когда строку показывают человеку.
//
// НЕГАТИВНЫЕ КОНТРОЛИ (проверено):
//   * тело `switch` сведено к `return value` — падают тесты 1 и 4;
//   * тело сведено к `return tr(value)` — падает тест 2: текст автора,
//     совпадающий с русской строкой интерфейса, перестал бы быть его;
//   * маппинг перевёл бы данные вместо витрины — тест 3: в русском
//     интерфейсе строки обязаны оставаться ровно теми, что лежат в модели.

import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => L10n.setCurrent(L10n.byCode(kSourceLanguageCode)));

  test('английский интерфейс показывает переводные заглушки', () {
    L10n.setCurrent(L10n.byCode('en'));
    expect(displayFieldSentinel('Не выбрана'), 'Not selected');
    expect(displayFieldSentinel('Не выбрано'), 'Not selected');
    expect(displayFieldSentinel('Выберите ноду'), 'Choose a node');
    expect(displayFieldSentinel('Выберите скрипт'), 'Choose a script');
    expect(displayFieldSentinel('имя_переменной'), 'variable_name');
    expect(displayFieldSentinel('Скрипт не найден'), 'Script not found');
  });

  test('текст автора проходит как есть, даже по-русски', () {
    L10n.setCurrent(L10n.byCode('en'));
    // Автор ввёл имя сам — это данные, их не переводят.
    expect(displayFieldSentinel('Лес'), 'Лес');
    expect(displayFieldSentinel('Мой скрипт'), 'Мой скрипт');
    expect(displayFieldSentinel(''), '');
  });

  test('русский интерфейс отдаёт строку без изменений', () {
    // Язык-источник: маппинг не должен ни добавлять, ни перефразировать.
    expect(displayFieldSentinel('Не выбрана'), 'Не выбрана');
    expect(displayFieldSentinel('Выберите ноду'), 'Выберите ноду');
    expect(displayFieldSentinel('Лес'), 'Лес');
  });

  test('ни одна заглушка не выпала из маппинга', () {
    // Гард проверяет, что литерал `tr(...)` из lib/ есть в словаре, но не
    // видит, остался ли кейс в самом `switch`. Убранный кейс вернул бы русскую
    // строку в английском интерфейсе — этот список такие провалы и ловит.
    L10n.setCurrent(L10n.byCode('en'));
    const sentinels = [
      'Не выбрана',
      'Не выбран',
      'Не выбрано',
      'Выберите объект',
      'Выберите ноду',
      'Выберите скрипт',
      'Выберите функцию',
      'Выберите аудио',
      'Выберите музыку',
      'Выберите .lua',
      'Все звуки',
      'имя_переменной',
      'Скрипт не найден',
    ];
    for (final sentinel in sentinels) {
      expect(
        displayFieldSentinel(sentinel),
        L10n.tr(sentinel),
        reason: '«$sentinel» выпала из маппинга: на витрине она осталась русской',
      );
      expect(
        displayFieldSentinel(sentinel),
        isNot(sentinel),
        reason: 'перевод «$sentinel» совпадает с русским — в словаре пусто',
      );
    }
  });
}
