/// UI плагинов поверх игрового экрана.
///
/// Четыре виджета: [PluginSlotLayer] — surface'ы области (`hud`/`overlay`/…),
/// [PluginScreenLayer] — полноэкранный surface (`screen`),
/// [PluginContentWidget] — айтем контента `type: 'plugin'`,
/// [PluginToastLayer] — тосты `mnd.ui.toast`. Содержимое везде декларативный
/// спек плагина ([PluginSpecView]); сама логика — в `plugin/plugin_runtime.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/plugin/plugin_runtime.dart';
import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/providers/game_session_scope.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/plugin_spec_view.dart';

/// Surface'ы плагинов в области [area] (`hud`/`overlay`/`drawer`/`menu`).
class PluginSlotLayer extends StatelessWidget {
  const PluginSlotLayer({
    super.key,
    required this.runtime,
    required this.area,
    required this.questId,
    required this.vars,
    this.nodeId = '',
  });

  final PluginRuntime runtime;
  final String area;
  final String questId;
  final Map<String, dynamic> vars;
  final String nodeId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) {
      final surfaces = runtime.surfacesIn(area);
      if (surfaces.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: switch (area) {
          'hud' => Alignment.topRight,
          'overlay' => Alignment.center,
          'drawer' => Alignment.bottomCenter,
          'menu' => Alignment.centerLeft,
          _ => Alignment.topCenter,
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: area == 'overlay' || area == 'drawer' ? 560 : 320,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: area == 'hud'
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.stretch,
            children: [
              for (final surface in surfaces)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: PluginSpecView(
                    spec: surface.spec,
                    vars: vars,
                    questId: questId,
                    onHandler: (handler, argument) => runtime.invokeHandler(
                      surface.pluginId,
                      handler,
                      argument: argument,
                      nodeId: nodeId,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Полноэкранный surface плагина: `mnd.ui.render('screen', …)`.
///
/// Модальный слой поверх всего экрана — плагин перехватывает экран (заставка,
/// самостоятельная головоломка, финальная карта). В отличие от слотов `screen`
/// переживает смену ноды: снимается плагином (`mnd.ui.close('screen')`) или
/// игрока — крестиком. Крестик рисует клиент специально: захват экрана без
/// видимого выхода был бы ловушкой, если плагин не заложил свою кнопку.
class PluginScreenLayer extends StatelessWidget {
  const PluginScreenLayer({
    super.key,
    required this.runtime,
    required this.questId,
    required this.vars,
    this.nodeId = '',
  });

  final PluginRuntime runtime;
  final String questId;
  final Map<String, dynamic> vars;
  final String nodeId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) {
      final surfaces = runtime.screenSurfaces;
      if (surfaces.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 44, 20, 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final surface in surfaces)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: PluginSpecView(
                              spec: surface.spec,
                              vars: vars,
                              questId: questId,
                              onHandler: (handler, argument) =>
                                  runtime.invokeHandler(
                                    surface.pluginId,
                                    handler,
                                    argument: argument,
                                    nodeId: nodeId,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: runtime.closeScreen,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Айтем контента `type: 'plugin'`.
///
/// Плагин выводит свой UI в цель `item:<id>` (обычно в ответ на `item_reveal`,
/// куда ему приходит весь JSON айтема вместе с `pluginData`). Пока он ничего
/// не вывел — спокойная заглушка: квест не должен разваливаться из-за плагина.
class PluginContentWidget extends ConsumerWidget {
  const PluginContentWidget({
    super.key,
    required this.item,
    required this.questId,
  });

  final ContentItem item;
  final String questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionKey = GameSessionScope.of(context, questId);
    final notifier = ref.watch(gameScreenProvider(sessionKey).notifier);
    final runtime = notifier.plugins;
    final label = item.pluginTypeId ?? item.pluginId ?? 'плагин';
    if (runtime == null) {
      return const _PluginPlaceholder(text: 'Плагин сейчас не активен');
    }
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final surface = runtime.surfaceFor('item:${item.id}');
        final spec = surface?.spec;
        if (surface == null || spec == null) {
          return _PluginPlaceholder(text: 'Плагин «$label» ничего не вывел');
        }
        return PluginSpecView(
          spec: spec,
          vars: ref.watch(gameStateProvider).variables,
          questId: questId,
          onHandler: (handler, argument) => runtime.invokeHandler(
            surface.pluginId,
            handler,
            argument: argument,
            nodeId: notifier.currentNodeId,
          ),
        );
      },
    );
  }
}

class _PluginPlaceholder extends StatelessWidget {
  const _PluginPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined, size: 18, color: theme.hintColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Показывает тосты `mnd.ui.toast` как SnackBar.
///
/// Ничего не рисует: подписывается на поток тостов сессии и живёт в Stack
/// игрового экрана (нужен `Scaffold`-предок для `ScaffoldMessenger`).
class PluginToastLayer extends ConsumerStatefulWidget {
  const PluginToastLayer({super.key, required this.questId});

  final String questId;

  @override
  ConsumerState<PluginToastLayer> createState() => _PluginToastLayerState();
}

class _PluginToastLayerState extends ConsumerState<PluginToastLayer> {
  StreamSubscription<PluginToast>? _subscription;
  Stream<PluginToast>? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessionKey = GameSessionScope.of(context, widget.questId);
    final stream =
        ref.read(gameScreenProvider(sessionKey).notifier).pluginToasts;
    if (identical(_source, stream)) return;
    _subscription?.cancel();
    _source = stream;
    _subscription = stream.listen(_show);
  }

  void _show(PluginToast toast) {
    if (!mounted || toast.text.isEmpty) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(toast.text),
        duration: toast.duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
