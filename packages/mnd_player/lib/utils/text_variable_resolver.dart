import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';

import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/providers/game_session_scope.dart';

/// Подставить `{variable}`/`{expression}` в тексте.
///
/// Единый путь для всех текстовых виджетов:
/// - **engine-mode** (основной): вычисляет выражения через синхронный FFI
///   движка (`engine.evaluateSync`) — движок остаётся единственным источником
///   истины, клиент ничего не вычисляет сам.
/// - **legacy-mode** (без движка): `ScriptExecutor.evaluateExpression` против
///   Dart `GameStateNotifier`.
///
/// `collapseDoubleBraces` — чистая текстовая предобработка (`{{x}}` → `{x}`),
/// остаётся на клиенте (не зависит от состояния).
String resolveTextVariables(
  WidgetRef ref,
  String text,
  String? questId,
  GameStateNotifier notifier, {
  GameSessionKey? sessionKey,
}) {
  final collapsed = ScriptExecutor.collapseDoubleBraces(text);

  final engine = _sessionEngine(ref, questId, sessionKey);

  if (engine != null) {
    return ScriptExecutor.substitutePlaceholders(collapsed, (expression) {
      final value = engine.evaluateSync(expression);
      return formatScriptValue(value);
    });
  }

  // Legacy fallback.
  return ScriptExecutor.substitutePlaceholders(
    collapsed,
    (expression) =>
        formatScriptValue(ScriptExecutor.evaluateExpression(expression, notifier)),
  );
}

/// Движок текущей сцены, если он есть и жив. Вне `GameScreen` (нет ключа
/// сессии или провайдера) — `null`, и вызывающий уходит на legacy-путь.
MeanderGameEngine? _sessionEngine(
  WidgetRef ref,
  String? questId,
  GameSessionKey? sessionKey,
) {
  if (questId == null) return null;
  final key = sessionKey ?? GameSessionScope.maybeOf(ref.context);
  // Не создаём standalone-провайдер вхолостую: каждый ref.read(autoDispose)
  // без подписки сразу диспоузится → шторм CREATING/DISPOSING (лог: standalone
  // hash меняется каждый кадр). Если ключа нет (вне GameScreen) — legacy-путь.
  if (key == null) return null;
  try {
    // Не создавать новый notifier, если провайдера ещё нет (exists == false).
    // Иначе каждый build текста плодит и тут же хоронит провайдер.
    final container = ProviderScope.containerOf(ref.context, listen: false);
    if (!container.exists(gameScreenProvider(key))) return null;
    final engine = ref.read(gameScreenProvider(key).notifier).engine;
    if (engine == null || engine.isDisposed) return null;
    return engine;
  } catch (_) {
    return null;
  }
}

/// Актуальный путь картинки у [item]: сначала то, что назначил скрипт блоком
/// `set_image`, затем формула (`{pic}`, `res/{level}.png`) — её раскрывает тот
/// же движок, что и текст, — и только потом статический `resourcePath`.
///
/// Вызывать из `build`: подписку на состояние заводим только когда айтему есть
/// что пересчитывать — без формулы и без переопределения картинка статична.
String? resolveItemResourcePath(
  WidgetRef ref,
  ContentItem item,
  String questId, {
  GameSessionKey? sessionKey,
}) {
  final overridden = ref.watch(
    gameStateProvider.select(
      (state) => itemSourceOverride(state.variables, item.id),
    ),
  );
  if (overridden != null) return overridden;
  if (!item.hasResourceExpr) return item.resourcePath;
  // Формула может читать сколько угодно переменных — следим за состоянием.
  ref.watch(gameStateProvider);
  return item.resolveResourcePath(
    evaluatedExpr: resolveTextVariables(
      ref,
      item.resourceExpr!,
      questId,
      ref.read(gameStateProvider.notifier),
      sessionKey: sessionKey ?? GameSessionScope.maybeOf(ref.context),
    ),
  );
}

/// Форма формулы числового поля: `{hp}/2 + 16` приводим к выражению `hp/2 + 16`.
///
/// Текстовый резолвер подставляет только содержимое фигурных скобок и не
/// считает арифметику во всей строке, поэтому числовую формулу отдаём движку
/// целиком, а скобки — которые автор привык ставить по образу `{текст}` —
/// съедаем здесь.
@visibleForTesting
String normalizeNumericFormula(String formula) {
  final collapsed = ScriptExecutor.collapseDoubleBraces(formula);
  return collapsed.replaceAll(_bracePattern, '').trim();
}

final RegExp _bracePattern = RegExp('[{}]');

/// Число из того, что вернул движок: `num`, строка с числом — годятся; bool,
/// null, `null`, текст или имя ненайденной переменной — «значения нет», и
/// вызывающий берёт статическое число.
@visibleForTesting
double? numericValueOf(dynamic evaluated) {
  if (evaluated is num) return evaluated.toDouble();
  if (evaluated is String) return double.tryParse(evaluated.trim());
  return null;
}

/// Вычислить формулу [formula] как число. `-1` и `1e9` — тоже числа, их не
/// режем: ограничение на размер поля накладывает виджет.
double? evaluateNumericFormula(
  WidgetRef ref,
  String formula,
  String? questId,
  GameStateNotifier notifier, {
  GameSessionKey? sessionKey,
}) {
  final expression = normalizeNumericFormula(formula);
  if (expression.isEmpty) return null;
  final engine = _sessionEngine(ref, questId, sessionKey);
  try {
    if (engine != null) {
      return numericValueOf(engine.evaluateSync(expression));
    }
    return numericValueOf(
      ScriptExecutor.evaluateExpression(expression, notifier),
    );
  } catch (_) {
    // Сломанная формула не роняет сцену: автор мог написать её наполовину.
    return null;
  }
}

/// Число поля [field] у айтема **сейчас**: формула из `numericExprs` считается
/// движком при каждом изменении состояния, без формулы и при нераскрытом
/// результате — статическое [staticValue] (он же превью в редакторе).
///
/// Вызывать из `build`: подписку на состояние заводим только когда айтему есть
/// что пересчитывать — без формулы поле статично.
double resolveItemNumeric(
  WidgetRef ref,
  ContentItem item,
  String field,
  String questId, {
  required double staticValue,
  GameSessionKey? sessionKey,
}) {
  final formula = item.numericExpr(field);
  if (formula == null) return staticValue;
  // Формула может читать сколько угодно переменных — следим за состоянием.
  ref.watch(gameStateProvider);
  return item.resolveNumeric(
    field,
    evaluatedValue: evaluateNumericFormula(
      ref,
      formula,
      questId,
      ref.read(gameStateProvider.notifier),
      sessionKey: sessionKey ?? GameSessionScope.maybeOf(ref.context),
    ),
    staticValue: staticValue,
  );
}
