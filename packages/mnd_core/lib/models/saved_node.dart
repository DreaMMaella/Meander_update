import 'package:uuid/uuid.dart';

double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? defaultValue;
  return defaultValue;
}

bool _parseBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return defaultValue;
}

String _parseString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  return value.toString();
}

class SavedNode {
  final String id;
  final String chapterId;
  final String title;
  final Map<String, dynamic> content;
  final double x;
  final double y;
  final int? color; // Цвет ноды в формате ARGB
  final String? backgroundAssetId;
  final String? backgroundVideoAssetId;
  final double? backgroundVideoVolume;
  final bool? backgroundVideoLoop;
  final bool? backgroundVideoMuted;
  final String? backgroundVideoFit;
  final double? backgroundBlur; // null = как в скрипте (дефолт 10), 0 = без размытия
  final String? scriptAssetId;
  final double? timerDuration;
  final String? defaultActionNodeId;
  final bool? timerHidden;
  final String? backgroundAudioId;
  final double? backgroundAudioVolume;

  /// Точечные runtime-ограничения для текущей ноды.
  final bool allowSave;
  final bool allowInventoryAccess;

  /// Внутренний отступ между корневыми элементами ноды в игровом списке.
  /// `null` — старое поведение (24 px между детьми). `0` — без зазоров.
  final double? itemSpacing;

  /// Стиль перехода **в эту ноду**: переопределяет глобальный
  /// `quest.nodeTransitionMode`. Значения как у квеста: `none`, `fade`,
  /// `page`, `dark` (затемнение). `null` — как в квесте.
  final String? transitionMode;

  /// Глобальное переопределение скругления углов картинок для всей ноды.
  /// `null` — по умолчанию скругление включено. `false` — выключено для всех картинок.
  final bool? imageRoundedCorners;

  // ====== Linked template fields (Templates v2) ======
  /// Если задан — нода связана с мастер-шаблоном `templateRef`.
  /// Различение режимов через [isTemplateMaster]:
  ///
  /// * `templateRef != null && !isTemplateMaster` → **linked-инстанс**:
  ///   контент разворачивается из мастера резолвером.
  /// * `templateRef != null && isTemplateMaster` → **мастер-нода**:
  ///   полноценная редактируемая нода, при сохранении её payload
  ///   синхронизируется с `TemplateRepository`.
  /// * `templateRef == null` — обычная (snapshot) нода.
  final String? templateRef;

  /// Последняя известная инстансу версия мастера (для UI / индикации).
  final int? templateVersion;

  /// true — эта нода сама является «мастером» шаблона [templateRef].
  /// Изменения её payload синхронизируются в репозиторий шаблонов
  /// при следующем сохранении.
  final bool isTemplateMaster;

  SavedNode({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.content,
    this.x = 0.0,
    this.y = 0.0,
    this.color,
    this.backgroundAssetId,
    this.backgroundVideoAssetId,
    this.backgroundVideoVolume,
    this.backgroundVideoLoop,
    this.backgroundVideoMuted,
    this.backgroundVideoFit,
    this.backgroundBlur,
    this.scriptAssetId,
    this.timerDuration,
    this.defaultActionNodeId,
    this.timerHidden,
    this.backgroundAudioId,
    this.backgroundAudioVolume,
    this.allowSave = true,
    this.allowInventoryAccess = true,
    this.itemSpacing,
    this.imageRoundedCorners,
    this.transitionMode,
    this.templateRef,
    this.templateVersion,
    this.isTemplateMaster = false,
  });

  /// Связана ли нода с мастер-шаблоном (любой режим).
  bool get hasTemplateLink => templateRef != null && templateRef!.isNotEmpty;

  /// Является ли нода **linked-инстансом** (read-only от мастера).
  bool get isTemplateInstance => hasTemplateLink && !isTemplateMaster;

  /// Является ли нода **мастером** шаблона (источник правды для linked).
  bool get isTemplateMasterNode => hasTemplateLink && isTemplateMaster;

  SavedNode copyWith({
    String? id,
    String? chapterId,
    String? title,
    Map<String, dynamic>? content,
    double? x,
    double? y,
    int? color,
    String? backgroundAssetId,
    String? backgroundVideoAssetId,
    double? backgroundVideoVolume,
    bool? backgroundVideoLoop,
    bool? backgroundVideoMuted,
    String? backgroundVideoFit,
    bool clearBackgroundVideo = false,
    double? backgroundBlur,
    bool clearBackgroundBlur = false,
    String? scriptAssetId,
    double? timerDuration,
    String? defaultActionNodeId,
    bool? timerHidden,
    bool clearTimerHidden = false,
    String? backgroundAudioId,
    double? backgroundAudioVolume,
    String? templateRef,
    int? templateVersion,
    bool? isTemplateMaster,
    bool? allowSave,
    bool? allowInventoryAccess,
    double? itemSpacing,
    bool clearItemSpacing = false,
    bool? imageRoundedCorners,
    bool clearImageRoundedCorners = false,
    String? transitionMode,
    bool clearTransitionMode = false,
    bool clearTemplateLink = false,
    bool clearDefaultActionNodeId = false,
  }) {
    return SavedNode(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      title: title ?? this.title,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
      color: color ?? this.color,
      backgroundAssetId: backgroundAssetId ?? this.backgroundAssetId,
      backgroundVideoAssetId: clearBackgroundVideo
          ? null
          : (backgroundVideoAssetId ?? this.backgroundVideoAssetId),
      backgroundVideoVolume:
          clearBackgroundVideo ? null : (backgroundVideoVolume ?? this.backgroundVideoVolume),
      backgroundVideoLoop:
          clearBackgroundVideo ? null : (backgroundVideoLoop ?? this.backgroundVideoLoop),
      backgroundVideoMuted:
          clearBackgroundVideo ? null : (backgroundVideoMuted ?? this.backgroundVideoMuted),
      backgroundVideoFit:
          clearBackgroundVideo ? null : (backgroundVideoFit ?? this.backgroundVideoFit),
      backgroundBlur: clearBackgroundBlur ? null : (backgroundBlur ?? this.backgroundBlur),
      scriptAssetId: scriptAssetId ?? this.scriptAssetId,
      timerDuration: timerDuration ?? this.timerDuration,
      defaultActionNodeId: clearDefaultActionNodeId
          ? null
          : (defaultActionNodeId ?? this.defaultActionNodeId),
      timerHidden: clearTimerHidden ? null : (timerHidden ?? this.timerHidden),
      backgroundAudioId: backgroundAudioId ?? this.backgroundAudioId,
      backgroundAudioVolume:
          backgroundAudioVolume ?? this.backgroundAudioVolume,
      allowSave: allowSave ?? this.allowSave,
      allowInventoryAccess: allowInventoryAccess ?? this.allowInventoryAccess,
      itemSpacing: clearItemSpacing ? null : (itemSpacing ?? this.itemSpacing),
      imageRoundedCorners: clearImageRoundedCorners
          ? null
          : (imageRoundedCorners ?? this.imageRoundedCorners),
      transitionMode: clearTransitionMode
          ? null
          : (transitionMode ?? this.transitionMode),
      templateRef: clearTemplateLink ? null : (templateRef ?? this.templateRef),
      templateVersion: clearTemplateLink
          ? null
          : (templateVersion ?? this.templateVersion),
      isTemplateMaster: clearTemplateLink
          ? false
          : (isTemplateMaster ?? this.isTemplateMaster),
    );
  }

  factory SavedNode.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? 'error_id_${const Uuid().v4()}';
    final title = json['title']?.toString() ?? 'Нода без имени';

    final rawContent = json['content'];
    final Map<String, dynamic> contentData = rawContent is Map<String, dynamic>
        ? rawContent
        : {'items': []};

    return SavedNode(
      id: id,
      title: title,
      content: contentData,
      chapterId: _parseString(json['chapterId']),
      x: _parseDouble(json['x']),
      y: _parseDouble(json['y']),
      color: json['color'] as int?,
      backgroundAssetId: json['backgroundAssetId']?.toString(),
      backgroundVideoAssetId: json['backgroundVideoAssetId']?.toString(),
      backgroundVideoVolume: json['backgroundVideoVolume'] != null
          ? _parseDouble(json['backgroundVideoVolume'])
          : null,
      backgroundVideoLoop: json['backgroundVideoLoop'] as bool?,
      backgroundVideoMuted: json['backgroundVideoMuted'] as bool?,
      backgroundVideoFit: json['backgroundVideoFit']?.toString(),
      backgroundBlur: json['backgroundBlur'] != null ? _parseDouble(json['backgroundBlur']) : null,
      scriptAssetId: json['scriptAssetId']?.toString(),
      timerDuration: json['timerDuration'] != null
          ? _parseDouble(json['timerDuration'])
          : null,
      defaultActionNodeId: json['defaultActionNodeId']?.toString(),
      timerHidden: json['timerHidden'] as bool?,
      backgroundAudioId: json['backgroundAudioId']?.toString(),
      backgroundAudioVolume: json['backgroundAudioVolume'] != null
          ? _parseDouble(json['backgroundAudioVolume'])
          : null,
      allowSave: _parseBool(json['allowSave'], defaultValue: true),
      allowInventoryAccess: _parseBool(
        json['allowInventoryAccess'],
        defaultValue: true,
      ),
      itemSpacing: json['itemSpacing'] != null
          ? _parseDouble(json['itemSpacing'])
          : null,
      imageRoundedCorners: json['imageRoundedCorners'] as bool?,
      transitionMode: json['transitionMode']?.toString(),
      templateRef: json['templateRef']?.toString(),
      templateVersion: (json['templateVersion'] as num?)?.toInt(),
      isTemplateMaster: json['isTemplateMaster'] as bool? ?? false,
    );
  }

  /// Все ключи, которыми владеет модель. [toJson] выдаёт часть из них
  /// (зависит от значений), поэтому сохранение ноды обязано почистить по
  /// этому списку: оставшееся в файле старое значение воскресает после
  /// того, как настройку сняли (снят блюр → блюр снова на ноде).
  static const modelKeys = <String>{
    'id',
    'chapterId',
    'title',
    'content',
    'x',
    'y',
    'color',
    'backgroundAssetId',
    'backgroundVideoAssetId',
    'backgroundVideoVolume',
    'backgroundVideoLoop',
    'backgroundVideoMuted',
    'backgroundVideoFit',
    'backgroundBlur',
    'scriptAssetId',
    'timerDuration',
    'defaultActionNodeId',
    'timerHidden',
    'backgroundAudioId',
    'backgroundAudioVolume',
    'allowSave',
    'allowInventoryAccess',
    'itemSpacing',
    'imageRoundedCorners',
    'transitionMode',
    'templateRef',
    'templateVersion',
    'isTemplateMaster',
  };

  /// Ключи HUD-панели, которые модель больше не ведёт: панель целиком
  /// заменяется стеком. Держим список, чтобы `_mergeNodeJson` в редакторе
  /// вычистил их из файла ноды при первом же сохранении — иначе записанное
  /// когда-то `toolbarMode` жило бы в квесте вечно, а прочитать его уже
  /// некому.
  static const legacyKeys = <String>{
    'toolbarMode',
    'toolbarPosition',
    'toolbarStyle',
    'allowToolbarInteractions',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterId': chapterId,
    'title': title,
    'content': content,
    'x': x,
    'y': y,
    if (color != null) 'color': color,
    if (backgroundAssetId != null) 'backgroundAssetId': backgroundAssetId,
    if (backgroundVideoAssetId != null)
      'backgroundVideoAssetId': backgroundVideoAssetId,
    if (backgroundVideoVolume != null)
      'backgroundVideoVolume': backgroundVideoVolume,
    if (backgroundVideoLoop != null) 'backgroundVideoLoop': backgroundVideoLoop,
    if (backgroundVideoMuted != null) 'backgroundVideoMuted': backgroundVideoMuted,
    if (backgroundVideoFit != null) 'backgroundVideoFit': backgroundVideoFit,
    if (backgroundBlur != null) 'backgroundBlur': backgroundBlur,
    if (scriptAssetId != null) 'scriptAssetId': scriptAssetId,
    if (timerDuration != null) 'timerDuration': timerDuration,
    if (defaultActionNodeId != null) 'defaultActionNodeId': defaultActionNodeId,
    if (timerHidden != null) 'timerHidden': timerHidden,
    if (backgroundAudioId != null) 'backgroundAudioId': backgroundAudioId,
    if (backgroundAudioVolume != null)
      'backgroundAudioVolume': backgroundAudioVolume,
    if (!allowSave) 'allowSave': false,
    if (!allowInventoryAccess) 'allowInventoryAccess': false,
    if (itemSpacing != null) 'itemSpacing': itemSpacing,
    if (imageRoundedCorners != null) 'imageRoundedCorners': imageRoundedCorners,
    if (transitionMode != null) 'transitionMode': transitionMode,
    if (templateRef != null) 'templateRef': templateRef,
    if (templateVersion != null) 'templateVersion': templateVersion,
    if (isTemplateMaster) 'isTemplateMaster': true,
  };
}

class CameraState {
  final double offsetX;
  final double offsetY;
  final double scale;

  CameraState({this.offsetX = 0.0, this.offsetY = 0.0, this.scale = 1.0});

  factory CameraState.fromJson(Map<String, dynamic> json) => CameraState(
    offsetX: _parseDouble(json['offsetX']),
    offsetY: _parseDouble(json['offsetY']),
    scale: _parseDouble(json['scale'], defaultValue: 1.0),
  );

  Map<String, dynamic> toJson() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'scale': scale,
  };
}
