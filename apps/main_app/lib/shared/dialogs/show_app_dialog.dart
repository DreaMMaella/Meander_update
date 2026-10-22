import 'package:flutter/material.dart';

/// Показ модального диалога как оверлея внутри текущего окна.
///
/// Полный аналог `showDialog`, но НЕ зависящий от экспериментального
/// windowing-режима Flutter. В Flutter 3.38+ при включённом флаге
/// `FLUTTER_ENABLED_FEATURE_FLAGS=windowing` стандартный `showDialog`
/// уводит диалог в отдельное нативное окно ОС (без затемняющего барьера).
/// Этот хелпер пушит обычный [DialogRoute] напрямую через [Navigator.push],
/// минуя windowing-ветку `showRawDialog` — диалог всегда рендерится
/// модальным оверлеем с барьером, а multi-window редактора продолжает работать.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  assert(debugCheckHasMaterialLocalizations(context));

  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  final CapturedThemes themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );

  final DialogThemeData dialogTheme = DialogTheme.of(context);

  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      barrierColor:
          barrierColor ??
          dialogTheme.barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
    ),
  );
}
