import 'dart:io';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:http/http.dart' as http;
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/quest_store.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/features/hub/widgets/preset_market.dart';

class LibraryItem {
  final String id; // asset id
  final String kind;
  final String title;
  final String fileUrl;
  final String? coverUrl;
  final String? localPath; // relative to app docs, e.g. my_library/sfx/xxx.mp3
  final String license;
  final String? authorName;
  final String? authorId;
  final bool authorIsVerified;
  final int addedAt;

  LibraryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.fileUrl,
    this.coverUrl,
    this.localPath,
    required this.license,
    this.authorName,
    this.authorId,
    this.authorIsVerified = false,
    required this.addedAt,
  });

  factory LibraryItem.fromMarketAsset(MarketAsset a, {String? localPath}) {
    return LibraryItem(
      id: a.id,
      kind: a.kind,
      title: a.title,
      fileUrl: a.fileUrl,
      coverUrl: a.coverUrl,
      localPath: localPath,
      license: a.license,
      authorName: a.authorName,
      authorId: a.authorId,
      authorIsVerified: a.authorIsVerified,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        fileUrl: j['fileUrl'] as String,
        coverUrl: j['coverUrl'] as String?,
        localPath: j['localPath'] as String?,
        license: j['license'] as String? ?? 'CC-BY',
        authorName: j['authorName'] as String?,
        authorId: j['authorId'] as String?,
        authorIsVerified: j['authorIsVerified'] == true,
        addedAt: j['addedAt'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'fileUrl': fileUrl,
        'coverUrl': coverUrl,
        'localPath': localPath,
        'license': license,
        'authorName': authorName,
        'authorId': authorId,
        'authorIsVerified': authorIsVerified,
        'addedAt': addedAt,
      };

  MarketAsset toMarketAsset() => MarketAsset(
        id: id,
        kind: kind,
        title: title,
        fileUrl: fileUrl,
        coverUrl: coverUrl,
        license: license,
        authorName: authorName,
        authorId: authorId,
        authorIsVerified: authorIsVerified,
      );
}

class MusicLibraryItem {
  final String id;
  final String title;
  final String performer;
  final String fileUrl;
  final String? coverUrl;
  final String? localPath;
  final String license;
  final String? authorName;
  final String? authorId;
  final bool authorIsVerified;
  final int addedAt;

  MusicLibraryItem({
    required this.id,
    required this.title,
    required this.performer,
    required this.fileUrl,
    this.coverUrl,
    this.localPath,
    required this.license,
    this.authorName,
    this.authorId,
    this.authorIsVerified = false,
    required this.addedAt,
  });

  factory MusicLibraryItem.fromTrack(MusicTrack t, {String? localPath}) => MusicLibraryItem(
        id: t.id,
        title: t.title,
        performer: t.performer,
        fileUrl: t.fileUrl,
        coverUrl: t.coverUrl,
        localPath: localPath,
        license: t.license,
        authorName: t.authorName,
        authorId: t.authorId,
        authorIsVerified: t.authorIsVerified,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );

  factory MusicLibraryItem.fromJson(Map<String, dynamic> j) => MusicLibraryItem(
        id: j['id'] as String,
        title: j['title'] as String,
        performer: j['performer'] as String? ?? '',
        fileUrl: j['fileUrl'] as String,
        coverUrl: j['coverUrl'] as String?,
        localPath: j['localPath'] as String?,
        license: j['license'] as String? ?? 'CC-BY',
        authorName: j['authorName'] as String?,
        authorId: j['authorId'] as String?,
        authorIsVerified: j['authorIsVerified'] == true,
        addedAt: j['addedAt'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'performer': performer,
        'fileUrl': fileUrl,
        'coverUrl': coverUrl,
        'localPath': localPath,
        'license': license,
        'authorName': authorName,
        'authorId': authorId,
        'authorIsVerified': authorIsVerified,
        'addedAt': addedAt,
      };
}

class MyLibraryService {
  static const _indexPath = 'my_library/index.json';
  static const _musicIndexPath = 'my_library/music_index.json';
  static const _libraryDir = 'my_library';

  static Future<List<LibraryItem>> loadAssets() async {
    try {
      final qs = await QuestStore.defaultInstance();
      if (!await qs.exists(_indexPath)) return [];
      final data = await qs.readJson(_indexPath);
      if (data == null) return [];
      final list = data['items'] as List? ?? [];
      return list.map((e) => LibraryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<List<MusicLibraryItem>> loadMusic() async {
    try {
      final qs = await QuestStore.defaultInstance();
      if (!await qs.exists(_musicIndexPath)) return [];
      final data = await qs.readJson(_musicIndexPath);
      if (data == null) return [];
      final list = data['items'] as List? ?? [];
      return list.map((e) => MusicLibraryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isInLibrary(String assetId) async {
    final items = await loadAssets();
    return items.any((e) => e.id == assetId);
  }

  static Future<bool> isMusicInLibrary(String trackId) async {
    final items = await loadMusic();
    return items.any((e) => e.id == trackId);
  }

  /// Причина, по которой файл не лег в библиотеку, — человеческим языком.
  /// `status` — код ответа, если сервер ответил; `error` — если запрос не прошёл.
  static String _whyNoFile({int? status, Object? error}) {
    if (error != null) {
      final raw = error.toString();
      if (raw.contains('SocketException') || raw.contains('ClientException')) {
        return tr('Нет соединения с сервером');
      }
      return tr('Файл не скачался');
    }
    if (status == 401 || status == 403) {
      return tr('Сервер не даёт файл: перечитайте страницу и войдите заново');
    }
    if (status == 404) return tr('Файла больше нет на сервере');
    return trf('Сервер не отдал файл (код {p0})', {'p0': status});
  }

  /// Библиотека — это файл на устройстве. Возвращает текст ошибки или null,
  /// если всё легло. Раньше при 403/404 и при сетевой ошибке записывались
  /// только метаданные: человек видел «Добавлено в библиотеку», плашка горела,
  /// а применить ассет было нечем.
  static Future<String?> addAsset(MarketAsset asset) async {
    final qs = await QuestStore.defaultInstance();
    final items = await loadAssets();
    if (items.any((e) => e.id == asset.id)) return null; // already

    // Пустая ссылка — сломанная публикация: запись без файла в полке только
    // обещает, поэтому не добавляем её и говорим, что не так.
    final url = asset.downloadUrl;
    if (url.isEmpty) return tr('Сервер не отдал ссылку на файл');

    // Download file to my_library/<kind>/<id>.<ext>
    String? localPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final req = http.Request('GET', Uri.parse(url));
      if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) {
        return _whyNoFile(status: resp.statusCode);
      }
      final bytes = await resp.stream.toBytes();
      final ext = p.extension(url.split('?').first);
      final rel = p.join(_libraryDir, asset.kind, '${asset.id}$ext');
      final full = await FileStorage.getFilePath(rel);
      await Directory(p.dirname(full)).create(recursive: true);
      await File(full).writeAsBytes(bytes);
      localPath = rel;
      // Also download cover if exists for preview
      if (asset.coverUrl != null) {
        try {
          final cReq = http.Request('GET', Uri.parse(asset.coverUrl!));
          if (token.isNotEmpty) {
            cReq.headers['Authorization'] = 'Bearer $token';
          }
          final cResp = await http.Client().send(cReq);
          if (cResp.statusCode == 200) {
            final cBytes = await cResp.stream.toBytes();
            final cExt = p.extension(asset.coverUrl!.split('?').first);
            final cRel = p.join(_libraryDir, asset.kind, '${asset.id}_cover$cExt');
            final cFull = await FileStorage.getFilePath(cRel);
            await File(cFull).writeAsBytes(cBytes);
          }
        } catch (_) {}
      }
    } catch (e) {
      return _whyNoFile(error: e);
    }

    // Для button_preset файл — ZIP, он уже сохранён выше.
    final item = LibraryItem.fromMarketAsset(asset, localPath: localPath);
    items.insert(0, item);
    await qs.writeJson(_indexPath, {'items': items.map((e) => e.toJson()).toList()});
    return null;
  }

  /// То же, что `addAsset`, для треков: в библиотеке лежит скачанный файл,
  /// плеер играет именно его, поэтому без файла трек добавлять не за чем.
  static Future<String?> addMusic(MusicTrack track) async {
    final qs = await QuestStore.defaultInstance();
    final items = await loadMusic();
    if (items.any((e) => e.id == track.id)) return null;
    String? localPath;
    final url = track.downloadUrl;
    if (url.isEmpty) return tr('Сервер не отдал ссылку на файл');
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final req = http.Request('GET', Uri.parse(url));
      if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) {
        return _whyNoFile(status: resp.statusCode);
      }
      final bytes = await resp.stream.toBytes();
      final ext = p.extension(url.split('?').first).isEmpty ? '.mp3' : p.extension(url.split('?').first);
      final rel = p.join(_libraryDir, 'music', '${track.id}$ext');
      final full = await FileStorage.getFilePath(rel);
      await Directory(p.dirname(full)).create(recursive: true);
      await File(full).writeAsBytes(bytes);
      localPath = rel;
    } catch (e) {
      return _whyNoFile(error: e);
    }
    final item = MusicLibraryItem.fromTrack(track, localPath: localPath);
    items.insert(0, item);
    await qs.writeJson(_musicIndexPath, {'items': items.map((e) => e.toJson()).toList()});
    return null;
  }

  static Future<void> removeAsset(String assetId) async {
    final qs = await QuestStore.defaultInstance();
    final items = await loadAssets();
    final idx = items.indexWhere((e) => e.id == assetId);
    if (idx == -1) return;
    final item = items[idx];
    // try delete file
    if (item.localPath != null) {
      try {
        final full = await FileStorage.getFilePath(item.localPath!);
        await File(full).delete();
        // also try cover
        final coverRel = p.join(_libraryDir, item.kind, '${item.id}_cover${p.extension(item.coverUrl ?? "")}');
        try {
          final cFull = await FileStorage.getFilePath(coverRel);
          await File(cFull).delete();
        } catch (_) {}
      } catch (_) {}
    }
    items.removeAt(idx);
    await qs.writeJson(_indexPath, {'items': items.map((e) => e.toJson()).toList()});
  }

  static Future<void> removeMusic(String trackId) async {
    final qs = await QuestStore.defaultInstance();
    final items = await loadMusic();
    final idx = items.indexWhere((e) => e.id == trackId);
    if (idx == -1) return;
    if (items[idx].localPath != null) {
      try {
        final full = await FileStorage.getFilePath(items[idx].localPath!);
        await File(full).delete();
      } catch (_) {}
    }
    items.removeAt(idx);
    await qs.writeJson(_musicIndexPath, {'items': items.map((e) => e.toJson()).toList()});
  }

  static Future<String?> copyAssetToQuest(LibraryItem item, String questId) async {
    // If localPath exists, copy file to quest res; otherwise download
    String sourcePath;
    if (item.localPath != null) {
      sourcePath = await FileStorage.getFilePath(item.localPath!);
      if (!await File(sourcePath).exists()) {
        // fallback download
        return _downloadAndCopyToQuest(item.toMarketAsset(), questId);
      }
    } else {
      return _downloadAndCopyToQuest(item.toMarketAsset(), questId);
    }

    final qs = await QuestStore.defaultInstance();
    final ext = p.extension(sourcePath).isEmpty ? p.extension(item.fileUrl.split('?').first) : p.extension(sourcePath);
    String destRel;
    final title = item.title;
    if (item.kind == 'background' || item.kind == 'image') {
      destRel = p.join('res/images', '${DateTime.now().millisecondsSinceEpoch}_${item.id}$ext');
      final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
      await Directory(p.dirname(dest)).create(recursive: true);
      await File(sourcePath).copy(dest);
      final meta = await qs.readJson(QuestPaths.metadata(questId)) ?? {};
      meta[p.basename(destRel)] = {'name': title, 'folder': '/', 'resourceId': item.id};
      await qs.writeJson(QuestPaths.metadata(questId), meta);
    } else if (item.kind == 'sfx') {
      destRel = p.join('res/audio', '${DateTime.now().millisecondsSinceEpoch}_${item.id}$ext');
      final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
      await Directory(p.dirname(dest)).create(recursive: true);
      await File(sourcePath).copy(dest);
      final meta = await qs.readJson(QuestPaths.metadata(questId)) ?? {};
      meta[p.basename(destRel)] = {'name': title, 'folder': '/', 'resourceId': item.id};
      await qs.writeJson(QuestPaths.metadata(questId), meta);
    } else if (item.kind == 'font') {
      destRel = p.join('res/fonts', '${title.replaceAll(' ', '_')}$ext');
      final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
      await Directory(p.dirname(dest)).create(recursive: true);
      await File(sourcePath).copy(dest);
    } else if (item.kind == 'button_preset') {
      // For presets, we need original ZIP handling - fallback to remote
      return _downloadAndCopyToQuest(item.toMarketAsset(), questId);
    } else {
      destRel = p.join('res', p.basename(sourcePath));
      final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
      await Directory(p.dirname(dest)).create(recursive: true);
      await File(sourcePath).copy(dest);
    }
    return destRel;
  }

  static Future<String?> _downloadAndCopyToQuest(MarketAsset asset, String questId) async {
    // Reuse logic from asset_details - download from remote and copy
    if (asset.kind == 'button_preset') {
      final imported = await PresetMarketService.importToQuest(asset: asset, questId: questId);
      return imported > 0 ? 'button_preset' : null;
    }
    // For other kinds, download and use same as above but from network
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final req = http.Request('GET', Uri.parse(asset.downloadUrl));
      if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      final resp = await http.Client().send(req);
      if (resp.statusCode != 200) return null;
      final bytes = await resp.stream.toBytes();
      final tmpDir = Directory.systemTemp.createTempSync('lib_copy_');
      final tmpFile = File(p.join(tmpDir.path, p.basename(asset.downloadUrl.split('?').first)));
      await tmpFile.writeAsBytes(bytes);
      final qs = await QuestStore.defaultInstance();
      String destRel;
      if (asset.kind == 'background' || asset.kind == 'image') {
        final ext = p.extension(asset.downloadUrl.split('?').first).isEmpty ? '.png' : p.extension(asset.downloadUrl.split('?').first);
        destRel = p.join('res/images', '${DateTime.now().millisecondsSinceEpoch}_${asset.id}$ext');
        final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
        await Directory(p.dirname(dest)).create(recursive: true);
        await tmpFile.copy(dest);
        final meta = await qs.readJson(QuestPaths.metadata(questId)) ?? {};
        meta[p.basename(destRel)] = {'name': asset.title, 'folder': '/', 'resourceId': asset.id};
        await qs.writeJson(QuestPaths.metadata(questId), meta);
      } else if (asset.kind == 'sfx') {
        final ext = p.extension(asset.downloadUrl.split('?').first).isEmpty ? '.mp3' : p.extension(asset.downloadUrl.split('?').first);
        destRel = p.join('res/audio', '${DateTime.now().millisecondsSinceEpoch}_${asset.id}$ext');
        final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
        await Directory(p.dirname(dest)).create(recursive: true);
        await tmpFile.copy(dest);
        final meta = await qs.readJson(QuestPaths.metadata(questId)) ?? {};
        meta[p.basename(destRel)] = {'name': asset.title, 'folder': '/', 'resourceId': asset.id};
        await qs.writeJson(QuestPaths.metadata(questId), meta);
      } else if (asset.kind == 'font') {
        final ext = p.extension(asset.downloadUrl.split('?').first).isEmpty ? '.ttf' : p.extension(asset.downloadUrl.split('?').first);
        destRel = p.join('res/fonts', '${asset.title.replaceAll(' ', '_')}$ext');
        final dest = await FileStorage.getFilePath(QuestPaths.questFile(questId, destRel));
        await Directory(p.dirname(dest)).create(recursive: true);
        await tmpFile.copy(dest);
      } else {
        return null;
      }
      try { tmpDir.deleteSync(recursive: true); } catch (_) {}
      return destRel;
    } catch (_) { return null; }
  }
}


