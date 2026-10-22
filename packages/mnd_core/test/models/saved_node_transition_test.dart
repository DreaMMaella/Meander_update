import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  test('SavedNode.transitionMode: round-trip и дефолт', () {
    final node = SavedNode(
      id: 'n1',
      chapterId: 'ch1',
      title: 'Узел',
      content: const {'items': []},
      transitionMode: 'dark',
    );

    final json = node.toJson();
    expect(json['transitionMode'], 'dark');

    final restored = SavedNode.fromJson(json);
    expect(restored.transitionMode, 'dark');
  });

  test('SavedNode.transitionMode: null по умолчанию (как в квесте)', () {
    final node = SavedNode.fromJson(const {
      'id': 'n1',
      'chapterId': 'ch1',
      'title': 'Узел',
      'content': {'items': []},
    });
    expect(node.transitionMode, isNull);
    expect(node.toJson().containsKey('transitionMode'), isFalse);
  });
}
