import 'dart:async';
import 'dart:io';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/offline_apk_builder.dart';
import 'package:canvas_app/core/utils/error_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Открывает экран параметров сборки APK. Возвращает `null`, если
/// пользователь закрыл экран без сборки.
Future<ApkBuildOptions?> showApkBuildOptionsScreen(
  BuildContext context,
  ApkBuildOptions initial,
) {
  return Navigator.of(context).push<ApkBuildOptions>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ApkBuildOptionsScreen(initial: initial),
    ),
  );
}

class ApkBuildOptionsScreen extends StatefulWidget {
  final ApkBuildOptions initial;

  const ApkBuildOptionsScreen({super.key, required this.initial});

  @override
  State<ApkBuildOptionsScreen> createState() => _ApkBuildOptionsScreenState();
}

class _ApkBuildOptionsScreenState extends State<ApkBuildOptionsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fileName;
  late final TextEditingController _appName;
  late final TextEditingController _packageName;
  late final TextEditingController _versionName;
  late final TextEditingController _versionCode;
  late final TextEditingController _certCommonName;
  late final TextEditingController _certOrganization;
  late final TextEditingController _certCountry;
  late final TextEditingController _certValidity;
  late final TextEditingController _storePassword;
  late final TextEditingController _keyAlias;
  late final TextEditingController _keyPassword;

  late ApkSigningMode _signingMode;
  late bool _protectContent;
  late bool _v1;
  late bool _v2;
  late bool _v3;
  String? _keystorePath;
  bool _pickingKeystore = false;
  bool _obscurePasswords = true;

  String? _iconPath;
  bool _pickingIcon = false;
  bool _submitted = false;

  /// Иконки, скопированные за время экрана: ненужные удаляем при выходе.
  final List<String> _importedIcons = [];

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    _fileName = TextEditingController(text: o.fileName);
    _appName = TextEditingController(text: o.appName);
    _packageName = TextEditingController(text: o.packageName);
    _versionName = TextEditingController(text: o.versionName);
    _versionCode = TextEditingController(text: '${o.versionCode}');
    _certCommonName = TextEditingController(text: o.certCommonName);
    _certOrganization = TextEditingController(text: o.certOrganization);
    _certCountry = TextEditingController(text: o.certCountry);
    _certValidity = TextEditingController(text: '${o.certValidityYears}');
    _storePassword = TextEditingController(text: o.storePassword);
    _keyAlias = TextEditingController(text: o.keyAlias);
    _keyPassword = TextEditingController(text: o.keyPassword);
    _signingMode = o.signingMode;
    _protectContent = o.protectContent;
    _v1 = o.v1;
    _v2 = o.v2;
    _v3 = o.v3;
    _keystorePath = o.keystorePath;
    _iconPath = o.iconPath;
  }

  @override
  void dispose() {
    for (final c in [
      _fileName,
      _appName,
      _packageName,
      _versionName,
      _versionCode,
      _certCommonName,
      _certOrganization,
      _certCountry,
      _certValidity,
      _storePassword,
      _keyAlias,
      _keyPassword,
    ]) {
      c.dispose();
    }
    final keep = _submitted ? _iconPath : null;
    for (final path in _importedIcons) {
      if (path != keep) unawaited(OfflineApkBuilder.deleteIcon(path));
    }
    super.dispose();
  }

  Future<void> _pickIcon() async {
    if (_pickingIcon) return;
    setState(() => _pickingIcon = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      final path = files.isEmpty ? null : files.single.path;
      if (path == null) return;
      final stored = await OfflineApkBuilder.importIcon(path);
      _importedIcons.add(stored);
      if (mounted) setState(() => _iconPath = stored);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trf('Ошибка: {p0}', {'p0': friendlyError(e)})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
  }

  Future<void> _pickKeystore() async {
    if (_pickingKeystore) return;
    setState(() => _pickingKeystore = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      final path = files.isEmpty ? null : files.single.path;
      if (path == null) return;
      final stored = await OfflineApkBuilder.importKeystore(path);
      if (mounted) setState(() => _keystorePath = stored);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trf('Ошибка: {p0}', {'p0': friendlyError(e)})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingKeystore = false);
    }
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_signingMode == ApkSigningMode.keystore && _keystorePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Выберите файл keystore')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_v1 && !_v2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Включите подпись v1 или v2 — без них APK не установится на Android 7–8'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _submitted = true;
    Navigator.of(context).pop(
      widget.initial.copyWith(
        fileName: _fileName.text.trim(),
        appName: _appName.text.trim(),
        packageName: _packageName.text.trim(),
        versionName: _versionName.text.trim(),
        versionCode: int.parse(_versionCode.text.trim()),
        protectContent: _protectContent,
        signingMode: _signingMode,
        certCommonName: _certCommonName.text.trim(),
        certOrganization: _certOrganization.text.trim(),
        certCountry: _certCountry.text.trim().toUpperCase(),
        certValidityYears: int.tryParse(_certValidity.text.trim()) ?? 30,
        keystorePath: _keystorePath,
        clearKeystore: _keystorePath == null,
        storePassword: _storePassword.text,
        keyAlias: _keyAlias.text.trim(),
        keyPassword: _keyPassword.text,
        v1: _v1,
        v2: _v2,
        v3: _v3,
        iconPath: _iconPath,
        clearIcon: _iconPath == null,
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? tr('Обязательное поле') : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(tr('Сборка APK')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.android_rounded, size: 18),
              label: Text(tr('Собрать')),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _FormSection(
                  icon: Icons.insert_drive_file_outlined,
                  title: tr('Файл'),
                  children: [
                    TextFormField(
                      controller: _fileName,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr('Имя APK-файла'),
                        suffixText: '.apk',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                _FormSection(
                  icon: Icons.apps_rounded,
                  title: tr('Приложение'),
                  children: [
                    _IconPickerTile(
                      path: _iconPath,
                      busy: _pickingIcon,
                      onPick: _pickIcon,
                      onReset: () => setState(() => _iconPath = null),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _appName,
                      textInputAction: TextInputAction.next,
                      maxLength: 50,
                      decoration: InputDecoration(
                        labelText: tr('Название на устройстве'),
                        helperText: tr('Подпись под иконкой в лаунчере'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _packageName,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: InputDecoration(
                        labelText: tr('ID пакета'),
                        hintText: 'com.example.myquest',
                        helperText: tr('Тот же ID — обновление установленного APK, другой — отдельное приложение'),
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return tr('Обязательное поле');
                        if (!ApkBuildOptions.isValidPackageName(value)) {
                          return tr('Латиница, цифры и _, минимум две части через точку');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _versionName,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: tr('Версия'),
                              hintText: '1.0.0',
                              border: const OutlineInputBorder(),
                            ),
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _versionCode,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: tr('Код версии'),
                              helperText: tr('Увеличивайте при обновлении'),
                              helperMaxLines: 2,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null || n < 1 || n > 2100000000) {
                                return tr('От 1 до 2100000000');
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _protectContent,
                      onChanged: (v) => setState(() => _protectContent = v),
                      title: Text(tr('Защитить контент квеста')),
                      subtitle: Text(tr('Квест внутри APK будет зашифрован')),
                    ),
                  ],
                ),
                _FormSection(
                  icon: Icons.verified_user_outlined,
                  title: tr('Подпись'),
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ApkSigningMode>(
                        segments: [
                          ButtonSegment(
                            value: ApkSigningMode.device,
                            icon: const Icon(Icons.phone_android_rounded),
                            label: Text(tr('Ключ устройства')),
                          ),
                          ButtonSegment(
                            value: ApkSigningMode.keystore,
                            icon: const Icon(Icons.key_rounded),
                            label: Text(tr('Свой keystore')),
                          ),
                        ],
                        selected: {_signingMode},
                        onSelectionChanged: (s) =>
                            setState(() => _signingMode = s.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _signingMode == ApkSigningMode.device
                          ? _buildDeviceKeyFields()
                          : _buildKeystoreFields(scheme),
                    ),
                  ],
                ),
                _FormSection(
                  icon: Icons.shield_outlined,
                  title: tr('Схемы подписи'),
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _v1,
                      onChanged: (v) => setState(() => _v1 = v ?? false),
                      title: Text(tr('v1 (JAR)')),
                      subtitle: Text(tr('Совместимость со старыми установщиками')),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _v2,
                      onChanged: (v) => setState(() => _v2 = v ?? false),
                      title: Text(tr('v2 (APK Signature Scheme)')),
                      subtitle: Text(tr('Android 7.0+, рекомендуется')),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _v3,
                      onChanged: (v) => setState(() => _v3 = v ?? false),
                      title: Text(tr('v3 (ротация ключа)')),
                      subtitle: Text(tr('Android 9+, дополнительно к v2')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceKeyFields() {
    return Column(
      key: const ValueKey('device'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Ключ создаётся и хранится в защищённом хранилище этого устройства. Одинаковые данные сертификата — один и тот же ключ.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _certCommonName,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: tr('Владелец сертификата (CN)'),
            hintText: 'Meander Offline Quest',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _certOrganization,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: tr('Организация (O)'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _certCountry,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                maxLength: 2,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                ],
                decoration: InputDecoration(
                  labelText: tr('Страна (C)'),
                  hintText: 'RU',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isNotEmpty && value.length != 2) {
                    return tr('Две буквы');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _certValidity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: tr('Срок, лет'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1 || n > 100) return tr('От 1 до 100');
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeystoreFields(ColorScheme scheme) {
    final path = _keystorePath;
    return Column(
      key: const ValueKey('keystore'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: _pickingKeystore
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(Icons.key_rounded, color: scheme.primary),
            title: Text(
              path == null ? tr('Выбрать файл keystore') : p.basename(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(tr('.jks, .p12, .pfx, .bks')),
            trailing: path == null
                ? const Icon(Icons.chevron_right_rounded)
                : IconButton(
                    tooltip: tr('Убрать'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _keystorePath = null),
                  ),
            onTap: _pickKeystore,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _storePassword,
          obscureText: _obscurePasswords,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr('Пароль хранилища'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscurePasswords ? tr('Показать') : tr('Скрыть'),
              icon: Icon(
                _obscurePasswords
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () =>
                  setState(() => _obscurePasswords = !_obscurePasswords),
            ),
          ),
          validator: (v) => _signingMode == ApkSigningMode.keystore &&
                  (v == null || v.isEmpty)
              ? tr('Обязательное поле')
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _keyAlias,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: tr('Алиас ключа'),
            helperText: tr('Пусто — первый ключ в хранилище'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _keyPassword,
          obscureText: _obscurePasswords,
          autocorrect: false,
          enableSuggestions: false,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: tr('Пароль ключа'),
            helperText: tr('Пусто — как у хранилища'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Пароли не сохраняются — их нужно вводить при каждой сборке.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPickerTile extends StatelessWidget {
  final String? path;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onReset;

  const _IconPickerTile({
    required this.path,
    required this.busy,
    required this.onPick,
    required this.onReset,
  });

  static const double _previewSize = 72;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconPath = path;
    final cacheSize =
        (_previewSize * MediaQuery.devicePixelRatioOf(context)).round();

    final Widget preview;
    if (busy) {
      preview = const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else if (iconPath != null) {
      preview = Image.file(
        File(iconPath),
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.broken_image_outlined, color: scheme.error),
      );
    } else {
      preview = Icon(
        Icons.add_photo_alternate_outlined,
        size: 30,
        color: scheme.onSurfaceVariant,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: tr('Выбрать иконку'),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : onPick,
              child: SizedBox.square(
                dimension: _previewSize,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(busy ? 'busy' : iconPath ?? 'none'),
                    child: SizedBox.expand(child: preview),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Иконка приложения'),
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                iconPath == null
                    ? tr('Стандартная иконка плеера. PNG, JPG или WebP — края обрежутся до квадрата')
                    : tr('Своя иконка — будет подогнана под все размеры экрана'),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onPick,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      iconPath == null ? tr('Выбрать') : tr('Заменить'),
                    ),
                  ),
                  if (iconPath != null)
                    TextButton.icon(
                      onPressed: busy ? null : onReset,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(tr('Сбросить')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
