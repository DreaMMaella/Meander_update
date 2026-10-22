import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_core/engine/game_engine.dart' show MeanderGameEngine;
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:mnd_player/services/trigger_pipeline.dart';
import 'package:mnd_player/utils/text_variable_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GameContainerWidget extends ConsumerStatefulWidget {
  final ContentItem item;
  final String questId;
  final Function(ContentItem) onInteract;
  final Function(String, String) onInputSubmitted;
  final VoidCallback onComplete;
  final Function(String) onTransition;
  final Function(String) onNavigateToNode;
  final double? audioVolume;
  final bool parentIsInteractable;
  final String? fontFamily;
  final String scriptEngineMode;
  final bool? imageRoundedCornersOverride;
  final MeanderGameEngine? engine;

  const GameContainerWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onInteract,
    required this.onInputSubmitted,
    required this.onComplete,
    required this.onTransition,
    required this.onNavigateToNode,
    this.audioVolume,
    this.parentIsInteractable = false,
    this.fontFamily,
    this.scriptEngineMode = kScriptEngineModeNew,
    this.imageRoundedCornersOverride,
    this.engine,
  });

  @override
  ConsumerState<GameContainerWidget> createState() =>
      _GameContainerWidgetState();
}

class _GameContainerWidgetState extends ConsumerState<GameContainerWidget> {
  /// Дети, чей onAppear-скрипт уже запущен за эту сессию контейнера.
  final Set<String> _startedAppear = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onComplete();
      }
      _runChildAppearScripts();
    });
  }

  /// onAppear у ребёнка ряда/колонки — то же, что делает стек для своих слоёв.
  /// Ядро исполняет поведенческие скрипты только для верхнего уровня ноды
  /// (`next_item` в `engine.rs`), детей контейнеров оно не видит, а
  /// `ConditionalContentWrapper` от onAppear берёт только условие видимости.
  /// Без этого шага редактор ряда/колонки предлагает слот «При появлении
  /// (onAppear)», и повешенный туда скрипт не срабатывает никогда.
  Future<void> _runChildAppearScripts() async {
    final engine = widget.engine;
    if (engine == null || !mounted) return;
    final children = widget.item.children ?? const <ContentItem>[];
    String? transitionTo;
    var ranAny = false;
    for (final child in children) {
      if (child.isHidden || !_startedAppear.add(child.id)) continue;
      if (child.scriptForEvent('onAppear') == null) continue;
      ranAny = true;
      try {
        final next = await engine.executeBehaviour(child.toJson(), 'onReveal');
        if (next != null && next.isNotEmpty && transitionTo == null) {
          transitionTo = next;
        }
      } catch (_) {
        // Ребёнок со сломанным скриптом не должен ронять весь ряд.
      }
    }
    if (!ranAny || !mounted) return;
    // Не только дельта: скрипт ребёнка мог оставить в движке звуки, ссылку
    // или кадры `wait` — их сливает экран, иначе они приедут в следующей сцене.
    await TriggerPipeline.syncAfterWidgetBehaviour(
      ref: ref,
      context: context,
      engine: engine,
    );
    if (!mounted) return;
    if (transitionTo != null) widget.onTransition(transitionTo);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.children == null || widget.item.children!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Do not block children interactions when container itself has onPress.
    // Otherwise nested buttons inside row/column can become non-functional.
    final bool hasTriggers =
        TriggerPipeline.itemHasInteraction(widget.item) ||
        (widget.item.targetNodeId != null &&
            widget.item.targetNodeId!.isNotEmpty) ||
        (widget.item.scriptAssetId != null &&
            widget.item.scriptAssetId!.isNotEmpty);

    final bool suppressChildrenInteraction =
        widget.parentIsInteractable || hasTriggers;

    CrossAxisAlignment align;
    switch (widget.item.crossAxisAlignment) {
      case 'start':
        align = CrossAxisAlignment.start;
        break;
      case 'end':
        align = CrossAxisAlignment.end;
        break;
      default:
        align = CrossAxisAlignment.center;
    }

    final textFitMode = widget.item.textFit;
    final rowTextAlignMode = widget.item.rowTextAlignment;

    // Внутренний gap. null → старое поведение (4px у ряда, 8px у колонки).
    // Формула (`numericExprs['itemSpacing']`) считается и когда статического
    // числа нет — автор мог задать только её; при нераскрытой формуле берём
    // тот же дефолт ветки, что и без формулы.
    final bool hasOwnSpacing = widget.item.itemSpacing != null;
    final bool hasSpacingFormula =
        widget.item.numericExpr('itemSpacing') != null;
    final double? customSpacing =
        hasOwnSpacing || hasSpacingFormula
        ? resolveItemNumeric(
            ref,
            widget.item,
            'itemSpacing',
            widget.questId,
            staticValue:
                widget.item.itemSpacing ??
                (widget.item.type == 'row' ? 4.0 : 8.0),
          )
        : null;
    final double rowHorizontalPad = customSpacing != null
        ? customSpacing / 2.0
        : 4.0;
    final double columnBottomPad = customSpacing != null ? customSpacing : 8.0;

    // Если контейнер явно задаёт скругление (или отключение), то используем его.
    // Иначе наследуем то, что пришло сверху (от ноды).
    final bool? effectiveRoundImages =
        widget.item.childImageRoundedCorners ??
        widget.imageRoundedCornersOverride;

    if (widget.item.type == 'row') {
      final children = widget.item.children!;
      return Row(
        crossAxisAlignment: align,
        children: List.generate(children.length, (i) {
          final childItem = children[i];
          // Если spacing задан явно — кладём padding только МЕЖДУ детьми,
          // чтобы 0 действительно давал стык без зазоров по краям.
          EdgeInsets pad;
          if (customSpacing != null) {
            pad = EdgeInsets.only(
              left: i == 0 ? 0 : rowHorizontalPad,
              right: i == children.length - 1 ? 0 : rowHorizontalPad,
            );
          } else {
            pad = const EdgeInsets.symmetric(horizontal: 4.0);
          }
          if (childItem.type == 'spacer') {
            return Padding(
              padding: pad,
              child: ContentDisplayFactory.build(
                item: childItem,
                questId: widget.questId,
                onInteract: widget.onInteract,
                onInputSubmitted: widget.onInputSubmitted,
                onComplete: () {},
                onTransition: widget.onTransition,
                onNavigateToNode: widget.onNavigateToNode,
                audioVolume: widget.audioVolume,
                isInsideRow: true,
                parentIsInteractable: suppressChildrenInteraction,
                imageRoundedCornersOverride: effectiveRoundImages,
                textFit: textFitMode,
                rowTextAlign: rowTextAlignMode,
                fontFamily: widget.fontFamily,
                scriptEngineMode: widget.scriptEngineMode,
                engine: widget.engine,
              ),
            );
          }
          return Expanded(
            flex: childItem.flex,
            child: Padding(
              padding: pad,
              child: ContentDisplayFactory.build(
                item: childItem,
                questId: widget.questId,
                onInteract: widget.onInteract,
                onInputSubmitted: widget.onInputSubmitted,
                onComplete: () {},
                onTransition: widget.onTransition,
                onNavigateToNode: widget.onNavigateToNode,
                audioVolume: widget.audioVolume,
                isInsideRow: true,
                parentIsInteractable: suppressChildrenInteraction,
                imageRoundedCornersOverride: effectiveRoundImages,
                textFit: textFitMode,
                rowTextAlign: rowTextAlignMode,
                fontFamily: widget.fontFamily,
                scriptEngineMode: widget.scriptEngineMode,
                engine: widget.engine,
              ),
            ),
          );
        }),
      );
    } else {
      // Это КОЛОНКА
      final children = widget.item.children!;
      return DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: widget.fontFamily),
        child: Column(
          crossAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(children.length, (i) {
            final childItem = children[i];
            // Аналогично ряду: при явном spacing — gap только между детьми.
            final double bottomPad;
            if (customSpacing != null) {
              bottomPad = i == children.length - 1 ? 0.0 : columnBottomPad;
            } else {
              bottomPad = 8.0;
            }
            return ContentDisplayFactory.build(
              item: childItem,
              questId: widget.questId,
              onInteract: widget.onInteract,
              onInputSubmitted: widget.onInputSubmitted,
              onComplete: () {},
              onTransition: widget.onTransition,
              onNavigateToNode: widget.onNavigateToNode,
              audioVolume: widget.audioVolume,
              isInsideRow: false,
              parentIsInteractable: suppressChildrenInteraction,
              imageRoundedCornersOverride: effectiveRoundImages,
              textFit: 'wrap',
              bottomPadding: bottomPad,
              fontFamily: widget.fontFamily,
              scriptEngineMode: widget.scriptEngineMode,
              engine: widget.engine,
            );
          }),
        ),
      );
    }
  }
}
