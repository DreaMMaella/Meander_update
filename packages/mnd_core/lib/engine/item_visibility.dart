/// Переопределения видимости, которые назначает скрипт.
///
/// Блок `set_visible` пишет в служебную переменную движка
/// `_internal_item_hidden` — вида `{itemId: "hidden" | "gone" | "visible"}`.
/// Держим ключ и чтение здесь, чтобы клиент не выдумывал имя переменной сам, а
/// модель айтема не мутировалась: значение живёт в состоянии игры, поэтому
/// попадает в сейв и восстанавливается из него.
///
/// «Не видно» — это два разных поведения, и клиент обязан различать их сам:
/// [EngineVisibility.hidden] оставляет айтему его место в раскладке,
/// [EngineVisibility.gone] выводит его из раскладки, и соседи подтягиваются.
library;

const String kItemHiddenVar = '_internal_item_hidden';

/// Как айтем выглядит для клиента после команд скрипта.
enum EngineVisibility {
  /// Скрипт айтем не трогал или показал его — рисуем как в модели квеста.
  visible,

  /// «Скрыть»: не видно и не кликабельно, но место занято.
  hidden,

  /// «Убрать»: айтема нет ни на экране, ни в раскладке.
  gone,
}

/// Видимость айтема [itemId] по команде скрипта.
///
/// Различает четыре случая: скрипт сказал скрыть, сказал убрать, сказал
/// показать и не прикасался вовсе — последнее значит «как в модели квеста».
EngineVisibility engineVisibilityOf(
  Map<String, dynamic> variables,
  String itemId,
) {
  final overrides = variables[kItemHiddenVar];
  if (overrides is! Map) return EngineVisibility.visible;
  return _parse(overrides[itemId]);
}

/// Строки — текущий формат ядра. Bool остаётся ради сейвов, записанных до
/// разделения «скрыть/убрать»: там `true` значило «не видно», и не видно было
/// именно со схлопыванием ряда.
EngineVisibility _parse(Object? raw) => switch (raw) {
  'hidden' => EngineVisibility.hidden,
  'gone' => EngineVisibility.gone,
  true => EngineVisibility.gone,
  _ => EngineVisibility.visible,
};
