import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_core/utils/work_paths.dart';

void main() {
  group('WorkPaths', () {
    test('всё внутри works/<id> и ничего в quests/', () {
      expect(WorkPaths.workRoot('w1'), 'works/w1');
      expect(WorkPaths.meta('w1'), 'works/w1/meta.json');
      expect(WorkPaths.book('w1'), 'works/w1/book.json');
      expect(WorkPaths.comic('w1'), 'works/w1/comic.json');
      expect(WorkPaths.audio('w1'), 'works/w1/audio.json');
      expect(WorkPaths.textFile('w1', '01.md'), 'works/w1/text/01.md');
      expect(WorkPaths.progress('w1'), 'works/w1/progress.json');
      expect(
        WorkPaths.resFile('w1', WorkResourceKind.images, 'p1.png'),
        'works/w1/res/images/p1.png',
      );
      expect(
        WorkPaths.relativeResPath(WorkResourceKind.audio, 'a.mp3'),
        'res/audio/a.mp3',
      );
      expect(
        WorkPaths.resFile('w1', WorkResourceKind.fonts, 'x.ttf'),
        'works/w1/res/fonts/x.ttf',
      );
      expect(WorkPaths.isWorkPath('works/w1/meta.json'), isTrue);
      expect(WorkPaths.isWorkPath('quests/w1/config.json'), isFalse);
    });
  });

  group('WorkKind', () {
    test('неизвестный тип не роняет и не теряет работу', () {
      expect(WorkKind.parse('comic'), WorkKind.comic);
      expect(WorkKind.parse('audio'), WorkKind.audiobook);
      expect(WorkKind.parse('romance'), WorkKind.book);
      expect(WorkKind.parse(null), WorkKind.book);
    });

    test('метка для списка', () {
      expect(WorkKind.poem.label, 'Стихи');
    });
  });

  group('WorkMeta', () {
    test('round-trip', () {
      final meta = WorkMeta(
        id: 'w1',
        kind: WorkKind.comic,
        title: 'Ночная смена',
        author: 'он',
        genres: const ['хоррор'],
        coverPath: 'res/cover.png',
        created: DateTime.utc(2026, 9, 25),
      );
      final decoded = WorkMeta.fromJson(meta.toJson());
      expect(decoded, isA<WorkMeta>());
      expect(decoded.id, 'w1');
      expect(decoded.kind, WorkKind.comic);
      expect(decoded.title, 'Ночная смена');
      expect(decoded.genres, ['хоррор']);
      expect(decoded.coverPath, 'res/cover.png');
      expect(decoded.created, DateTime.utc(2026, 9, 25));
    });

    test('битая строка вместо даты — работа открывается', () {
      final meta = WorkMeta.fromJson({
        'id': 'w1',
        'title': 'X',
        'created': 'вчера',
      });
      expect(meta.created, isNull);
      expect(meta.kind, WorkKind.book);
    });

    test('snake_case со сервера читается', () {
      final meta = WorkMeta.fromJson({
        'id': 'w1',
        'kind': 'audiobook',
        'cover_path': 'res/c.jpg',
        'author_id': 'me',
      });
      expect(meta.kind, WorkKind.audiobook);
      expect(meta.coverPath, 'res/c.jpg');
      expect(meta.authorId, 'me');
    });
  });

  group('WorkOutline', () {
    test('книга: главы туда и обратно, озвучка главы сохраняется', () {
      const outline = WorkOutline(
        chapters: [
          TextChapter(id: 'c1', title: 'Глава 1', file: 'text/01.md'),
          TextChapter(
            id: 'c2',
            title: 'Глава 2',
            file: 'text/02.md',
            audio: 'res/audio/ch02.mp3',
          ),
        ],
      );
      final decoded = WorkOutline.fromJson(
        WorkKind.book,
        outline.toJson(WorkKind.book),
      );
      expect(decoded.chapters.map((c) => c.title), ['Глава 1', 'Глава 2']);
      expect(decoded.chapters.first.audio, isNull);
      expect(decoded.chapters.last.audio, 'res/audio/ch02.mp3');
      expect(decoded.pageCount, 2);
    });

    test('комикс: порядок страниц = порядок массива', () {
      final decoded = WorkOutline.fromJson(WorkKind.comic, {
        'pages': [
          {'id': 'p1', 'image': 'res/images/p001.png', 'caption': ''},
          {'id': 'p2', 'image': 'res/images/p002.png', 'caption': 'тише'},
        ],
      });
      expect(decoded.pages.map((p) => p.image), [
        'res/images/p001.png',
        'res/images/p002.png',
      ]);
      expect(decoded.chapters, isEmpty);
      expect(decoded.pageCount, 2);
    });

    test('аудиокнига: длительность не обязана быть числом', () {
      final decoded = WorkOutline.fromJson(WorkKind.audiobook, {
        'tracks': [
          {'id': 't1', 'file': 'res/audio/1.mp3', 'durationSeconds': '1830'},
          {'id': 't2', 'file': 'res/audio/2.mp3'},
        ],
      });
      expect(decoded.tracks.first.durationSeconds, 1830);
      expect(decoded.tracks.last.durationSeconds, 0);
      expect(decoded.tracks.last.title, 'Дорожка');
    });

    test('мусор вместо списка не роняет чтение', () {
      final decoded = WorkOutline.fromJson(WorkKind.book, {
        'chapters': [
          'не объект',
          {'id': 'c1', 'title': 'q', 'file': 'f'},
        ],
      });
      expect(decoded.chapters.length, 1);
    });

    test('стихи используют главы, а не страницы', () {
      const outline = WorkOutline(
        chapters: [TextChapter(id: 'p1', title: 'Осень', file: 'text/01.md')],
      );
      final decoded = WorkOutline.fromJson(
        WorkKind.poem,
        outline.toJson(WorkKind.poem),
      );
      expect(decoded.chapters.single.title, 'Осень');
      expect(decoded.pages, isEmpty);
    });
  });

  group('reorder', () {
    test('перенос страницы вниз не сдвигает остальных лишним шагом', () {
      expect(reorder([1, 2, 3, 4], 0, 2), [2, 3, 1, 4]);
    });

    test('перенос вверх', () {
      expect(reorder(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    });

    test('палец махнул за край — всё остаётся внутри', () {
      expect(reorder([1, 2, 3], 0, 9), [2, 3, 1]);
      expect(reorder([1, 2, 3], -5, 1), [2, 1, 3]);
      expect(reorder(<int>[], 0, 0), isEmpty);
    });

    test('исходный список не меняется', () {
      final source = [1, 2, 3];
      final next = reorder(source, 2, 0);
      expect(source, [1, 2, 3]);
      expect(next, [3, 1, 2]);
    });
  });

  group('ReadingProgress', () {
    test('пустой файл — начало, а не падение', () {
      const progress = ReadingProgress();
      final decoded = ReadingProgress.fromJson({});
      expect(decoded.pageIndex, progress.pageIndex);
      expect(decoded.scrollFraction, progress.scrollFraction);
      expect(decoded.trackIndex, progress.trackIndex);
      expect(decoded.updatedAt, isNull);
    });

    test('round-trip с долей прокрутки', () {
      const progress = ReadingProgress(
        pageIndex: 4,
        scrollFraction: 0.25,
        positionSeconds: 61,
      );
      final decoded = ReadingProgress.fromJson(progress.toJson());
      expect(decoded.pageIndex, 4);
      expect(decoded.scrollFraction, 0.25);
      expect(decoded.positionSeconds, 61);
    });

    test('обновление позиции не теряет дорожку', () {
      const progress = ReadingProgress(trackIndex: 2, positionSeconds: 10);
      final next = progress.copyWith(positionSeconds: 40);
      expect(next.trackIndex, 2);
      expect(next.positionSeconds, 40);
    });
  });
}
