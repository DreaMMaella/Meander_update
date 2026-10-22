import 'dart:typed_data';

import 'package:canvas_app/core/services/template_bundler.dart';
import 'package:canvas_app/models/template_model.dart';

/// Результат «установки» шаблона в квест: payload, в котором при необходимости
/// уже обновлены пути к ассетам, плюс отчёт о копировании файлов.
class TemplateInstallResult {
  /// Шаблон с обновлённым payload (пути перенаправлены, если были коллизии).
  final TemplateItem template;
  final TemplateBundleApplyReport assetsReport;

  const TemplateInstallResult({
    required this.template,
    required this.assetsReport,
  });
}

/// Сервис «установки» шаблона в квест: распаковывает связанные ассеты
/// в `quests/<questId>/...` и обновляет ссылки в payload, если что-то
/// пришлось переименовать из-за коллизий.
class TemplateAssetInstaller {
  /// Применить ассеты шаблона к квесту.
  ///
  /// Возвращает новый [TemplateItem] с (возможно) обновлённым payload и
  /// отчётом о копировании.
  ///
  /// Использовать перед вставкой шаблона в квест, например:
  /// ```dart
  /// final installed = await TemplateAssetInstaller.installToQuest(
  ///   template: tpl,
  ///   questId: questId,
  ///   bytesBySha: imported.bytesBySha,
  /// );
  /// final newItem = TemplateApplier.buildContentItem(installed.template);
  /// ```
  static Future<TemplateInstallResult> installToQuest({
    required TemplateItem template,
    required String questId,
    Map<String, Uint8List>? bytesBySha,
  }) async {
    if (template.assets.isEmpty) {
      // Нечего распаковывать.
      return TemplateInstallResult(
        template: template,
        assetsReport: const TemplateBundleApplyReport(
          copied: 0,
          skippedExisting: 0,
          failed: [],
          remappedPaths: {},
        ),
      );
    }

    final report = await TemplateBundler.applyAssetsToQuest(
      questId: questId,
      assets: template.assets,
      bytesBySha: bytesBySha,
    );

    if (report.remappedPaths.isEmpty) {
      return TemplateInstallResult(template: template, assetsReport: report);
    }

    // Обновляем пути в payload, если был ремап.
    final newPayload = TemplateBundler.remapPayloadPaths(
      template.payload,
      report.remappedPaths,
    );

    // Также обновляем relativePath в assets (для информативности, не критично).
    final newAssets = template.assets.map((a) {
      final newRel = report.remappedPaths[a.relativePath];
      if (newRel == null) return a;
      return a.copyWith(relativePath: newRel);
    }).toList();

    return TemplateInstallResult(
      template: template.copyWith(payload: newPayload, assets: newAssets),
      assetsReport: report,
    );
  }
}
