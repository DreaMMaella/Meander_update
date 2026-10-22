// ============================================================================
//  АДАПТИВНЫЕ ПОВЕРХНОСТИ ДЛЯ ШИРОКОГО ОКНА
//
//  Приложение выросло из телефона: почти весь интерфейс — одноколоночная
//  мобильная вёрстка, меню вызываются долгим тапом и раскрываются bottom
//  sheet'ом, который на 1440 px прилипает к нижнему краю экрана. Здесь —
//  примитивы, чтобы каждый экран не изобретал свою ветку `if (wide)`.
//
//  Пороги переиспользуются из catalog_shell: маркет и хаб уже живут по ним,
//  и второй набор цифр означал бы, что на одной и той же ширине два экрана
//  ведут себя по-разному.
// ============================================================================

import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:canvas_app/shared/widgets/catalog_shell.dart';
import 'package:flutter/material.dart';

/// Средний брейкпоинт: с него окно считается «компьютерным».
const double kDesktopBreakpoint = kCatalogMediumBreakpoint;

/// Есть ли место для десктопной раскладки (рельс, вторая колонка, popup).
bool isDesktopWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// Ограничение ширины контента: лента или форма не должна тянуться на весь
/// монитор — текст такой длины не читают, а кнопки улетают за край.
class AdaptiveContent extends StatelessWidget {
  final Widget child;

  /// 720 — как у карточки квеста и настроек: уже принятая в приложении
  /// ширина читаемой колонки.
  final double maxWidth;

  /// Выравнивание при широком окне. `center` нужен формам и ленте контента,
  /// `start` — панелям, которые работают в паре с другой колонкой: иначе
  /// вторая колонка встанет посреди экрана.
  final Alignment align;

  const AdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.align = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Список/форма по-мобильному, на широком окне — диалог у курсора.
///
/// Возвращает результат так же, как `showModalBottomSheet`, поэтому миграция
/// существующих вызовов — это замена имени функции, а не переписывание
/// содержимого. [anchor] — точка, из которой открыли меню (правый клик или
/// тап по кнопке): диалог притягивается к ней, и взгляду не надо скакать.
///
/// [showDragHandle], [isScrollControlled] и [useSafeArea] работают только на
/// телефоне: у диалога нет «ручки», а его высота уже ограничена частью экрана.
///
/// [scrollable] — про крутить содержимое внутри диалога. По умолчанию нет:
/// height-constrained колонка с `Expanded` внутри должна оставаться таковой.
/// `true` передают вызовы с длинным пикером на `Column(mainAxisSize: min)` —
/// без прокрутки такой список перелился бы за 80 % высоты экрана.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 420,
  Offset? anchor,
  bool barrierDismissible = true,
  Color? backgroundColor,
  bool enableDrag = true,
  bool showDragHandle = false,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool scrollable = false,
}) {
  if (!isDesktopWidth(context)) {
    return _showBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
    );
  }
  return _showDesktopDialog<T>(
    context: context,
    builder: builder,
    title: title,
    maxWidth: maxWidth,
    anchor: anchor,
    barrierDismissible: barrierDismissible,
    backgroundColor: backgroundColor,
    scrollable: scrollable,
  );
}

Future<T?> _showBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Color? backgroundColor,
  required bool enableDrag,
  required bool showDragHandle,
  required bool isScrollControlled,
  required bool useSafeArea,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor ?? scheme.surface,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // Шит дотянут до самого низа экрана — так он выглядит целиком. Значит
    // нижний край жестовой зоны iPhone (34 pt) кто-то обязан учесть, а
    // `useSafeArea: true` Material специально оставляет низ на совести
    // вызывающей стороны (`SafeArea(bottom: false)`). Без этого последняя
    // кнопка любого меню ложится под свайп вверх и тап по неё не срабатывает.
    //
    // Верх не трогаем: он уже защищён либо Material, либо шапкой самого шита,
    // а `viewInsets` (клавиатура) — отдельное поле, его вызывающие стороны
    // считают сами и этот SafeArea не меняет.
    builder: (sheetContext) =>
        SafeArea(top: false, child: Builder(builder: builder)),
  );
}

Future<T?> _showDesktopDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String? title,
  required double maxWidth,
  required Offset? anchor,
  required bool barrierDismissible,
  required Color? backgroundColor,
  required bool scrollable,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showAppDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    // Диалог живёт поверх всего, включая in-app окно редактора: root-навигатор
    // тут же использует DesktopNavigationWrapper.
    builder: (ctx) {
      final screen = MediaQuery.sizeOf(ctx);
      final radius = BorderRadius.circular(20);
      return Align(
        // Без якоря — по центру; с якорем — у курсора, как контекстное меню.
        alignment: anchor == null
            ? Alignment.center
            : _anchorAlignment(anchor, screen),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: screen.height * 0.8,
            ),
            child: Material(
              color: backgroundColor ?? scheme.surfaceContainerHigh,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  // loose, а не tight: содержимое шита само знает свою высоту
                  // (ListView прокрутится, короткий список не растянется).
                  Flexible(
                    fit: FlexFit.loose,
                    child: scrollable
                        ? SingleChildScrollView(
                            child: Builder(builder: builder),
                          )
                        : Builder(builder: builder),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Позиция диалога относительно курсора: меню не должно вылезать за край экрана.
Alignment _anchorAlignment(Offset anchor, Size screen) {
  double fraction(double position, double extent) =>
      (position * 2 / extent - 1).clamp(-1.0, 1.0);
  return Alignment(
    fraction(anchor.dx, screen.width),
    fraction(anchor.dy, screen.height),
  );
}

/// `position` для [showMenu] от точки вызова до противоположного края экрана:
/// Material сам перепривяжет меню, чтобы оно не вылезло за границу.
RelativeRect contextMenuRect(Offset origin, Size screen) =>
    RelativeRect.fromLTRB(
      origin.dx,
      origin.dy,
      screen.width - origin.dx,
      screen.height - origin.dy,
    );

/// Контекстное меню по правой кнопке мыши (и долгим тапом на тач-экране).
///
/// Долгий тап остаётся намеренно: то же собранное приложение живёт на
/// телефоне и планшете, и отбирать у него единственный вход в меню нельзя.
class DesktopContextMenu extends StatefulWidget {
  final Widget child;
  final List<PopupMenuEntry<Object?>> Function(BuildContext context) items;

  /// Выбор в меню: [showMenu] возвращает `value` пункта, и вызывающей стороне
  /// не надо оборачивать это в свой future.
  final ValueChanged<Object?>? onSelected;

  const DesktopContextMenu({
    super.key,
    required this.child,
    required this.items,
    this.onSelected,
  });

  @override
  State<DesktopContextMenu> createState() => _DesktopContextMenuState();
}

class _DesktopContextMenuState extends State<DesktopContextMenu> {
  Offset? _lastPosition;

  Future<void> _open() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final origin =
        _lastPosition ??
        (renderBox == null
            ? Offset.zero
            : renderBox.localToGlobal(Offset.zero));
    final value = await showMenu<Object?>(
      context: context,
      position: contextMenuRect(origin, screen),
      items: widget.items(context),
    );
    if (value != null) widget.onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (event) => _lastPosition = event.globalPosition,
      onSecondaryTap: _open,
      onLongPressStart: (event) {
        _lastPosition = event.globalPosition;
        _open();
      },
      child: widget.child,
    );
  }
}

/// Подсветка строки под курсором: на телефоне её не видно, а на ПК без неё
/// карточка выглядит мёртвой — непонятно, по чему можно кликнуть.
class HoverHighlight extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const HoverHighlight({
    super.key,
    required this.child,
    this.borderRadius,
    this.onTap,
  });

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovered ? scheme.onSurface.withOpacity(0.05) : null,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}
