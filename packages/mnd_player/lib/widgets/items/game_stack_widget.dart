import 'dart:io';
import 'dart:math' as math;

import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/utils/quest_image_source.dart';
import 'package:mnd_player/utils/text_variable_resolver.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:mnd_player/services/trigger_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// «Стек» — область фиксированной высоты на всю ширину ноды, в которой дети
/// раскладываются по якорям (Godot-модель), а не линейно:
///
///   left   = anchorLeft   * W + offsetLeft
///   right  = anchorRight  * W + offsetRight
///   top    = anchorTop    * H + offsetTop
///   bottom = anchorBottom * H + offsetBottom
///
/// Ширина стека — авторская `item.stackWidth` (дефолт 720), но не больше
/// доступной ширины ноды: холст живёт в пикселях дизайна и ужимается до
/// доступного места, а не растягивается на него. Высота — `item.stackHeight`
/// (дефолт `kStackDesignHeight`). Рамка закрепления (`stackPin` + якоря)
/// растягивает холст по той оси, где якоря разведены (0..1), и оставляет
/// авторский размер там, где схлопнута. Дети рендерятся тем же
/// ContentDisplayFactory (интерактив/шрифты/триггеры наследуются).
class GameStackWidget extends ConsumerStatefulWidget {
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

  const GameStackWidget({
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

  /// Стек, у которого есть собственное действие (onPress/onSubmit, переход или
  /// скрипт ноды), перехватывает тап — триггеры детей до движка не дойдут.
  ///
  /// Формула живёт здесь, а не внутри `build`, потому что редактор стека
  /// показывает по ней предупреждение: без этого в редакторе можно было
  /// повесить триггер на объект внутри стека и молча получить нерабочую связь.
  static bool suppressesChildInteraction(ContentItem stack) {
    final hasOwnInteraction =
        TriggerPipeline.itemHasInteraction(stack) ||
        (stack.targetNodeId?.trim().isNotEmpty ?? false) ||
        (stack.scriptAssetId?.trim().isNotEmpty ?? false);
    return hasOwnInteraction;
  }

  @override
  ConsumerState<GameStackWidget> createState() => _GameStackWidgetState();
}

class _GameStackWidgetState extends ConsumerState<GameStackWidget> {
  /// Слои, чей onAppear-скрипт уже запущен за эту сессию стека.
  final Set<String> _startedAppear = {};

  /// Скругление картинок регулирует сам стек — как ряд и колонка. Без этого у
  /// автора стека не было способа получить острые углы: наследовалось только
  /// то, что пришло от ноды.
  bool? get _roundImages =>
      widget.item.childImageRoundedCorners ??
      widget.imageRoundedCornersOverride;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete();
      _runChildAppearScripts();
    });
  }

  /// onAppear у слоя. Ядро исполняет поведенческие скрипты только для
  /// верхнего уровня ноды (`next_item` в `engine.rs`), детей контейнеров оно
  /// не видит — поэтому плеер вызывает движок сам для каждого слоя.
  /// Исполнение по-прежнему в ядре (`executeBehaviour`), клиент решает лишь
  /// «когда», как это делают HUD и модалка.
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
        // Слой со сломанным скриптом не должен ронять весь стек.
      }
    }
    if (!ranAny || !mounted) return;
    // Не только дельта: скрипт слоя мог оставить в движке звуки, ссылку или
    // кадры `wait` — их сливает экран, иначе они приедут в следующей сцене.
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
    final designWidth = widget.item.stackCanvasWidth;
    final designHeight = widget.item.stackCanvasHeight;
    // Рамка закрепления растягивает холст по своей оси (`fill` — это
    // растянутая рамка 0..1 по обеим). Схлопнутая рамка оставляет авторский
    // размер: дети заданы в px дизайна, и холст обязан ужаться до неё, а не
    // разрастись до доступного места.
    final stretchWidth = widget.item.stackPinStretchesWidth;
    final stretchHeight = widget.item.stackPinStretchesHeight;
    final children = widget.item.children ?? const [];

    // Стек с триггерами блокирует интерактив детей (как контейнер).
    final bool suppressChildrenInteraction =
        widget.parentIsInteractable ||
        GameStackWidget.suppressesChildInteraction(widget.item);

    final bg = widget.item.backgroundColor;

    Widget stack = LayoutBuilder(
      builder: (context, constraints) {
        // Холст живёт в px дизайна (по умолчанию 720) — как в редакторе.
        // Доступную ширину стек получает масштабированием: раньше детей
        // раскладывали по фактической ширине ноды, и авторский offsetLeft в
        // 340 px на телефоне оказывался за краем, а высота stackHeight
        // оставалась пиксельной — картинку резало.
        final w = constraints.maxWidth.isFinite
            ? (stretchWidth
                  ? constraints.maxWidth
                  : math.min(constraints.maxWidth, designWidth))
            : designWidth;
        final scale = w / designWidth;
        // Растянутая по высоте рамка: холст в px дизайна добирается под
        // доступное место, поэтому масштаб по обеим осям остаётся равным
        // scale — без полос и без искажения. Якоря 0↔1 прижимают панель к
        // реальному краю экрана.
        final canvasHeight = stretchHeight && constraints.maxHeight.isFinite
            ? (constraints.maxHeight / scale).clamp(1.0, 20000.0)
            : designHeight;
        return Align(
          // Align отдаёт ребёнку СВОБОДные ограничения. Без него родитель
          // ноды (колонка на всю ширину) навязывает стеку свою ширину,
          // жёсткий SizedBox превращается в 360 вместо авторских 183, а
          // FittedBox с BoxFit.fill растягивает холст только по горизонтали —
          // картинка плющится в блин, текст залезает за край.
          alignment: Alignment.center,
          // Факторы = 1: если родитель отпускает место по своей воле (intrinsic
          // раскладка), стек остаётся в своих авторских px, а не раздувает
          // обёртку до доступной ширины.
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: w,
            height: canvasHeight * scale,
            child: FittedBox(
              // Равные масштабы по осям ⇒ fill == contain, но без субпиксельной
              // щели, которую contain оставил бы по краю.
              fit: BoxFit.fill,
              child: SizedBox(
                width: designWidth,
                height: canvasHeight,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Картинка-фон — под всеми слоями: z-порядок детей её не
                    // трогает, а живёт она в px холста, то есть масштабуется
                    // вместе с детьми.
                    if (widget.item.hasStackBackgroundImage)
                      Positioned.fill(
                        child: StackBackgroundFile(
                          questId: widget.questId,
                          source: widget.item.stackBackgroundPath!,
                          fit: widget.item.stackBackgroundFit,
                        ),
                      ),
                    for (final child in children)
                      _buildChild(
                        child,
                        designWidth,
                        canvasHeight,
                        suppressChildrenInteraction,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Фон: Container нужен, когда задан цвет ИЛИ картинка. borderRadius без
    // фона бессмысленно и создавало видимую «панель» в игре.
    if (bg != null || widget.item.hasStackBackgroundImage) {
      // Скругление может считать движок (`numericExprs['borderRadius']`). Без
      // числа и без формулы его нет вовсе; `Radius` не терпит отрицательных
      // значений, поэтому рамка как у остальных числовых полей.
      final bool hasRadius =
          widget.item.borderRadius != null ||
          widget.item.numericExpr('borderRadius') != null;
      final BorderRadius? radius = hasRadius
          ? BorderRadius.circular(
              resolveItemNumeric(
                ref,
                widget.item,
                'borderRadius',
                widget.questId,
                staticValue: widget.item.borderRadius ?? 0.0,
              ).clamp(0.0, 999.0),
            )
          : null;
      // Material is required directly around the content that may contain
      // ListTile (row/column children), otherwise the colored Container/
      // DecoratedBox becomes the nearest paint ancestor and Flutter reports
      // invisible ListTile ink/background warnings.
      stack = Container(
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.hardEdge,
          child: stack,
        ),
      );
    }

    // Размер LayoutBuilder считает сам: высота — это та же высота стека,
    // ужатая во столько же, во сколько дизайн-ширина ужалась до доступной.
    return stack;
  }

  Widget _buildChild(
    ContentItem child,
    double stackW,
    double stackH,
    bool suppressChildrenInteraction,
  ) {
    final rect = child.stackChildRect(stackW, stackH);
    final width = rect.width;
    final height = rect.height;
    if (width <= 0 || height <= 0) return const SizedBox.shrink();
    // Скрытый в редакторе слой не участвует ни в раскладке, ни в тапах.
    // Картинки обходят ContentDisplayFactory, поэтому проверка здесь, а не
    // только в нём.
    if (child.isHidden) return const SizedBox.shrink();

    // Все дети идут через один фабрика-путь: у картинки в стеке бокс задан
    // жёстко (якоря+offset), поэтому ей нужен BoxFit.contain — cover/fill
    // кропает или плющит. Интерактив, видимость и триггеры при этом
    // наследуются от обычных нод, а не переписываются здесь.
    final content = ContentDisplayFactory.build(
      item: child,
      questId: widget.questId,
      onInteract: widget.onInteract,
      onInputSubmitted: widget.onInputSubmitted,
      onComplete: () {},
      onTransition: widget.onTransition,
      onNavigateToNode: widget.onNavigateToNode,
      audioVolume: widget.audioVolume,
      isInsideRow: false,
      parentIsInteractable: suppressChildrenInteraction,
      imageRoundedCornersOverride: _roundImages,
      imageBoxFit: child.type == 'image' ? BoxFit.contain : null,
      textFit: 'wrap',
      fontFamily: widget.fontFamily,
      scriptEngineMode: widget.scriptEngineMode,
      engine: widget.engine,
    );

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: width,
      height: height,
      child: paintStackChildBox(
        child,
        Align(
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: widget.fontFamily),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Прозрачность, поворот и масштаб ребёнка стека вокруг центра его бокса. Общая
/// для плеера и канваса-редактора: то, что рисует редактор, обязано совпадать с
/// игрой. `transformHitTests` по умолчанию true — тап следует за картинкой,
/// а не за исходным ось-выровненным rect'ом.
Widget paintStackChildBox(ContentItem child, Widget body) {
  Widget painted = body;
  if (child.rotation != 0) {
    painted = Transform.rotate(
      angle: child.rotation * math.pi / 180,
      child: painted,
    );
  }
  // Отдельно от бокса: кнопка и текст рисуются своим размером, и тянуть их
  // за рамку бесполезно — масштаб единственная ручка, которая их меняет.
  if (child.scale != 1.0) {
    painted = Transform.scale(scale: child.scale, child: painted);
  }
  if (child.opacity < 1) {
    painted = Opacity(opacity: child.opacity.clamp(0.0, 1.0), child: painted);
  }
  return painted;
}

/// Картинка-фон холста стека. Файл ищет `QuestImageSource` — тот же резолвер,
/// что у слоя-картинки, поэтому путь, имя ресурса и uuid доезжают одинаково до
/// редактора, игры и экспорта. Общий для плеера и канваса: автор обязан видеть
/// тот же фон, что получит игрок.
class StackBackgroundFile extends StatefulWidget {
  const StackBackgroundFile({
    super.key,
    required this.questId,
    required this.source,
    this.fit = kStackBackgroundFitDefault,
  });

  final String questId;
  final String source;
  final String fit;

  @override
  State<StackBackgroundFile> createState() => _StackBackgroundFileState();
}

/// Режим фона в `BoxFit`. `tile` — это не масштаб, а повторение, поэтому у него
/// `BoxFit.none`: картинка кладётся в своих px и повторяется, как плитка.
BoxFit stackBackgroundBoxFit(String fit) => switch (fit) {
  'contain' => BoxFit.contain,
  'fill' => BoxFit.fill,
  'tile' => BoxFit.none,
  _ => BoxFit.cover,
};

class _StackBackgroundFileState extends State<StackBackgroundFile> {
  Future<File?>? _future;
  String? _futureFor;

  @override
  Widget build(BuildContext context) {
    final key = '${widget.questId}|${widget.source}';
    if (key != _futureFor) {
      _futureFor = key;
      _future = QuestImageSource.resolve(widget.questId, widget.source);
    }
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        // Нет файла — нет фона: цвет под ним остаётся видимым, а не серая
        // заплатка на весь холст.
        if (file == null) return const SizedBox.shrink();
        final tile = widget.fit == 'tile';
        return Image.file(
          file,
          fit: stackBackgroundBoxFit(widget.fit),
          repeat: tile ? ImageRepeat.repeat : ImageRepeat.noRepeat,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          isAntiAlias: true,
        );
      },
    );
  }
}
