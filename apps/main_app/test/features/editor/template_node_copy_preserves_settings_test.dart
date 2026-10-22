// Инвариант: копия ноды из шаблона сохраняет ВСЕ настройки исходной ноды.
//
// buildNode/buildChapter долго пересобирали ноду перечислением полей, и
// каждое незаписанное поле молча пропадало: видео-фон, размытие, отступы,
// переход, ограничения ноды, цвет. Копия строится copyWith поверх исходной
// ноды, поэтому новое поле модели переезжает само; сбрасывается только то,
// что в копии невалидно — связь с мастер-шаблоном и ссылка на ноду, которой
// в копии нет.
import 'package:canvas_app/features/editor/utils/template_applier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/saved_node.dart';

SavedNode _richNode() => SavedNode(
  id: 'node-src',
  chapterId: 'chapter-src',
  title: 'Сцена с видео',
  content: const {
    'items': [
      {'id': 'item-1', 'type': 'text', 'content': 'Привет'},
    ],
  },
  x: 12,
  y: 34,
  color: 0xFF00FF00,
  backgroundAssetId: 'res/images/still.jpg',
  backgroundVideoAssetId: 'res/images/intro.mp4',
  backgroundVideoVolume: 0.4,
  backgroundVideoLoop: false,
  backgroundVideoMuted: true,
  backgroundVideoFit: 'contain',
  backgroundBlur: 18,
  scriptAssetId: 'scripts/intro.json',
  backgroundAudioId: 'res/audio/amb.mp3',
  backgroundAudioVolume: 0.8,
  allowSave: false,
  allowInventoryAccess: false,
  itemSpacing: 6,
  imageRoundedCorners: false,
  transitionMode: 'page',
);

void _expectSettingsCarried(SavedNode copy) {
  expect(copy.color, 0xFF00FF00, reason: 'цвет ноды потерян при вставке');
  expect(copy.backgroundAssetId, 'res/images/still.jpg');
  expect(
    copy.backgroundVideoAssetId,
    'res/images/intro.mp4',
    reason: 'шаблон вставился без видео-фона',
  );
  expect(copy.backgroundVideoVolume, 0.4);
  expect(copy.backgroundVideoLoop, isFalse);
  expect(copy.backgroundVideoMuted, isTrue);
  expect(copy.backgroundVideoFit, 'contain');
  expect(copy.backgroundBlur, 18);
  expect(copy.scriptAssetId, 'scripts/intro.json');
  expect(copy.backgroundAudioId, 'res/audio/amb.mp3');
  expect(copy.backgroundAudioVolume, 0.8);
  expect(copy.allowSave, isFalse, reason: 'настройка сохранений сбилась');
  expect(copy.allowInventoryAccess, isFalse);
  expect(copy.itemSpacing, 6);
  expect(copy.imageRoundedCorners, isFalse);
  expect(copy.transitionMode, 'page');
}

void main() {
  group('копия ноды из шаблона', () {
    test('buildNode переносит настройки ноды', () {
      final source = _richNode();
      final template = TemplateApplier.makeFromNode(
        name: 'Шаблон',
        node: source,
      );

      final copy = TemplateApplier.buildNode(
        template,
        chapterId: 'chapter-new',
        x: 100,
        y: 200,
      );

      expect(copy, isNotNull);
      _expectSettingsCarried(copy!);
      expect(copy.chapterId, 'chapter-new');
      expect(copy.x, 100);
      expect(copy.y, 200);
      expect(copy.id, isNot(source.id));
    });

    test('копия не наследует связь ноды-мастера с шаблоном', () {
      final master = _richNode().copyWith(
        templateRef: 'tpl-master',
        templateVersion: 3,
        isTemplateMaster: true,
      );
      final template = TemplateApplier.makeFromNode(
        name: 'Шаблон',
        node: master,
      );

      final copy = TemplateApplier.buildNode(
        template,
        chapterId: 'chapter-new',
        x: 0,
        y: 0,
      );

      expect(copy?.hasTemplateLink, isFalse);
      expect(copy?.isTemplateMaster, isFalse);
    });

    test('ссылка таймера на другую ноду не переезжает в копию', () {
      final withLink = _richNode().copyWith(defaultActionNodeId: 'node-other');
      final template = TemplateApplier.makeFromNode(
        name: 'Шаблон',
        node: withLink,
      );

      final copy = TemplateApplier.buildNode(
        template,
        chapterId: 'chapter-new',
        x: 0,
        y: 0,
      );

      expect(copy?.defaultActionNodeId, isNull);
    });

    test('buildChapter переносит настройки и переводит внутренние ссылки', () {
      // Таймер ссылается на саму себя: id копии новый, ссылка обязана
      // переехать на копию, а не остаться на ноде исходной главы.
      final source = _richNode().copyWith(defaultActionNodeId: 'node-src');
      final template = TemplateApplier.makeFromChapter(
        name: 'Глава',
        nodes: [source],
        connections: const [
          {'id': 'c1', 'fromId': 'node-src', 'toId': 'node-src'},
        ],
      );

      final copy = TemplateApplier.buildChapter(
        template,
        targetChapterId: 'chapter-new',
      )!.nodes.single;

      _expectSettingsCarried(copy);
      expect(copy.chapterId, 'chapter-new');
      expect(copy.id, isNot(source.id));
      expect(
        copy.defaultActionNodeId,
        copy.id,
        reason: 'внутренняя ссылка не переведена на копию ноды',
      );
    });

    test('ссылка на ноду вне копии главы снимается', () {
      final source = _richNode().copyWith(defaultActionNodeId: 'node-outside');
      final template = TemplateApplier.makeFromChapter(
        name: 'Глава',
        nodes: [source],
        connections: const [],
      );

      final copy = TemplateApplier.buildChapter(
        template,
        targetChapterId: 'chapter-new',
      )!.nodes.single;

      expect(copy.defaultActionNodeId, isNull);
    });
  });

  test('шаблон главы хранит все настройки ноды', () {
    final template = TemplateApplier.makeFromChapter(
      name: 'Глава',
      nodes: [_richNode()],
      connections: const [],
    );

    final stored = (template.payload['nodes'] as List).cast<Map>().single;
    expect(stored['backgroundVideoAssetId'], 'res/images/intro.mp4');
    expect(stored['backgroundBlur'], 18.0);
    expect(stored['transitionMode'], 'page');
  });
}
