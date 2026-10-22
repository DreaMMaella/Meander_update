import 'package:canvas_app/plugin_host/plugin_content_type.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:canvas_app/plugin_host/lua_runtime_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обход Lua-таблицы в мосте: `next()` возвращает bool (не код статуса), а
/// индекс таблицы надо зафиксировать до `pushNil()`. Пока это было неверно,
/// любой вызов API с табличным аргументом падал или не завершался.
void main() {
  test('registerContentType читает props и вложенную canvas-таблицу', () {
    final logs = <String>[];
    final adapter = LuaRuntimeAdapter(logs.add);
    late PluginContentType registered;

    adapter.addContentTypeCallback((pluginId, type) => registered = type);
    adapter.load(
      'demo',
      '''
plugin.registerContentType('lock', {
  name = 'Замок',
  color = '#ff8800',
  renderAs = 'canvas',
  canvas = { width = 64, height = 48 },
})
''',
    );

    expect(
      logs.where((l) => l.contains('init error')),
      isEmpty,
      reason: 'инициализация плагина не должна падать',
    );
    expect(registered.id, 'lock');
    expect(registered.name, 'Замок');
    expect(registered.color, '#ff8800');
    expect(registered.isCanvas, isTrue);
    expect(registered.canvasConfig['width'], 64.0);
    expect(registered.canvasConfig['height'], 48.0);
  });

  test('injectUI доносит текст виджета из таблицы-аргумента', () {
    final logs = <String>[];
    final adapter = LuaRuntimeAdapter(logs.add);
    final injected = <String, PluginWidgetSpec>{};

    adapter.addSlotInjectCallback((pluginId, slotId, widget) {
      injected[slotId] = widget;
    });
    adapter.load(
      'demo',
      '''
plugin.injectUI('hud', { type = 'text', text = 'Съедобный камень' })
''',
    );

    expect(
      logs.where((l) => l.contains('init error')),
      isEmpty,
      reason: 'инициализация плагина не должна падать',
    );
    expect(injected['hud']?.type, PluginWidgetType.text);
    expect(injected['hud']?.text, 'Съедобный камень');
  });
}
