// Пагинация стены. Вторая страница, упавшая по сети, раньше не оставляла на
// экране ничего: список замирал на двадцатом посте, и это было неотличимо от
// «больше постов нет».

import 'dart:io';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/wall/providers/wall_paginated_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _author = 'u-1';
const int _pageSize = 20;

class _FakeApi extends ApiService {
  _FakeApi({this.failOlder = false});

  /// Отдавать ли ошибку на запросе следующей страницы.
  bool failOlder;

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    final offset = int.tryParse(queryParams?['offset'] ?? '0') ?? 0;
    if (offset > 0 && failOlder) throw const SocketException('нет сети');
    return [
      for (var i = 0; i < _pageSize; i++)
        {
          'id': 'p$offset-$i',
          'author_id': _author,
          'content': 'пост $i',
          'created_at': '2026-09-20T10:00:00.000Z',
        },
    ];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_id': 'me'}));

  test(
    'неудачная догрузка оставляет ошибку в состоянии, а не молчание',
    () async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(_FakeApi(failOlder: true)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(wallPaginatedProvider(_author).notifier);

      await notifier.loadPosts();
      expect(
        container.read(wallPaginatedProvider(_author)).posts.length,
        _pageSize,
      );
      expect(container.read(wallPaginatedProvider(_author)).error, isNull);

      await notifier.loadMore();
      final state = container.read(wallPaginatedProvider(_author));
      expect(state.isLoadingMore, isFalse);
      // Прочитанное не исчезает.
      expect(state.posts.length, _pageSize);
      // И провал виден: хвост списка рисует «Повторить».
      expect(state.error, isNotNull);
    },
  );

  test('успешный повтор догрузки гасит прежнюю ошибку', () async {
    final api = _FakeApi(failOlder: true);
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(wallPaginatedProvider(_author).notifier);

    await notifier.loadPosts();
    await notifier.loadMore();
    expect(container.read(wallPaginatedProvider(_author)).error, isNotNull);

    api.failOlder = false;
    await notifier.loadMore();
    final state = container.read(wallPaginatedProvider(_author));
    expect(state.error, isNull);
    expect(state.posts.length, _pageSize * 2);
  });
}
