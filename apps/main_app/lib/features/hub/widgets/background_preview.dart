import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/quest_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/features/game/screens/game_screen.dart';
import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';

/// Превью фона «как в квесте»: собираем временный квест-песочницу с этим
/// фоном и демо-контентом, открываем настоящий плеер, после выхода — удаляем.
class BackgroundPreviewService {
  static const _prefix = 'bg_preview_';

  /// Создать временный квест с фоном [asset] и демо-узлом.
  /// Возвращает questId.
  static Future<String> createPreviewQuest(MarketAsset asset) async {
    await _sweepStale();
    final questId = '$_prefix${DateTime.now().millisecondsSinceEpoch}';

    // 1. Скачать картинку фона.
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final uri = Uri.parse(asset.downloadUrl);
    final req = http.Request('GET', uri);
    if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
    final resp = await http.Client().send(req);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final bytes = await resp.stream.toBytes();

    var ext = p.extension(asset.downloadUrl.split('?').first).toLowerCase();
    if (ext.isEmpty || ext.length > 5) ext = '.png';
    final bgFileName = 'background$ext';
    final imagePath = await FileStorage.getFilePath(
      QuestPaths.resImage(questId, bgFileName),
    );
    final imageFile = File(imagePath);
    await imageFile.parent.create(recursive: true);
    await imageFile.writeAsBytes(bytes);

    // 2. config.json: фон квеста + стартовая нода.
    final config = <String, dynamic>{
      'id': questId,
      'title': tr('Превью фона'),
      'version': '1.0.0',
      'created': DateTime.now().toIso8601String(),
      'updated': DateTime.now().toIso8601String(),
      'author': 'Market Preview',
      'description': tr('Временный квест для превью фона из маркета'),
      'startNodeId': 'preview_node',
      'backgroundAssetId': bgFileName,
      'dimBackground': false,
      'hideNodeTitles': true,
      'backgroundAssetIdName': asset.title,
    };
    final qs = await QuestStore.defaultInstance();
    await qs.writeJson(QuestPaths.config(questId), config);

    // 3. Демо-нода: текст + пара кнопок, как в реальной сцене.
    final node = {
      'id': 'preview_node',
      'title': '',
      'content': {
        'items': [
          {
            'type': 'text',
            'id': 'preview_text_1',
            'text': tr(
                'Так фон будет выглядеть в квесте: текст читается поверх картинки, кнопки кликабельны.',
            ),
          },
          {
            'type': 'button',
            'id': 'preview_btn_1',
            'buttonText': tr('Обычная кнопка'),
            'targetNodeId': 'preview_node',
          },
          {
            'type': 'button',
            'id': 'preview_btn_2',
            'buttonText': tr('Длинный текст на кнопке не ломается'),
            'targetNodeId': 'preview_node',
          },
        ],
      },
    };
    final nodesJson = jsonEncode([node]);
    // Пишем в оба канонических расположения (движок читает nodes.json,
    // редактор — nodes/nodes.json).
    await qs.writeText(QuestPaths.nodesLegacy(questId), nodesJson);
    await qs.writeText(QuestPaths.nodesCanonical(questId), nodesJson);

    return questId;
  }

  /// Открыть плеер с временным квестом; по выходу квест удаляется.
  static Future<void> openPreview(BuildContext context, WidgetRef ref, MarketAsset asset) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      messenger.showSnackBar(SnackBar(content: Text(tr('Готовим превью...'))));
      final questId = await createPreviewQuest(asset);
      await navigator.push(
        MaterialPageRoute(builder: (_) => GameScreen(questId: questId, isTesting: true)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(trf('Ошибка превью: {p0}', {'p0': friendlyError(e)}))));
    } finally {
      await _sweepStale();
      ref.invalidate(questsProvider);
    }
  }

  /// Удалить все временные квесты-превью (в т.ч. оставшиеся после падения).
  static Future<void> _sweepStale() async {
    try {
      final root = Directory(await FileStorage.getFilePath(QuestPaths.questsDir));
      if (!await root.exists()) return;
      await for (final entity in root.list()) {
        if (entity is Directory && p.basename(entity.path).startsWith(_prefix)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
