import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';

/// Стекло модалки. Ключ нужен рантайм-тестам: под слоем лежит контент окна,
/// а поиск по типу ColoredBox дал бы ложные совпадения.
const Key kModalScrimKey = ValueKey('modal_scrim');

/// Слой одного закреплённого стека поверх прокрутки ноды.
///
/// Рамку на экране считает модель ([ContentItem.stackPinRect]) по якорям
/// закрепления, поэтому панель стоит там, где её нарисовал автор, а не там,
/// где её поставил бы ярлык `top`/`bottom`. Модальное окно
/// ([ContentItem.isModalStack]) дополнительно кладёт под стек заглушку на весь
/// вьюпорт: нода под окном затемняется и тапы до неё не доходят — без этого
/// «модалка» была бы просто картинкой поверх играбельной сцены.
///
/// Затемнение живёт ровно столько, сколько само окно: решение то же, что у
/// `ConditionalContentWrapper` внутри [child]. Окно на триггере видимости
/// появляется не сразу, а стекло раньше него ни к чему — игрок оставался бы на
/// потемневшей ноде без единого объекта и без ответа на тапы.
///
/// Рамка отдаёт ребёнку жёсткие ограничения и совпадает с холстом по
/// построению: [ContentItem.stackPinRect] считает схлопнутую ось как размер
/// холста уже умноженным на масштаб по ширине. Расхождение означало бы, что
/// стек растягивает картинку по одной оси без второй.
class PinnedStackLayer extends ConsumerWidget {
  const PinnedStackLayer({
    super.key,
    required this.item,
    required this.viewport,
    required this.child,
    this.offset = Offset.zero,
    this.onDismiss,
    this.engine,
  });

  final ContentItem item;

  /// Вьюпорт ноды без системных вырезов (SafeArea) — от него считаются доли
  /// якорей и px смещений.
  final Size viewport;
  final Widget child;

  /// Сдвиг рамки: на широком окне игра центрируется в колонку 720 px, и
  /// закреплённая панель обязана стоять в этой колонке, а не у края окна.
  final Offset offset;

  /// Закрытие окна тапом вне рамки. `null` — закрыть нельзя (у слоя нет
  /// состояния, в котором это работает).
  final VoidCallback? onDismiss;

  /// Движок для проверки условия видимости окна. `null` — без движка условию
  /// негде считаться, и контент фабрики собирается как обычный: стекло тогда
  /// на месте.
  final MeanderGameEngine? engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rect = item.stackPinRect(viewport).shift(offset);
    final scrim = item.stackScrimOpacity;
    return Stack(
      // Рамка может уходить за экран (шторка, панель под вырез) — обрезать её
      // нечем: сам слой лежит в Positioned.fill, а клиппинг съел бы тень.
      clipBehavior: Clip.none,
      children: [
        if (item.isModalStack && _windowIsShown(ref))
          // Прозрачная при scrim = 0, но всё равно заглушка: окно либо
          // перехватывает ввод, либо это не окно.
          Positioned.fill(
            key: kModalScrimKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: item.stackDismissesOnTapOutside ? onDismiss : () {},
              child: ColoredBox(color: Color.fromRGBO(0, 0, 0, scrim)),
            ),
          ),
        Positioned.fromRect(rect: rect, child: child),
      ],
    );
  }

  /// Видно ли окно прямо сейчас — по тем же трём причинам, по каким
  /// `ConditionalContentWrapper` гасит его содержимое: статический флаг
  /// редактора, `set_visible` из скрипта и условие триггера видимости.
  ///
  /// «Скрыть» (`hidden`) тоже не показ: контент при этом прозрачный, а стекло
  /// осталось бы — та же потемневшая пустота.
  bool _windowIsShown(WidgetRef ref) {
    if (item.isHidden) return false;
    // Переменные движка читает условие окна, поэтому подписка полная: стекло
    // обязано уйти и вернуться вместе с самим окном.
    final variables = ref.watch(gameStateProvider).variables;
    if (engineVisibilityOf(variables, item.id) != EngineVisibility.visible) {
      return false;
    }
    if (item.scriptForEvent('onAppear') == null) return true;
    // Ошибка условия или нет движка — то же, что делает обёртка контента:
    // окно показываем (без движка условию негде считаться).
    try {
      return engine?.evaluateVisibility(
            item.toJson(),
            allowMutation: false,
          ) ??
          true;
    } catch (_) {
      return true;
    }
  }
}
