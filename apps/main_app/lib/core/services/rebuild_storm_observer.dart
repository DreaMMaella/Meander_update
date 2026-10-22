import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ловит «шторм пересборок» — циклическую зависимость провайдеров, когда
/// провайдер косвенно инвалидирует/пересобирает сам себя (A→B→A→…).
///
/// Такой цикл синхронный: он не отдаёт управление event loop, аллоцирует
/// AsyncValue/Future на каждой итерации (отсюда рост памяти до гигабайтов)
/// и не бросает исключений — поэтому обычные логгеры его не видят.
///
/// Пишет синхронно (dart:io, не зависит от event loop) в
/// `/tmp/mnd_rebuild_storm.log` и в stderr, чтобы след оставался даже когда
/// главный изолят уже заблокирован.
class RebuildStormObserver extends ProviderObserver {
  final Map<ProviderBase<Object?>, int> _counts = {};
  int _totalEvents = 0;

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _bump(provider);
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _bump(provider);
  }

  void _bump(ProviderBase<Object?> provider) {
    final n = (_counts[provider] ?? 0) + 1;
    _counts[provider] = n;
    _totalEvents++;

    // `name` почти всегда null (провайдеры не именованы явно), поэтому
    // идентифицируем по runtimeType — в нём сохраняется дженерик-тип.
    final id = provider.name ?? provider.runtimeType.toString();

    // Первые срабатывания тоже логируем — короткий шторм, убитый OOM до
    // 1000 итераций, всё равно оставит след.
    if (n == 5 || n == 20 || n == 100 || n % 1000 == 0) {
      _log('${DateTime.now().toIso8601String()} ⚠️ REBUILD STORM: $id x$n\n');
    }

    // Глобальный снимок всей карты — ловит round-robin A→B→A→B, где ни один
    // провайдер по отдельности не дойдёт до своего порога.
    if (_totalEvents == 500 || _totalEvents % 5000 == 0) {
      final snapshot = _counts.entries
          .map((e) => '  ${e.key.name ?? e.key.runtimeType}: ${e.value}')
          .join('\n');
      _log(
        '${DateTime.now().toIso8601String()} '
        'SNAPSHOT (total=$_totalEvents):\n$snapshot\n',
      );
    }
  }

  void _log(String line) {
    try {
      File('/tmp/mnd_rebuild_storm.log').writeAsStringSync(
        line,
        mode: FileMode.append,
      );
    } catch (_) {}
    stderr.writeln(line);
  }
}
