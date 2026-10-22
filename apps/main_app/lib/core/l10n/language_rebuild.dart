import 'package:flutter/widgets.dart';

import 'l10n.dart';

/// Пересобирает экран при смене языка.
///
/// `tr()` — глобальная функция без BuildContext, поэтому язык меняется в
/// словаре, а не в виджетах. Обычно этого достаточно: `_AppState.build`
/// слушает `appLanguageProvider`, пересобирает `MaterialApp`, и перерисовка
/// каскадом доходит даже в надстроенные маршруты (измерено в
/// `test/core/l10n/language_rebuild_mechanism_test.dart`). Миксин — страховка
/// для поддеревьев, которые пересборка корня не накрывает: он подписан на
/// извещение `L10n.setCurrent` и перерисовывает себя сам.
///
/// setState сохраняет навигацию и локальное состояние редакторов — в отличие
/// от пересоздания MaterialApp с новым key, которое сбрасывало бы пользователя
/// на главный экран и топило несохранённую работу.
mixin LanguageRebuild<W extends StatefulWidget> on State<W> {
  @override
  void initState() {
    super.initState();
    L10n.addListener(_rebuild);
  }

  @override
  void dispose() {
    L10n.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }
}
