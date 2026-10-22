import 'package:flutter/material.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/features/resources/models/resource_file.dart';

/// Единый источник визуальных атрибутов (цвет/иконка/бейдж) для типов ресурсов.
/// Убирает дублирование, которое было размазано по карточкам.
class ResourceTypeVisuals {
  const ResourceTypeVisuals._();

  // Базовые семантические акценты типов (тон калибруется под яркость темы).
  static const Color _imageColor = Color(0xFF42A5F5); // blue
  static const Color _audioColor = Color(0xFFFFA726); // orange
  static const Color _fontColor = Color(0xFF26C6DA); // cyan
  static const Color _eventColor = Color(0xFFFFB300); // amber — триггер/событие
  static const Color _conditionColor = Color(0xFF66BB6A); // green — логика
  static const Color _genericScriptColor = Color(0xFF7E57C2); // deep purple
  static const Color _luaColor = Color(0xFF66B2FF); // голубой — Lua
  static const Color _fallbackColor = Color(0xFF9E9E9E); // grey

  /// Базовый (нетонированный) акцентный цвет ресурса.
  static Color baseColor(ResourceFile r) {
    switch (r.type) {
      case 'image':
        return _imageColor;
      case 'audio':
        return _audioColor;
      case 'font':
        return _fontColor;
      case 'script':
        return _baseScriptColor(r.scriptType);
      case 'lua':
        return _luaColor;
      default:
        return _fallbackColor;
    }
  }

  static Color _baseScriptColor(ScriptType type) {
    switch (type) {
      case ScriptType.event:
        return _eventColor;
      case ScriptType.condition:
        return _conditionColor;
      case ScriptType.generic:
        return _genericScriptColor;
    }
  }

  /// Подгоняет семантический акцент под текущую яркость темы: в светлой теме
  /// слегка затемняет (для контраста на светлом фоне), в тёмной — осветляет.
  static Color _toned(Color base, BuildContext? context) {
    if (context == null) return base;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Color.lerp(base, Colors.white, 0.14)!
        : Color.lerp(base, Colors.black, 0.10)!;
  }

  /// Акцентный цвет ресурса, адаптированный к теме (если передан [context]).
  static Color color(ResourceFile r, [BuildContext? context]) =>
      _toned(baseColor(r), context);

  static Color scriptColor(ScriptType type, [BuildContext? context]) =>
      _toned(_baseScriptColor(type), context);

  /// Иконка ресурса.
  static IconData icon(ResourceFile r) {
    switch (r.type) {
      case 'image':
        return Icons.image_rounded;
      case 'audio':
        return Icons.audiotrack_rounded;
      case 'font':
        return Icons.text_fields_rounded;
      case 'script':
        switch (r.scriptType) {
          case ScriptType.event:
            return Icons.bolt_rounded; // искра-триггер
          case ScriptType.condition:
            return Icons.account_tree_rounded; // дерево решений
          case ScriptType.generic:
            return Icons.terminal_rounded; // консоль/скрипт
        }
      case 'lua':
        return Icons.data_object_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  /// Человекочитаемое название типа (для подзаголовка в списке).
  static String typeLabel(ResourceFile r) {
    switch (r.type) {
      case 'image':
        return tr('Изображение');
      case 'audio':
        return tr('Аудио');
      case 'font':
        return tr('Шрифт');
      case 'script':
        switch (r.scriptType) {
          case ScriptType.event:
            return tr('Событие');
          case ScriptType.condition:
            return tr('Условие');
          case ScriptType.generic:
            return tr('Скрипт');
        }
      case 'lua':
        return 'Lua';
      default:
        return tr('Файл');
    }
  }

  /// Форматирует размер файла в человекочитаемый вид (КБ/МБ).
  static String formatSize(int bytes) {
    if (bytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) {
      final v = bytes / mb;
      return trf('{v} МБ', {'v': v.toStringAsFixed(v >= 10 ? 0 : 1)});
    }
    if (bytes >= kb) {
      final v = bytes / kb;
      return trf('{v} КБ', {'v': v.toStringAsFixed(v >= 10 ? 0 : 1)});
    }
    return trf('{bytes} Б', {'bytes': bytes});
  }

  /// Краткая дата изменения (напр. "3 июн" / "3 июн 2025").
  static String formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final d = date.toLocal();
    final base = '${d.day} ${monthShort(d.month)}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  /// Счётчик элементов: «1 элемент / 2 элемента / 5 элементов».
  static String pluralItems(int n) =>
      '$n ${trp(['элемент', 'элемента', 'элементов'], n)}';

  /// Счётчик блоков скрипта: «1 блок / 2 блока / 5 блоков».
  static String pluralBlocks(int n) =>
      '$n ${trp(['блок', 'блока', 'блоков'], n)}';

  /// Полезная строка метаданных для подзаголовка ресурса.
  /// Картинки/аудио: "размер · дата". Шрифты: "TTF · размер".
  /// Скрипты: "N блоков · тип · дата".
  static String metaLine(ResourceFile r) {
    final parts = <String>[];
    switch (r.type) {
      case 'script':
        parts.add(pluralBlocks(r.blockCount));
        if (r.scriptType != ScriptType.generic) parts.add(typeLabel(r));
        final date = formatDate(r.modifiedAt);
        if (date.isNotEmpty) parts.add(date);
        break;
      case 'font':
        final ext = r.extensionLabel;
        if (ext.isNotEmpty) parts.add(ext);
        final size = formatSize(r.sizeBytes);
        if (size.isNotEmpty) parts.add(size);
        break;
      default:
        final size = formatSize(r.sizeBytes);
        if (size.isNotEmpty) parts.add(size);
        final date = formatDate(r.modifiedAt);
        if (date.isNotEmpty) parts.add(date);
    }
    return parts.isEmpty ? typeLabel(r) : parts.join(' · ');
  }

  /// Короткий лейбл для бейджа.
  static String badge(ResourceFile r) {
    switch (r.type) {
      case 'image':
        return 'IMG';
      case 'audio':
        return 'SND';
      case 'font':
        return 'FONT';
      case 'script':
        switch (r.scriptType) {
          case ScriptType.event:
            return 'TRIG';
          case ScriptType.condition:
            return 'LOGIC';
          case ScriptType.generic:
            return 'SCR';
        }
      case 'lua':
        return 'LUA';
      default:
        return 'FILE';
    }
  }
}

/// Маленький бейдж типа ресурса (используется в grid-карточке).
/// Tonal-pill с иконкой + короткой меткой в M3-стиле.
class ResourceTypeBadge extends StatelessWidget {
  final ResourceFile resource;
  const ResourceTypeBadge({super.key, required this.resource});

  @override
  Widget build(BuildContext context) {
    final color = ResourceTypeVisuals.color(resource, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ResourceTypeVisuals.icon(resource),
            color: Colors.white,
            size: 11,
          ),
          const SizedBox(width: 4),
          Text(
            ResourceTypeVisuals.badge(resource),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Аватар-иконка ресурса (squircle) в плоском M3-стиле: tonal-контейнер
/// акцентного цвета с иконкой типа (без градиентов и теней).
class ResourceTypeAvatar extends StatelessWidget {
  final ResourceFile resource;
  final double size;
  const ResourceTypeAvatar({super.key, required this.resource, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = ResourceTypeVisuals.color(resource, context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: Icon(
        ResourceTypeVisuals.icon(resource),
        color: color,
        size: size * 0.52,
      ),
    );
  }
}
