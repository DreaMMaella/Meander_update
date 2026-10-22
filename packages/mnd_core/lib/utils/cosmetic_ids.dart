import 'dart:convert';

/// id предмета экипировки профиля из сырого jsonb `cosmetics`.
///
/// Каталог косметики и её отрисовка живут в приложении, поэтому модели пакета
/// хранят только id: бэкенд отдаёт всю карту одним полем (`author_cosmetics`),
/// и новый слот попадает в ленту без правки модели.
String? cosmeticSlotId(Object? raw, String slot) {
  Map<Object?, Object?>? map;
  if (raw is Map) {
    map = raw;
  } else if (raw is String && raw.trim().startsWith('{')) {
    // Старый драйвер отдаёт jsonb как строку.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) map = decoded;
    } catch (_) {
      map = null;
    }
  }
  final value = map?[slot];
  return value is String && value.isNotEmpty ? value : null;
}
