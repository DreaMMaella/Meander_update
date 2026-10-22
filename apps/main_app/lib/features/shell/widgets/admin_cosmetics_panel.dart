import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';

// ============================================================================
//  АДМИН: ВЫДАЧА ОФОРМЛЕНИЯ ПРОФИЛЯ
//
//  Сценарий один: конкурс закончился, надо выдать призёрам снег на профиль.
//  Поэтому здесь нет редактора предметов — каталог живёт в коде клиента, а
//  сервер хранит только права. Отсюда две следствия:
//   1. сетку мы рисуем по локальному каталогу (он же показывает превью),
//      серверу отправляем только id;
//   2. отзываемый предмет снимается с полки автоматически: витрина читает
//      `profiles/cosmetics/mine`, а не свой список.
// ============================================================================

class AdminCosmeticsPanel extends ConsumerStatefulWidget {
  const AdminCosmeticsPanel({super.key, this.nonce = 0});

  /// Меняется по кнопке «Обновить» в шапке админ-центра.
  final int nonce;

  @override
  ConsumerState<AdminCosmeticsPanel> createState() => _AdminCosmeticsPanelState();
}

class _AdminCosmeticsPanelState extends ConsumerState<AdminCosmeticsPanel> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController(text: '50');

  /// Найденные по запросу люди.
  List<Map<String, dynamic>> _hits = const [];
  bool _searching = false;

  /// Запрос, по которому поиск уже успел ответить пустотой. Без этой пометки
  /// опечатка в id выглядит как неработающая кнопка.
  String? _emptySearch;

  /// Выборка администратора: id пользователя -> отображаемое имя.
  final Map<String, String> _targets = {};

  /// id предметов из каталога, отмеченные для выдачи.
  final Set<String> _picked = {};

  CosmeticSlot _slot = CosmeticSlot.banner;

  /// Фильтр по сезонному выпуску; null — показывать весь слот.
  String? _season;
  bool _busy = false;
  String? _error;

  /// Выдачи и коды подгружаются списком; перечитаются после операций.
  List<Map<String, dynamic>> _grants = const [];
  List<Map<String, dynamic>> _codes = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(loadCodes);
  }

  @override
  void didUpdateWidget(AdminCosmeticsPanel old) {
    super.didUpdateWidget(old);
    if (old.nonce != widget.nonce) refreshAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    _daysCtrl.dispose();
    _codeCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<T?> _guard<T>(Future<T> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      return await body();
    } catch (e) {
      if (mounted) setState(() => _error = _readableError(e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _readableError(Object error) {
    final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return match?.group(1) ?? trf('Сервер не ответил: {p0}', {'p0': error});
  }

  // -- Загрузка ----------------------------------------------------------

  Future<void> searchUsers() async {
    final raw = _searchCtrl.text.trim();
    if (raw.length < 2) {
      setState(() {
        _hits = const [];
        _emptySearch = null;
      });
      return;
    }
    // Бэкенд сравнивает id как текст, а uuid в базе всегда в нижнем регистре:
    // скопированный с телефона ЗАГЛАВНЫМ id иначе «никто не найден».
    final q = raw.toLowerCase();
    // UUID можно вставить напрямую: поиск по нему всё равно идёт на бэке,
    // но без него админу пришлось бы копировать людей из других экранов.
    setState(() => _searching = true);
    final res = await _guard<List<Map<String, dynamic>>>(() async {
      final response = await _api.get(
        'admin/cosmetics/users',
        queryParams: {'q': q},
      );
      return (response as Map<String, dynamic>)['users']
          .cast<Map<String, dynamic>>();
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      _hits = res ?? const [];
      _emptySearch = res == null ? null : (res.isEmpty ? q : null);
    });
  }

  Future<void> loadGrants(String userId) async {
    final res = await _guard<List<Map<String, dynamic>>>(() async {
      final response = await _api.get(
        'admin/cosmetics/grants',
        queryParams: {'user_id': userId},
      );
      return (response as Map<String, dynamic>)['grants']
          .cast<Map<String, dynamic>>();
    });
    if (!mounted) return;
    setState(() => _grants = res ?? const []);
  }

  Future<void> loadCodes() async {
    final res = await _guard<List<Map<String, dynamic>>>(() async {
      final response = await _api.get('admin/cosmetics/codes');
      return (response as Map<String, dynamic>)['codes']
          .cast<Map<String, dynamic>>();
    });
    if (!mounted) return;
    setState(() => _codes = res ?? const []);
  }

  Future<void> refreshAll() async {
    await loadCodes();
    final first = _targets.keys.firstOrNull;
    if (first != null) await loadGrants(first);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ErrorNote(text: _error!),
          ),
        _Section(
          title: tr('Кому выдаём'),
          child: _buildTargets(),
        ),
        _Section(
          title: tr('Что выдаём'),
          child: _buildCatalog(),
        ),
        _Section(
          title: tr('Параметры выдачи'),
          child: _buildGrantForm(),
        ),
        _Section(
          title: tr('Промокод на выбранное'),
          child: _buildCodeForm(),
        ),
        _Section(
          title: trf('Выдачи {p0}', {'p0': _targets.keys.firstOrNull ?? ''}).trim(),
          child: _buildGrantsList(),
        ),
        _Section(title: tr('Коды с оформлением'), child: _buildCodesList()),
      ],
    );
  }

  // -- Секции ------------------------------------------------------------

  Widget _buildTargets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => searchUsers(),
                decoration: InputDecoration(
                  labelText: tr('Имя пользователя или id'),
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_search_rounded, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: tr('Найти'),
              icon: const Icon(Icons.search_rounded),
              onPressed: _busy ? null : searchUsers,
            ),
          ],
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        for (final hit in _hits)
          if (!_targets.containsKey(hit['id'] as String))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded, size: 20),
              title: Text(hit['full_name'] ?? tr('Без имени')),
              subtitle: Text('${hit['id']}', style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.add_circle_outline_rounded, size: 20),
              onTap: () => setState(() {
                _targets[hit['id'] as String] =
                    '${hit['full_name'] ?? tr('без имени')}';
                _grants = const [];
              }),
            ),
        if (_emptySearch != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              trf('По запросу «{_emptySearch}» никто не найден: id должен совпадать целиком, имя — от 2 символов.', {'_emptySearch': _emptySearch}),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in _targets.entries)
              InputChip(
                label: Text(entry.value),
                tooltip: entry.key,
                onDeleted: () => setState(() {
                  _targets.remove(entry.key);
                  _grants = const [];
                }),
              ),
          ],
        ),
        if (_targets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => loadGrants(_targets.keys.first),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(trf('Что уже выдано первому из {p0}', {'p0': _targets.length})),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCatalog() {
    // Отметка живёт поверх фильтров: новогодний набор собирается за один
    // заход — обложка на одной вкладке, снег на другой.
    final all = cosmeticsOfSlot(_slot);
    final items = _season == null
        ? all
        : all.where((def) => def.season == _season).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final slot in CosmeticSlot.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(slot.title),
                    selected: _slot == slot,
                    onSelected: (_) => setState(() => _slot = slot),
                  ),
                ),
            ],
          ),
        ),
        if (kCosmeticSeasons.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(tr('Выпуск:'), style: TextStyle(fontSize: 12)),
                ),
                for (final season in kCosmeticSeasons)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cosmeticSeasonLabel(season)),
                      // Повторный тап снимает фильтр: отдельная кнопка «Все»
                      // для этого только множила бы состояния.
                      selected: _season == season,
                      onSelected: (_) => setState(
                        () => _season = _season == season ? null : season,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        _buildBulkPick(items),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(tr('В этом слоте предметов выбранного выпуска нет.')),
          )
        else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 190).floor().clamp(2, 6);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final def = items[index];
                return _PickTile(
                  def: def,
                  selected: _picked.contains(def.id),
                  onTap: def.free
                      ? null
                      : () => setState(() {
                          if (!_picked.remove(def.id)) _picked.add(def.id);
                        }),
                );
              },
            );
          },
        ),
        if (_picked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () => setState(_picked.clear),
              icon: const Icon(Icons.deselect_rounded, size: 18),
              label: Text(trf('Снять отметки ({p0})', {'p0': _picked.length})),
            ),
          ),
      ],
    );
  }

  /// Отметить показанное разом: отмечать сорок галочек пальцем — то самое
  /// «вручную постоянно». Бесплатные предметы пропускаем: бэкенд их не
  /// записывает, и отмеченные они только врут в счётчике кнопки выдачи.
  Widget _buildBulkPick(List<CosmeticDef> items) {
    final grantable = items.where((def) => !def.free).toList();
    final missingHere = grantable.where((def) => !_picked.contains(def.id));
    final missingEverywhere = kCosmetics.where(
      (def) => !def.free && !_picked.contains(def.id),
    );
    if (grantable.isEmpty && missingEverywhere.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectHere = missingHere.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (grantable.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => setState(() {
              for (final def in grantable) {
                if (selectHere) {
                  _picked.add(def.id);
                } else {
                  _picked.remove(def.id);
                }
              }
            }),
            icon: Icon(
              selectHere ? Icons.select_all_rounded : Icons.deselect_rounded,
              size: 18,
            ),
            label: Text(
              selectHere
                  ? trf('Отметить показанные (+{p0})', {'p0': missingHere.length})
                  : trf('Снять показанные ({p0})', {'p0': grantable.length}),
            ),
          ),
        if (missingEverywhere.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => setState(
              () => _picked.addAll(missingEverywhere.map((def) => def.id)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(trf('Всё платное сразу (+{p0})', {'p0': missingEverywhere.length})),
          ),
      ],
    );
  }

  Widget _buildGrantForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _daysCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Дней (пусто = бессрочно)'),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _reasonCtrl,
                decoration: InputDecoration(
                  labelText: tr('За что (попадёт в историю выдач)'),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: (_busy || _targets.isEmpty || _picked.isEmpty)
              ? null
              : _grant,
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: Text(
            trf('Выдать {p0} предмет(ов) {p1} чел.', {'p0': _picked.length, 'p1': _targets.length}),
          ),
        ),
        if (_targets.length == 1 && _picked.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
            label: Text(tr('Отозвать выбранное у этого человека')),
          ),
        ],
      ],
    );
  }

  Widget _buildCodeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Код активируют сами победители в профиле — выдача по id не нужна. В код кладётся всё, что отмечено в каталоге выше.'),
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: tr('Код (пусто = сгенерировать)'),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Активаций'),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: (_busy || _picked.isEmpty) ? null : _createCode,
          icon: const Icon(Icons.qr_code_rounded, size: 18),
          label: Text(tr('Создать код')),
        ),
      ],
    );
  }

  Widget _buildGrantsList() {
    if (_grants.isEmpty) {
      return Text(
        tr('Откройте выдачу кнопкой выше или выберите человека — здесь появится срок, источник и причина каждой выдачи.'),
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final g in _grants)
          _GrantRow(
            name: cosmeticById('${g['cosmetic_id']}')?.name ?? '${g['cosmetic_id']}',
            source: '${g['source']}',
            reason: g['reason'] == null ? null : '${g['reason']}',
            expiresAt: g['expires_at'] == null ? null : '${g['expires_at']}',
            onRevoke: () => _revokeOne('${g['cosmetic_id']}'),
          ),
      ],
    );
  }

  Widget _buildCodesList() {
    if (_codes.isEmpty) {
      return Text(
        tr('Кодов с оформлением пока нет.'),
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final c in _codes)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_offer_outlined, size: 20),
            title: Text('${c['code']}'),
            subtitle: Text(
              trf('{p0}\nиспользовано {p1} из {p2}', {'p0': (c['cosmetic_ids'] as List).map((id) => cosmeticById('$id')?.name ?? id).join(', '), 'p1': c['current_uses'], 'p2': c['max_uses']}),
              style: const TextStyle(fontSize: 11.5),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: tr('Скопировать код'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${c['code']}'));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('Код скопирован'))),
                );
              },
            ),
          ),
      ],
    );
  }

  // -- Действия ----------------------------------------------------------

  int? get _days {
    final raw = _daysCtrl.text.trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    return value == null || value <= 0 ? null : value;
  }

  Future<void> _grant() async {
    final ids = _picked.toList();
    final res = await _guard(() async {
      return await _api.post('admin/cosmetics/grant', body: {
        'user_ids': _targets.keys.toList(),
        'cosmetic_ids': ids,
        if (_days != null) 'days': _days,
        if (_reasonCtrl.text.trim().isNotEmpty) 'reason': _reasonCtrl.text.trim(),
      });
    });
    if (!mounted || res == null) return;
    setState(() {
      _picked.clear();
      _grants = const [];
    });
    await loadGrants(_targets.keys.first);
    if (mounted) {
      // Бэк считает сам: бесплатные предметы он не записывает, поэтому
      // «выдано 42» после «всё платное сразу» должно быть правдой, а не
      // пересказом того, что отметил админ.
      final perUser = res['granted'] as Map?;
      final written = (perUser?.values.firstOrNull as List?)?.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            written == null || written == ids.length
                ? trf('Выдано: {p0} предмет(ов) на {p1} чел.', {'p0': ids.length, 'p1': _targets.length})
                : trf('Выдано: {written} из {p0}, остальное уже у него.', {'written': written, 'p0': ids.length}),
          ),
        ),
      );
    }
  }

  Future<void> _revoke() async {
    final userId = _targets.keys.first;
    final res = await _guard(() async {
      return await _api.post('admin/cosmetics/revoke', body: {
        'user_id': userId,
        'cosmetic_ids': _picked.toList(),
      });
    });
    if (!mounted || res == null) return;
    setState(() {
      _picked.clear();
      _grants = const [];
    });
    await loadGrants(userId);
  }

  Future<void> _revokeOne(String cosmeticId) async {
    final userId = _targets.keys.firstOrNull;
    if (userId == null) return;
    final res = await _guard(() async {
      return await _api.post('admin/cosmetics/revoke', body: {
        'user_id': userId,
        'cosmetic_ids': [cosmeticId],
      });
    });
    if (!mounted || res == null) return;
    await loadGrants(userId);
  }

  Future<void> _createCode() async {
    final res = await _guard(() async {
      return await _api.post('admin/cosmetics/codes', body: {
        'cosmetic_ids': _picked.toList(),
        if (_codeCtrl.text.trim().isNotEmpty) 'code': _codeCtrl.text.trim(),
        'max_uses': int.tryParse(_maxUsesCtrl.text.trim()) ?? 100,
        if (_days != null) 'days': _days,
      });
    });
    if (res is! Map) return;
    final code = '${res['code']}';
    await loadCodes();
    if (!mounted) return;
    setState(() => _picked.clear());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Код готов')),
        content: SelectableText(code),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
            },
            child: Text(tr('Скопировать')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Закрыть'))),
        ],
      ),
    );
  }
}

// ============================================================================
//  МЕЛКИЕ ВИДЖЕТЫ ВКЛАДКИ
// ============================================================================

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          // Material с цветом, а не Container: внутри лежат ListTile, и их
          // ink-эффекты должны рисоваться поверх этого фона, а не под ним.
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: scheme.surfaceContainerHigh,
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Плитка каталога с мультивыбором: превью — тот же рендерер, что и на
/// настоящем профиле, чтобы не выдавать кота в мешке.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.def,
    required this.selected,
    this.onTap,
  });

  final CosmeticDef def;
  final bool selected;

  /// null у бесплатных предметов: их некому выдавать, они и так надеты.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final free = def.free;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CosmeticPreview(def: def, height: 56),
                    if (!free)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              def.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              free ? tr('бесплатно · не выдаётся') : def.tier.title,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.name,
    required this.source,
    required this.reason,
    required this.expiresAt,
    required this.onRevoke,
  });

  final String name;
  final String source;
  final String? reason;
  final String? expiresAt;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final until = expiresAt == null
        ? tr('бессрочно')
        : trf('до {p0}', {'p0': DateTime.parse(expiresAt!).toLocal().toString().substring(0, 16)});
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.redeem_rounded, size: 20),
      title: Text(name),
      subtitle: Text(
        '$source · $until${reason == null ? '' : ' · $reason'}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: IconButton(
        tooltip: tr('Отозвать'),
        icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
        onPressed: onRevoke,
      ),
    );
  }
}
