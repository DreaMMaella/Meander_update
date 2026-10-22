import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/resources/screens/lua_docs_screen.dart';

// ============================================================================
//  ОБЩИЙ КАРКАС РЕДАКТОРА LUA — Material 3 (единый для файлового и inline)
// ============================================================================

class LuaEditorScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final VoidCallback? onCancel;
  final bool isBusy;
  final Widget? trailingButton;
  final VoidCallback? onHelp;
  final List<Widget> extraActions;

  const LuaEditorScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    this.onCancel,
    this.isBusy = false,
    this.trailingButton,
    this.onHelp,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: tr('Назад'),
          onPressed: isBusy ? null : () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.data_object_rounded,
                    size: 14,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LUA',
                    style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          ...extraActions,
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: tr('Документация по Lua'),
            onPressed: onHelp ??
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LuaDocsScreen(),
                    ),
                  );
                },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: content,
              ),
            ),
            _ActionBar(
              scheme: scheme,
              isBusy: isBusy,
              onCancel: onCancel,
              trailing: trailingButton,
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижняя панель действий: Отмена (слева) + параметризованная кнопка (справа).
class _ActionBar extends StatelessWidget {
  final ColorScheme scheme;
  final bool isBusy;
  final VoidCallback? onCancel;
  final Widget? trailing;

  const _ActionBar({
    required this.scheme,
    required this.isBusy,
    this.onCancel,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: isBusy || onCancel == null ? null : onCancel,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(tr('Отмена')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: trailing ??
                const SizedBox(
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
