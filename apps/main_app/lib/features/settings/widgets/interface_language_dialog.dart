import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/custom_language_store.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/l10n/l10n_provider.dart';
import 'package:canvas_app/core/l10n/language_pack.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';

/// Диалог «Язык интерфейса»: выбор, импорт своего перевода и удаление.
///
/// Импорт устроен как перевод темы, а не как установка плагина: файл остаётся
/// у пользователя, приложение хранит копию в `documents/languages/<код>.json`
/// и перечитывает её на старте. Неполный пакет — норма: строка без перевода
/// остаётся русской, поэтому перевод можно дописывать по одному экрану.
class InterfaceLanguageDialog extends ConsumerStatefulWidget {
  /// Конструктор может быть `const`, но вызывать его надо без `const`: widget
  /// переводит строки в `build`, а константный экземпляр Flutter имеет право
  /// не перестраивать — экран остался бы на старом языке.
  const InterfaceLanguageDialog({super.key});

  @override
  ConsumerState<InterfaceLanguageDialog> createState() =>
      _InterfaceLanguageDialogState();
}

class _InterfaceLanguageDialogState
    extends ConsumerState<InterfaceLanguageDialog> {
  bool _busy = false;

  /// Сообщение под списком: результат последнего импорта или удаления.
  String? _notice;

  Future<void> _select(AppLanguage language) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appLanguageProvider.notifier).select(language.code);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          trf('Язык интерфейса: {name}', {'name': language.nativeName}),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _import() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: tr('Выберите файл языка'),
    );
    if (files.isEmpty) return;
    final raw = await _readText(files.first);
    if (raw == null) {
      setState(() => _notice = tr('Файл языка не читается'));
      return;
    }
    if (raw.codeUnits.length > kLanguagePackMaxBytes) {
      setState(() => _notice = tr('Файл языка слишком большой'));
      return;
    }
    _setBusy(true);
    try {
      final pack = await customLanguageStore.importText(raw);
      if (!mounted) return;
      _setBusy(false);
      setState(
        () => _notice = pack.skipped.isEmpty
            ? trf('Язык импортирован: {name}', {
                'name': pack.language.nativeName,
              })
            : trf(
                'Язык импортирован: {name}. Пропущено записей: {skipped}',
                {
                  'name': pack.language.nativeName,
                  'skipped': pack.skipped.length,
                },
              ),
      );
    } on LanguagePackException catch (error) {
      if (!mounted) return;
      _setBusy(false);
      setState(() => _notice = languagePackMessage(error));
    } catch (error) {
      if (!mounted) return;
      _setBusy(false);
      setState(() => _notice = tr('Не удалось импортировать язык'));
    }
  }

  /// Содержимое выбранного файла. На дескоте file_picker отдаёт путь, на
  /// Android — байты, поэтому пробуем и то, и другое.
  Future<String?> _readText(PlatformFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return utf8.decode(bytes);
    } catch (_) {
      final path = file.path;
      if (path == null) return null;
      try {
        return await File(path).readAsString();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _exportTemplate() async {
    if (_busy) return;
    _setBusy(true);
    try {
      await FilePicker.saveFile(
        fileName: 'meander-language-template.json',
        bytes: customLanguageStore.templateBytes(),
        mimeType: 'application/json',
        dialogTitle: tr('Шаблон для перевода'),
      );
      if (!mounted) return;
      _setBusy(false);
      setState(
        () => _notice = tr('Шаблон со всеми строками сохранён в выбранный файл'),
      );
    } catch (_) {
      if (!mounted) return;
      _setBusy(false);
      setState(() => _notice = tr('Не удалось сохранить шаблон'));
    }
  }

  Future<void> _remove(AppLanguage language) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(trf('Удалить язык {name}?', {'name': language.nativeName})),
        content: Text(tr('Файл языка удалится из приложения.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Удалить')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _setBusy(true);
    final wasCurrent = L10n.code == language.code;
    await customLanguageStore.remove(language.code);
    if (!mounted) return;
    _setBusy(false);
    // Язык был выбран — провайдер обязан записать откат в настройки, иначе
    // после перезапуска код окажется неизвестным и экраны разойдутся с prefs.
    if (wasCurrent) {
      await ref.read(appLanguageProvider.notifier).select(kSourceLanguageCode);
    }
    setState(() => _notice = tr('Язык удалён'));
  }

  void _setBusy(bool value) {
    setState(() => _busy = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(appLanguageProvider);
    final builtin = [
      for (final language in L10n.supported)
        if (!language.custom) language,
    ];
    final custom = [
      for (final language in L10n.supported)
        if (language.custom) language,
    ];

    return AlertDialog(
      title: Text(tr('Язык интерфейса')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final language in builtin)
                _LanguageTile(
                  language: language,
                  isCurrent: language.code == current.code,
                  onTap: () => _select(language),
                ),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    tr('Импортированные языки'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final language in custom)
                  _LanguageTile(
                    language: language,
                    isCurrent: language.code == current.code,
                    onTap: () => _select(language),
                    onDelete: _busy ? null : () => _remove(language),
                  ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(
                  _notice!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                tr('Строка без перевода остаётся русской — перевод можно дополнять по частям.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy ? null : _import,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_rounded),
          label: Text(tr('Импортировать язык')),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _exportTemplate,
          icon: const Icon(Icons.download_rounded),
          label: Text(tr('Шаблон для перевода')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Закрыть')),
        ),
      ],
    );
  }
}

/// Текст причины отказа для человека.
///
/// Ядро перевода (`lib/core/l10n/`) гард-сканер переводов не проверяет, поэтому
/// сообщение рождается здесь: словарь обязан покрыть каждую причину, иначе
/// тест на отсутствие кириллицы в английском режиме её поймает.
String languagePackMessage(LanguagePackException error) {
  final detail = error.detail;
  return switch (error.issue) {
    LanguagePackIssue.tooLarge => tr('Файл языка слишком большой'),
    LanguagePackIssue.notJson => tr('Файл языка не читается как JSON'),
    LanguagePackIssue.notObject => tr(
      'Файл языка должен быть объектом JSON с полями code и strings',
    ),
    LanguagePackIssue.unknownVersion => trf(
      'Неизвестная версия формата языка: {version}',
      {'version': detail},
    ),
    LanguagePackIssue.missingCode => tr('В файле не указан код языка'),
    LanguagePackIssue.badCode => tr(
      'Код языка должен быть строчными буквами, например de или pt-BR',
    ),
    LanguagePackIssue.duplicateCode => trf(
      'Язык с кодом {code} уже есть в списке',
      {'code': detail},
    ),
    LanguagePackIssue.missingName => tr('В файле не указано название языка'),
    LanguagePackIssue.unknownPluralRule => trf(
      'Неизвестное правило множественного числа: {rule}',
      {'rule': detail},
    ),
    LanguagePackIssue.nothingTranslated => tr(
      'В файле нет ни одной переведённой строки',
    ),
    LanguagePackIssue.tooManyStrings => tr('Слишком много строк в файле языка'),
  };
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.isCurrent,
    required this.onTap,
    this.onDelete,
  });

  final AppLanguage language;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(language.nativeName),
      subtitle: isCurrent
          ? Text(tr('Текущий язык'))
          : Text(language.code, style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: onDelete != null
          ? IconButton(
              tooltip: tr('Удалить язык'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
            )
          : isCurrent
          ? Icon(Icons.check_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
