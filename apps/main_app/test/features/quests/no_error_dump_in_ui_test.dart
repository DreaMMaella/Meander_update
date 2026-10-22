// Экраны называют причину сбоя, а не печатают дамп.
//
// `'Ошибка: $e'` в снэкбаре — это `FileSystemException: Cannot create
// directory, path = /data/user/0/com.IILLUMINAT.meadner/… (OS Error: No space
// left on device, errno = 28)` или `Exception(HttpException: …)` с трейсом на
// три строки. Человек получает имя класса и путь приложения, которые он не
// может ни открыть, ни проверить, — и читает это как «Meander сломан».
// `friendlyError()` оставляет одну строку без префикса класса, а для сетевого
// отказа — русскую фразу.
//
// Инвариант держим по исходникам, потому что правок здесь много и они
// одинаковые: дамп ошибки доходит до лога, но не до строки UI. `debugPrint`
// и `print` разрешены намеренно — там трейс нужен разработчику, и человек его
// не видит. Дамп приходит в трёх формах: `$e`, `${e}` / `${e.toString()}` и
// `e.toString()` прямо в аргументе снэкбара (`_showError(e.toString())` в
// ресурсах) — на каждую свой признак.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): снять обёртку по одной форме в каждом
// месте — `Text('Ошибка: $err')` в node_selection_screen.dart,
// `Text('Ошибка: ${e.toString()}')` в report_dialog.dart и
// `_showError(e.toString())` в resources_screen.dart; из редакторского среза
// так же проверяли `$e` в tags_screen.dart, multiline-аргумент
// `_showSnack('Не удалось загрузить скрипт: …')` в visual_script_editor_screen
// и `_showMessage(nav, 'Ошибка импорта: $e')` в deep_link_service.dart.
// Из сервисного среза так же проверяли `'Ошибка импорта: $e'` в
// qst_importer.dart, `failed.add('${q.title}: $e')` в cloud_sync_service.dart
// и `description: '$e'` в quest_cleaner_service.dart.
// В каждом случае падают оба теста этого файла: «не попадает в строки UI» на
// номере строки, «разворачивается через friendlyError» на границе числа
// вызовов.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Поверхности, где человек видит сбой: вкладка «Мои» с её экранами,
/// маркет/хаб, куда новичок попадает сразу после входа, социальные экраны —
/// стена, публикация и профиль, редактор с ресурсами (сбой там чаще не сетевой,
/// а `dart:io`: нет места, нет прав, пикер вернул мусор), путь новичка —
/// вход, импорт чужого квеста, публикация своего, аватар, награды, история,
/// загрузка сохранения — и остальной редактор: главы и шаблоны, слои кнопок,
/// таблицы, Lua, визуальные скрипты и импорт квеста по ссылке. Сюда же
/// попадают сервисы, чьи строки экран показывает человеку: импорт `.qst`,
/// облачная синхронизация (список отказов) и чистка квеста (описание проблемы).
const _screens = [
  'lib/features/quests/screens/my_quests_screen.dart',
  'lib/features/quests/screens/quest_details_screen.dart',
  'lib/features/quests/screens/edit_quest_screen.dart',
  'lib/features/quests/screens/quest_history_screen.dart',
  'lib/features/quests/screens/create_quest_screen.dart',
  'lib/features/hub/widgets/preset_market.dart',
  'lib/features/hub/widgets/market_resource_actions.dart',
  'lib/features/market/screens/quest_market_details_screen.dart',
  'lib/features/wall/widgets/post_card.dart',
  'lib/features/wall/screens/create_post_screen.dart',
  'lib/features/profile/screens/my_publications_screen.dart',
  'lib/features/profile/screens/profile_screen.dart',
  'lib/features/resources/screens/resources_screen.dart',
  'lib/features/editor/screens/node_selection_screen.dart',
  'lib/features/editor/screens/node_content_screen.dart',
  'lib/features/hub/screens/preset_details_screen.dart',
  'lib/features/asset_market/screens/asset_upload_screen.dart',
  'lib/features/profile/widgets/banner_and_socials.dart',
  'lib/shared/widgets/report_dialog.dart',
  'lib/features/quests/screens/import_quest_screen.dart',
  'lib/features/quests/screens/quest_sync_settings_screen.dart',
  'lib/features/quests/screens/cloud_sync_settings_screen.dart',
  'lib/features/quests/screens/quest_publish_screen.dart',
  'lib/features/profile/screens/play_history_screen.dart',
  'lib/features/profile/screens/rewards_screen.dart',
  'lib/features/profile/screens/avatar_editor_screen.dart',
  'lib/features/settings/screens/theme_settings_screen.dart',
  'lib/features/shell/screens/menu_screen.dart',
  'lib/features/game/screens/load_game_screen.dart',
  'lib/features/game/screens/game_from_save_loader.dart',
  'lib/features/market/widgets/market_widgets.dart',
  'lib/features/forums/screens/forum_topic_composer_screen.dart',
  'lib/features/editor/screens/tags_screen.dart',
  'lib/features/editor/screens/canvas_screen.dart',
  'lib/features/editor/screens/button_style_presets_screen.dart',
  'lib/features/editor/screens/button_style_editor_screen.dart',
  'lib/features/editor/screens/template_manager_screen.dart',
  'lib/features/editor/screens/audio_selection_screen.dart',
  'lib/features/editor/widgets/template_picker_sheet.dart',
  'lib/features/editor/widgets/quest_validation_panel.dart',
  'lib/features/editor/logic/item_editor_helper.dart',
  'lib/features/editor/screens/node_content/container_editor_screen.dart',
  'lib/features/editor/screens/visual_script_editor/visual_script_editor_screen.dart',
  'lib/features/editor/screens/visual_script_editor/content_item_selection_screen.dart',
  'lib/features/editor/screens/visual_script_editor/variable_selection_screen.dart',
  'lib/features/resources/screens/data/table_editor_screen.dart',
  'lib/features/resources/screens/lua_editor_screen.dart',
  'lib/core/services/deep_link_service.dart',
  'lib/core/importers/qst_parser.dart',
  'lib/core/importers/qst_importer.dart',
  'lib/core/services/cloud_sync_service.dart',
  'lib/core/services/quest_cleaner_service.dart',
];

/// Минимум вызовов `friendlyError` в файле — ровно текущее их число.
/// Нижняя граница не даёт инварианту стать ложно-зелёным: снял кто-то одну
/// обёртку — тест падает, а не ждёт, пока дамп снова доедет до человека.
const _friendlyFloor = {
  'lib/features/quests/screens/my_quests_screen.dart': 8,
  'lib/features/quests/screens/quest_details_screen.dart': 5,
  'lib/features/quests/screens/edit_quest_screen.dart': 3,
  'lib/features/quests/screens/quest_history_screen.dart': 2,
  'lib/features/quests/screens/create_quest_screen.dart': 1,
  'lib/features/hub/widgets/preset_market.dart': 4,
  'lib/features/hub/widgets/market_resource_actions.dart': 2,
  'lib/features/market/screens/quest_market_details_screen.dart': 5,
  'lib/features/wall/widgets/post_card.dart': 1,
  'lib/features/wall/screens/create_post_screen.dart': 1,
  'lib/features/profile/screens/my_publications_screen.dart': 1,
  'lib/features/profile/screens/profile_screen.dart': 5,
  'lib/features/resources/screens/resources_screen.dart': 15,
  'lib/features/editor/screens/node_selection_screen.dart': 2,
  'lib/features/editor/screens/node_content_screen.dart': 3,
  'lib/features/hub/screens/preset_details_screen.dart': 1,
  'lib/features/asset_market/screens/asset_upload_screen.dart': 1,
  'lib/features/profile/widgets/banner_and_socials.dart': 1,
  'lib/shared/widgets/report_dialog.dart': 1,
  'lib/features/quests/screens/import_quest_screen.dart': 2,
  'lib/features/quests/screens/quest_sync_settings_screen.dart': 1,
  'lib/features/quests/screens/cloud_sync_settings_screen.dart': 1,
  'lib/features/quests/screens/quest_publish_screen.dart': 1,
  'lib/features/profile/screens/play_history_screen.dart': 1,
  'lib/features/profile/screens/rewards_screen.dart': 1,
  'lib/features/profile/screens/avatar_editor_screen.dart': 1,
  'lib/features/settings/screens/theme_settings_screen.dart': 1,
  'lib/features/shell/screens/menu_screen.dart': 2,
  'lib/features/game/screens/load_game_screen.dart': 1,
  'lib/features/game/screens/game_from_save_loader.dart': 1,
  'lib/features/market/widgets/market_widgets.dart': 2,
  'lib/features/forums/screens/forum_topic_composer_screen.dart': 1,
  'lib/features/editor/screens/tags_screen.dart': 3,
  'lib/features/editor/screens/canvas_screen.dart': 1,
  'lib/features/editor/screens/button_style_presets_screen.dart': 3,
  'lib/features/editor/screens/button_style_editor_screen.dart': 1,
  'lib/features/editor/screens/template_manager_screen.dart': 1,
  'lib/features/editor/screens/audio_selection_screen.dart': 1,
  'lib/features/editor/widgets/template_picker_sheet.dart': 1,
  'lib/features/editor/widgets/quest_validation_panel.dart': 1,
  'lib/features/editor/logic/item_editor_helper.dart': 2,
  'lib/features/editor/screens/node_content/container_editor_screen.dart': 1,
  'lib/features/editor/screens/visual_script_editor/visual_script_editor_screen.dart':
      4,
  'lib/features/editor/screens/visual_script_editor/content_item_selection_screen.dart':
      1,
  'lib/features/editor/screens/visual_script_editor/variable_selection_screen.dart':
      2,
  'lib/features/resources/screens/data/table_editor_screen.dart': 2,
  'lib/features/resources/screens/lua_editor_screen.dart': 3,
  'lib/core/services/deep_link_service.dart': 1,
  'lib/core/importers/qst_parser.dart': 2,
  'lib/core/importers/qst_importer.dart': 3,
  'lib/core/services/cloud_sync_service.dart': 2,
  'lib/core/services/quest_cleaner_service.dart': 4,
};

/// Куда дампу можно: лог (`debugPrint`/`print`) и комментарий, где он
/// описывается. Всё остальное — строка, которую читает человек.
final _allowedRawDump = RegExp(r'(^//|debugPrint\(|print\()');

/// `$e` и `${e}` / `${e.toString()}` — ошибка, вставленная в строку как есть.
/// Фигурные скобки смотрим только в форме «весь идентификатор» или
/// `.toString()`: `${e.$2}` — это поля кортежа, а не дамп.
final _rawDump = RegExp(
  r'\$(?:e|err|error|stack)\b'
  r'|\$\{\s*(?:e|err|error|stack)(?:\.toString\(\))?\s*\}',
);

/// `e.toString()`, переданный прямо в поверхность с сообщением: тот же дамп,
/// только без кавычек — `_showError(e.toString())` в ресурсах годами печатал
/// `FileSystemException ... (OS Error: No space left on device, errno = 28)`.
final _dumpAsArgument = RegExp(
  r'(SnackBar\(|showSnackBar\(|_showError\()'
  r'[^\n]*\b(?:e|err|error)\.toString\(\)',
);

String _source(String path) => File(path).readAsStringSync();

/// Вне списка сознательно: `shell/screens/admin_screen.dart` (5 мест),
/// `plugins/`, `analytics/` и служебные логи (`*_provider`, `hang_watchdog`,
/// `crash_log_service`, `print`/`debugPrint`) — там дамп читает разработчик
/// или автор в админке, а не новичок. В список попали только те сервисы, чью
/// строку экран отдаёт человеку: `deep_link_service` (тот, кто открыл квест по
/// ссылке), `qst_parser` и `qst_importer` (диалог импорта),
/// `cloud_sync_service` (список отказов), `quest_cleaner_service`
/// (описание проблемы).
/// Следующий срез снимает ограничение, если находка окажется на пути человека.

void main() {
  for (final path in _screens) {
    final name = path.split('/').last;

    test('$name: дамп ошибки не попадает в строки UI', () {
      expect(File(path).existsSync(), isTrue, reason: '$path переехал');
      final lines = _source(path).split('\n');
      final leaked = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        final isDump =
            (_rawDump.hasMatch(trimmed) || _dumpAsArgument.hasMatch(trimmed)) &&
            !_allowedRawDump.hasMatch(trimmed);
        if (isDump) {
          leaked.add('${i + 1}: $trimmed');
        }
      }
      expect(
        leaked,
        isEmpty,
        reason:
            'человек читает трейс вместо причины — оберни в friendlyError '
            '(или в свою фразу, как questCreationErrorText)',
      );
    });

    test('$name: причина сбоя разворачивается через friendlyError', () {
      final calls = 'friendlyError('.allMatches(_source(path)).length;
      expect(
        calls,
        greaterThanOrEqualTo(_friendlyFloor[path]!),
        reason:
            'мест, где ошибку человек видит одной строкой, стало меньше, '
            'чем их закрывали',
      );
    });
  }

  test('признак отказа хранилища общий для всех экранов', () {
    // Список маркеров живёт в error_text.dart: локальные копии экранов
    // расходятся, и на одном экране «No space left» снова станет дампом.
    final shared = _source('lib/core/utils/error_text.dart');
    expect(shared, contains('bool looksLikeStorageFailure(Object error)'));
    for (final marker in const [
      'FileSystemException',
      'No space left',
      'Permission denied',
      'Not a directory',
    ]) {
      expect(shared, contains(marker));
    }
    for (final path in _screens) {
      expect(
        _source(path),
        isNot(contains('_storageFailureMarkers')),
        reason: '$path держит собственный список маркеров вместо общего',
      );
    }
  });
}
