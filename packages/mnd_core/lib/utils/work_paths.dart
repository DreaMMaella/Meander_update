// ============================================================================
//  Единый реестр путей «полки» — литературных работ (план 023).
//
//  Работы живут ОТДЕЛЬНО от квестов не только в интерфейсе: список квестов
//  строится обходом `QuestPaths.questsDir`, поэтому файл, попавший в `quests/`,
//  становится квестом для валидатора, экспорта и плеера. Отсюда вторая
//  корневая папка и свой реестр путей — по образцу QuestPaths (план 020-C6).
//
//  Все пути относительны корня документов приложения и без ведущего '/'.
// ============================================================================

/// Ветки `res/` работы — те же четыре, что у квеста.
enum WorkResourceKind { images, audio, fonts, videos }

/// Каталог работ: `works/<workId>/`.
class WorkPaths {
  WorkPaths._();

  /// Корневой каталог всех работ.
  static const String worksDir = 'works';

  static String workRoot(String workId) => 'works/$workId';

  /// Метаданные работы: тип, название, автор, обложка.
  static String meta(String workId) => 'works/$workId/meta.json';

  static String cover(String workId, String fileName) =>
      'works/$workId/res/$fileName';

  /// Оглавления по типам. Тело книги — отдельные `.md`, а не поле JSON:
  /// ошибка в одном файле не должна хоронить всю рукопись.
  static String book(String workId) => 'works/$workId/book.json';
  static String comic(String workId) => 'works/$workId/comic.json';
  static String audio(String workId) => 'works/$workId/audio.json';

  /// Каталог глав-файлов книги.
  static String textDir(String workId) => 'works/$workId/text';

  /// Файл главы; расширение задаёт модель (`Chapter.file`), здесь только путь.
  static String textFile(String workId, String fileName) =>
      'works/$workId/text/$fileName';

  /// Позиция чтения. Единственная запись, которую меняет читалка.
  static String progress(String workId) => 'works/$workId/progress.json';

  static String resDir(String workId) => 'works/$workId/res';

  static String resImagesDir(String workId) => 'works/$workId/res/images';
  static String resAudioDir(String workId) => 'works/$workId/res/audio';
  static String resVideosDir(String workId) => 'works/$workId/res/videos';
  static String resFontsDir(String workId) => 'works/$workId/res/fonts';

  static String resFile(
    String workId,
    WorkResourceKind kind,
    String fileName,
  ) => 'works/$workId/res/${kind.dirName}/$fileName';

  /// Имя файла ресурса в каталоге ветки (без пути работы).
  static String relativeResPath(WorkResourceKind kind, String fileName) =>
      'res/${kind.dirName}/$fileName';

  /// true, если путь уже относительный к корню документов (`works/...`).
  static bool isWorkPath(String path) => path.startsWith('works/');
}

extension WorkResourceKindName on WorkResourceKind {
  String get dirName => switch (this) {
    WorkResourceKind.images => 'images',
    WorkResourceKind.audio => 'audio',
    WorkResourceKind.fonts => 'fonts',
    WorkResourceKind.videos => 'videos',
  };
}
