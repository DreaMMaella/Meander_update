import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/services/save_game_service.dart';
import 'package:canvas_app/features/game/screens/game_screen.dart';
import 'package:canvas_app/models/save_slot_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// Вкладка «Симуляция из сейва» после выбора слота: читает слот по id из
/// провайдера сохранений и строит [GameScreen]. Пока слот не найден —
/// показывает загрузку/ошибку, не создавая второй экземпляр игры.
class GameFromSaveLoader extends ConsumerWidget {
  final String questId;
  final String slotId;
  final bool isTesting;

  const GameFromSaveLoader({
    super.key,
    required this.questId,
    required this.slotId,
    this.isTesting = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final slotsAsync = ref.watch(saveSlotsProvider(questId));

    return slotsAsync.when(
      loading: () => Scaffold(
        backgroundColor: scheme.surface,
        body: Center(child: CircularProgressIndicator(color: scheme.primary)),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              trf('Не удалось загрузить сохранение: {p0}', {'p0': friendlyError(error)}),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
      ),
      data: (slots) {
        SaveSlot? slot;
        for (final candidate in slots) {
          if (candidate.id == slotId) {
            slot = candidate;
            break;
          }
        }
        if (slot == null) {
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Center(
              child: Text(
                tr('Сохранение не найдено'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        return GameScreen(
          questId: questId,
          saveSlot: slot,
          isTesting: isTesting,
        );
      },
    );
  }
}
