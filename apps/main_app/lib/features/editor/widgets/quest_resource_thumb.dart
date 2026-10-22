import 'dart:io';

import 'package:flutter/material.dart';

import 'package:mnd_player/utils/quest_image_source.dart';

/// Миниатюра ресурса квеста по «источнику» — пути, имени из библиотеки или
/// голому файлу.
///
/// Источник резолвится асинхронно, поэтому future держим в состоянии и
/// пересоздаём только при смене источника: иначе виджет на каждой пересборке
/// списка мигает и заново читает диск (на слабом устройстве это видно в сетке
/// из сотен карточек).
class QuestResourceThumb extends StatefulWidget {
  final String questId;
  final String? source;
  final double radius;

  /// Что показать, когда картинки нет: путь не задан, формула, файл не найден.
  final Widget fallback;

  /// Ширина декодирования: в карточке пикера картинка всё равно во всю плитку
  /// не помещается, а полноразмерные кадры съедают память.
  final int cacheWidth;

  const QuestResourceThumb({
    super.key,
    required this.questId,
    required this.source,
    required this.fallback,
    this.radius = 0,
    this.cacheWidth = 360,
  });

  @override
  State<QuestResourceThumb> createState() => _QuestResourceThumbState();
}

class _QuestResourceThumbState extends State<QuestResourceThumb> {
  String? _futureFor;
  Future<File?>? _future;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = widget.source;
    if (source != _futureFor) {
      _futureFor = source;
      _future = source == null || source.trim().isEmpty
          ? null
          : QuestImageSource.resolve(widget.questId, source);
    }

    if (_future == null) return widget.fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<File?>(
        future: _future,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) {
            return snapshot.connectionState == ConnectionState.waiting
                ? ColoredBox(color: scheme.surfaceContainerHighest)
                : widget.fallback;
          }
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => widget.fallback,
          );
        },
      ),
    );
  }
}
