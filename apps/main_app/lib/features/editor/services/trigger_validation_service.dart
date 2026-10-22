import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/parser.dart'
    show ScriptParser;
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/trigger_reference.dart';
import 'package:mnd_core/utils/quest_paths.dart';

/// Minimal storage contract used by trigger validation.
///
/// Keeping the validator on this narrow interface makes it possible to test
/// trigger diagnostics without touching the application documents directory.
abstract interface class TriggerValidationStorage {
  Future<bool> exists(String relativePath);

  Future<Map<String, dynamic>> readJsonFile(String relativePath);
}

/// Production adapter for the quest file storage.
class FileTriggerValidationStorage implements TriggerValidationStorage {
  const FileTriggerValidationStorage();

  @override
  Future<bool> exists(String relativePath) => FileStorage.exists(relativePath);

  @override
  Future<Map<String, dynamic>> readJsonFile(String relativePath) =>
      FileStorage.readJsonFile(relativePath);
}

/// A problem found in an item trigger, or `null` when the trigger is valid.
class TriggerValidationIssue {
  final String message;
  final bool canAutoFix;

  const TriggerValidationIssue({
    required this.message,
    this.canAutoFix = false,
  });
}

/// Shared validation rules for editor onAppear triggers.
///
/// Lua is intentionally validated only for file existence: its body is
/// interpreted by the Lua runtime and cannot be checked with JSON block rules.
/// JSON triggers are checked for a valid function/event and matching item
/// target, preserving the behavior previously duplicated in two screens.
class TriggerValidationService {
  final String questId;
  final TriggerValidationStorage storage;

  const TriggerValidationService({
    required this.questId,
    this.storage = const FileTriggerValidationStorage(),
  });

  Future<TriggerValidationIssue?> validateOnAppear({
    required String itemId,
    required String? rawTrigger,
  }) async {
    final raw = rawTrigger?.trim() ?? '';
    if (raw.isEmpty) return null;

    final triggerRef = TriggerReference.parse(raw);
    if (triggerRef.scriptPath.isEmpty) {
      return TriggerValidationIssue(message: tr('onAppear-скрипт не найден'));
    }

    final fullPath = QuestPaths.questFile(questId, triggerRef.scriptPath);
    if (!await storage.exists(fullPath)) {
      return TriggerValidationIssue(message: tr('onAppear-скрипт не найден'));
    }

    if (triggerRef.scriptPath.toLowerCase().endsWith('.lua')) {
      return null;
    }

    try {
      final scriptData = await storage.readJsonFile(fullPath);
      // Канонизация (план 020-B4): легаси title-события/алиасы больше не
      // дают ложных «нет события». Фолбэк офлайн, паритет с ядром — golden.
      final canonical = <String, dynamic>{
        'blocks': ScriptParser.normalizeScriptBlocks(
          (scriptData['blocks'] as List? ?? []),
        ),
      };
      final blocks = _topLevelBlocks(canonical);

      if (triggerRef.isFunctionRef) {
        final functionEvents = blocks.where(
          (block) =>
              block['type'] == 'event' &&
              block['eventType']?.toString() == 'function',
        );
        final existsNamed = functionEvents.any((event) {
          final functionName = event['functionName']?.toString().trim();
          final resolvedName = (functionName == null || functionName.isEmpty)
              ? 'main'
              : functionName;
          return resolvedName == triggerRef.functionEntry;
        });

        if (!existsNamed) {
          return TriggerValidationIssue(
            message: trf('В скрипте нет функции "{p0}"', {'p0': triggerRef.functionEntry}),
          );
        }
        return null;
      }

      final onAppearEvents = blocks.where(
        (block) =>
            block['type'] == 'event' &&
            block['eventType']?.toString() == 'onContentAppear',
      );
      final events = onAppearEvents.toList(growable: false);

      if (events.isEmpty) {
        return TriggerValidationIssue(
          message: tr('В скрипте нет события onContentAppear'),
        );
      }

      final hasMatchingTarget = events.any((event) {
        final target = event['targetContentItemId']?.toString();
        return target == null || target.isEmpty || target == itemId;
      });
      if (hasMatchingTarget) return null;

      if (events.length == 1) {
        return TriggerValidationIssue(
          message:
              tr('onAppear ссылается на другой/устаревший item. Можно исправить автоматически.'),
          canAutoFix: true,
        );
      }

      return TriggerValidationIssue(
        message:
            tr('onAppear ссылается на другой item в многособытийном скрипте. Нужна ручная проверка.'),
      );
    } catch (_) {
      return TriggerValidationIssue(
        message: tr('Не удалось прочитать onAppear-скрипт'),
      );
    }
  }

  List<Map<String, dynamic>> _topLevelBlocks(Map<String, dynamic> scriptData) {
    final rawBlocks = scriptData['blocks'];
    if (rawBlocks is! List) return const [];
    return rawBlocks
        .whereType<Map>()
        .map((block) => Map<String, dynamic>.from(block))
        .toList(growable: false);
  }
}
