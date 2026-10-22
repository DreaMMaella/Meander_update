// Демо-квесты спрятаны из общего каталога, но в поиске их прятать не за чем:
// автор выкладывает демо именно ради отзывов, а человек в строке поиска ищет
// слово, а не разглядывает витрину. Проверяем, что фильтр снимает их с экрана
// только при просмотре каталога.
import 'package:canvas_app/features/market/providers/market_provider.dart';
import 'package:canvas_app/models/market_quest_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String id, {required bool demo}) => <String, dynamic>{
  'id': id,
  'title': 'Квест $id',
  'download_url': 'https://example.test/$id.zip',
  'description': '',
  'author_id': 'author-1',
  'author_name': 'Автор',
  'downloads_count': 0,
  'like_count': 0,
  'dislike_count': 0,
  'is_demo': demo,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};

void main() {
  final full = MarketQuest.fromJson(_json('full', demo: false));
  final demo = MarketQuest.fromJson(_json('demo', demo: true));
  final quests = [full, demo];

  test('в поиске остаются и демо, и обычные квесты', () {
    expect(
      visibleMarketQuests(
        quests: quests,
        searchQuery: 'квест',
        selectedCategory: null,
      ),
      contains(demo),
    );
  });

  test('в категории демо показываем демо', () {
    expect(
      visibleMarketQuests(
        quests: quests,
        searchQuery: '',
        selectedCategory: 'demo',
      ),
      contains(demo),
    );
  });

  test('обычный каталог демо не показывает', () {
    expect(
      visibleMarketQuests(
        quests: quests,
        searchQuery: '',
        selectedCategory: null,
      ),
      isNot(contains(demo)),
    );
    expect(
      visibleMarketQuests(
        quests: quests,
        searchQuery: '',
        selectedCategory: 'horror',
      ),
      isNot(contains(demo)),
    );
  });

  test('пробел в поиске каталог не разблокирует', () {
    expect(
      visibleMarketQuests(
        quests: quests,
        searchQuery: '   ',
        selectedCategory: null,
      ),
      isNot(contains(demo)),
    );
  });
}
